#include "scfde_modem.h"
#include "scfde_fft.h"
#include "scfde_ldpc.h"
#include <math.h>
#include <string.h>

/**
 * @file scfde_modem.c
 * @brief Fixed-profile SC-FDE transmitter and receiver processing chain.
 *
 * Baseline scheme (SCFDE_LDPC_ENABLED == 0):
 *   payload -> header/CRC -> QPSK -> three-UW frame
 *   -> 12 kHz real passband samples (rectangular pulses).
 *
 * Receive path:
 *   ADC DC removal/downconversion -> sample-phase and UW search -> three-UW
 *   time-varying CFO correction -> LS channel estimate -> MMSE-FDE
 *   -> QPSK hard decisions -> header/CRC.
 *
 * Re-enabling SCFDE_LDPC_ENABLED inserts LDPC(192,128) encode/decode around
 * the QPSK block and restores the 16-byte coded packet.
 *
 * All large work arrays are static to keep stack use predictable on the MCU.
 * The module is therefore deliberately non-reentrant.
 */

#define SCFDE_PI                    3.14159265358979323846f
#define SCFDE_PACKET_CRC_INDEX      (SCFDE_PACKET_BYTES - 2u)
#define SCFDE_CHANNEL_TAPS          28u
#define SCFDE_TX_AMPLITUDE          700
#define SCFDE_SYNC_THRESHOLD        0.18f
#define SCFDE_MAX_RX_SYMBOLS        ((SCFDE_RX_CAPTURE_LENGTH / SCFDE_RX_SAMPLES_PER_SYMBOL) + 1u)

static const int16_t g_carrier_cos[8] = {256, 181, 0, -181, -256, -181, 0, 181};
static const int16_t g_carrier_sin[8] = {0, 181, 256, 181, 0, -181, -256, -181};

static scfde_complex_t g_uw[SCFDE_UW_LENGTH];              /* Known Chu training sequence. */
static scfde_complex_t g_tx_data[SCFDE_DATA_SYMBOLS];      /* Prepared QPSK payload. */
static scfde_complex_t g_phase_symbols[SCFDE_MAX_RX_SYMBOLS]; /* One candidate sample phase. */
static scfde_complex_t g_frame_symbols[SCFDE_FRAME_SYMBOLS]; /* Best synchronized frame. */
static scfde_complex_t g_fft_a[SCFDE_FFT_SIZE];            /* Estimated channel H[k]. */
static scfde_complex_t g_fft_b[SCFDE_FFT_SIZE];            /* Equalizer input/output block. */
#if SCFDE_LDPC_ENABLED
static uint8_t g_tx_code_bits[SCFDE_LDPC_CODE_BITS];
#endif
static scfde_equalizer_mode_t g_equalizer_mode = SCFDE_EQUALIZER_MMSE_FDE;

static scfde_complex_t scfde_complex_multiply(scfde_complex_t a, scfde_complex_t b)
{
    scfde_complex_t result;
    result.re = a.re * b.re - a.im * b.im;
    result.im = a.re * b.im + a.im * b.re;
    return result;
}

static scfde_complex_t scfde_complex_conjugate(scfde_complex_t a)
{
    a.im = -a.im;
    return a;
}

static float scfde_complex_power(scfde_complex_t a)
{
    return a.re * a.re + a.im * a.im;
}

static uint16_t scfde_crc16_ccitt(const uint8_t *data, uint16_t length)
{
    uint16_t crc = 0xFFFFu;
    uint16_t i;

    for(i = 0u; i < length; i++)
    {
        uint8_t bit;
        crc ^= (uint16_t)data[i] << 8u;
        for(bit = 0u; bit < 8u; bit++)
        {
            if((crc & 0x8000u) != 0u)
            {
                crc = (uint16_t)((crc << 1u) ^ 0x1021u);
            }
            else
            {
                crc <<= 1u;
            }
        }
    }
    return crc;
}

void scfde_modem_init(void)
{
    uint16_t n;

    scfde_fft_init();
    for(n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        float angle = -SCFDE_PI * (float)(n * n) / (float)SCFDE_UW_LENGTH;
        g_uw[n].re = cosf(angle);
        g_uw[n].im = sinf(angle);
    }
    memset(g_tx_data, 0, sizeof(g_tx_data));
}

void scfde_modem_set_equalizer(scfde_equalizer_mode_t mode)
{
    if((uint8_t)mode < (uint8_t)SCFDE_EQUALIZER_COUNT)
    {
        g_equalizer_mode = mode;
    }
}

scfde_equalizer_mode_t scfde_modem_get_equalizer(void)
{
    return g_equalizer_mode;
}

uint8_t scfde_modem_prepare_tx(const uint8_t *payload, uint8_t length, uint8_t sequence)
{
    uint8_t packet[SCFDE_PACKET_BYTES];
    uint16_t crc;
    uint16_t symbol;
    uint16_t bit;

    if((length > SCFDE_MAX_PAYLOAD) || ((length > 0u) && (payload == 0)))
    {
        return 0u;
    }

    /* The systematic QPSK input is exactly one packet:
       magic(2), length(1), sequence(1), payload/padding, CRC16(2). */
    memset(packet, 0, sizeof(packet));
    packet[0] = 0xA5u;
    packet[1] = 0x5Au;
    packet[2] = length;
    packet[3] = sequence;
    if(length > 0u)
    {
        memcpy(&packet[4], payload, length);
    }
    crc = scfde_crc16_ccitt(packet, SCFDE_PACKET_CRC_INDEX);
    packet[SCFDE_PACKET_CRC_INDEX] = (uint8_t)(crc >> 8u);
    packet[SCFDE_PACKET_CRC_INDEX + 1u] = (uint8_t)crc;

#if SCFDE_LDPC_ENABLED
    {
        uint8_t info_bits[SCFDE_LDPC_INFO_BITS];
        /* Bits are unpacked least-significant-bit first to match the QPSK
           mapper and the packet reconstruction in the receiver. */
        memset(info_bits, 0, sizeof(info_bits));
        for(bit = 0u; bit < SCFDE_LDPC_INFO_BITS; bit++)
        {
            info_bits[bit] = (uint8_t)((packet[bit >> 3u] >> (bit & 7u)) & 1u);
        }
        scfde_ldpc_encode(info_bits, g_tx_code_bits);
        for(symbol = 0u; symbol < SCFDE_DATA_SYMBOLS; symbol++)
        {
            uint16_t bit_index = symbol * 2u;
            uint8_t first = g_tx_code_bits[bit_index];
            bit_index++;
            g_tx_data[symbol].re = first != 0u ? 1.0f : -1.0f;
            g_tx_data[symbol].im = g_tx_code_bits[bit_index] != 0u ? 1.0f : -1.0f;
        }
    }
#else
    /* Baseline: map the packet bits directly to QPSK (bit 0 -> I, bit 1 -> Q,
       bit value 1 -> positive component). */
    for(symbol = 0u; symbol < SCFDE_DATA_SYMBOLS; symbol++)
    {
        uint16_t bit_index = symbol * 2u;
        uint8_t first = (uint8_t)((packet[bit_index >> 3u] >> (bit_index & 7u)) & 1u);
        bit_index++;
        uint8_t second = (uint8_t)((packet[bit_index >> 3u] >> (bit_index & 7u)) & 1u);
        g_tx_data[symbol].re = first != 0u ? 1.0f : -1.0f;
        g_tx_data[symbol].im = second != 0u ? 1.0f : -1.0f;
    }
#endif
    return 1u;
}

uint32_t scfde_modem_get_tx_sample_length(void)
{
    return SCFDE_FRAME_SYMBOLS * SCFDE_TX_SAMPLES_PER_SYMBOL;
}

static scfde_complex_t scfde_get_tx_symbol(uint16_t symbol_index)
{
    if(symbol_index < (2u * SCFDE_UW_LENGTH))
    {
        return g_uw[symbol_index % SCFDE_UW_LENGTH];
    }
    if(symbol_index < (2u * SCFDE_UW_LENGTH + SCFDE_DATA_SYMBOLS))
    {
        return g_tx_data[symbol_index - 2u * SCFDE_UW_LENGTH];
    }
    return g_uw[symbol_index - 2u * SCFDE_UW_LENGTH - SCFDE_DATA_SYMBOLS];
}

int16_t scfde_modem_get_tx_sample(uint32_t index)
{
    uint16_t symbol_index;
    uint8_t carrier_index;
    scfde_complex_t symbol;
    int32_t mixed;

    if(index >= scfde_modem_get_tx_sample_length())
    {
        return 0;
    }
    /* 12 kHz at 96 kHz gives an exact eight-sample carrier period. The lookup
       oscillator avoids sinf/cosf inside the real-time DAC sample loop. */
    symbol_index = (uint16_t)(index / SCFDE_TX_SAMPLES_PER_SYMBOL);
    carrier_index = (uint8_t)(index & 7u);
    symbol = scfde_get_tx_symbol(symbol_index);
    mixed = (int32_t)(symbol.re * (float)g_carrier_cos[carrier_index]) -
            (int32_t)(symbol.im * (float)g_carrier_sin[carrier_index]);
    return (int16_t)((mixed * SCFDE_TX_AMPLITUDE) / 256);
}

static scfde_complex_t scfde_correlate_uw(const scfde_complex_t *symbols)
{
    scfde_complex_t correlation = {0.0f, 0.0f};
    uint16_t n;

    for(n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        scfde_complex_t product = scfde_complex_multiply(symbols[n], scfde_complex_conjugate(g_uw[n]));
        correlation.re += product.re;
        correlation.im += product.im;
    }
    return correlation;
}

static float scfde_sync_metric(const scfde_complex_t *symbols)
{
    scfde_complex_t first = scfde_correlate_uw(symbols);
    scfde_complex_t second = scfde_correlate_uw(symbols + SCFDE_UW_LENGTH);
    float energy = 0.0f;
    uint16_t n;

    for(n = 0u; n < (2u * SCFDE_UW_LENGTH); n++)
    {
        energy += scfde_complex_power(symbols[n]);
    }
    if(energy < 1.0e-12f)
    {
        return 0.0f;
    }
    /* Energy normalization makes the threshold largely independent of ADC
       gain. Two repeated UWs reduce false acquisition on payload data. */
    return (scfde_complex_power(first) + scfde_complex_power(second)) /
           ((float)SCFDE_UW_LENGTH * energy);
}

static float scfde_phase_difference(scfde_complex_t later, scfde_complex_t earlier,
                                    uint16_t symbol_gap)
{
    scfde_complex_t cross = scfde_complex_multiply(later,
                                                   scfde_complex_conjugate(earlier));
    return atan2f(cross.im, cross.re) / (float)symbol_gap;
}

static void scfde_estimate_frequency_offsets(float *start_offset,
                                             float *end_offset)
{
    scfde_complex_t first = scfde_correlate_uw(g_frame_symbols);
    scfde_complex_t second = scfde_correlate_uw(g_frame_symbols + SCFDE_UW_LENGTH);
    scfde_complex_t third = scfde_correlate_uw(
        g_frame_symbols + (2u * SCFDE_UW_LENGTH) + SCFDE_DATA_SYMBOLS);
    /* UW1/UW2 estimate the phase rate near frame start. UW2/UW3 estimate the
       rate across the data block. Their difference models linear Doppler drift. */
    float first_rate = scfde_phase_difference(second, first, SCFDE_UW_LENGTH);
    float last_rate = scfde_phase_difference(
        third, second, SCFDE_UW_LENGTH + SCFDE_DATA_SYMBOLS);

    if(start_offset != 0)
    {
        *start_offset = first_rate;
    }
    if(end_offset != 0)
    {
        *end_offset = last_rate;
    }
}

static void scfde_correct_frequency_offset(float start_radians_per_symbol,
                                            float end_radians_per_symbol)
{
    uint16_t n;
    float frame_last = (float)(SCFDE_FRAME_SYMBOLS - 1u);
    float slope = (end_radians_per_symbol - start_radians_per_symbol) / frame_last;

    /* Integrating a linearly changing phase rate produces the quadratic phase
       term below: phi[n]=w0*n+0.5*slope*n^2. */
    for(n = 0u; n < SCFDE_FRAME_SYMBOLS; n++)
    {
        float symbol = (float)n;
        float angle = -(start_radians_per_symbol * symbol +
                        0.5f * slope * symbol * symbol);
        scfde_complex_t rotation;
        rotation.re = cosf(angle);
        rotation.im = sinf(angle);
        g_frame_symbols[n] = scfde_complex_multiply(g_frame_symbols[n], rotation);
    }
}

static float scfde_build_channel_response(void)
{
    float difference_energy = 0.0f;
    float channel_power = 0.0f;
    uint16_t n;

    /* LS estimate on UW2: H32[k]=Yuw[k]*conj(Xuw[k])/|Xuw[k]|^2. */
    memset(g_fft_a, 0, sizeof(g_fft_a));
    memset(g_fft_b, 0, sizeof(g_fft_b));
    for(n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        scfde_complex_t difference;
        g_fft_a[n] = g_uw[n];
        g_fft_b[n] = g_frame_symbols[SCFDE_UW_LENGTH + n];
        if(n >= SCFDE_CHANNEL_TAPS)
        {
            difference.re = g_frame_symbols[n].re - g_frame_symbols[SCFDE_UW_LENGTH + n].re;
            difference.im = g_frame_symbols[n].im - g_frame_symbols[SCFDE_UW_LENGTH + n].im;
            difference_energy += scfde_complex_power(difference);
        }
    }
    scfde_fft(g_fft_a, SCFDE_UW_LENGTH, 0u);
    scfde_fft(g_fft_b, SCFDE_UW_LENGTH, 0u);
    for(n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        float denominator = scfde_complex_power(g_fft_a[n]) + 1.0e-9f;
        scfde_complex_t numerator = scfde_complex_multiply(g_fft_b[n], scfde_complex_conjugate(g_fft_a[n]));
        g_fft_b[n].re = numerator.re / denominator;
        g_fft_b[n].im = numerator.im / denominator;
    }
    scfde_fft(g_fft_b, SCFDE_UW_LENGTH, 1u);

    /* Transform to delay, discard taps outside the configured channel span,
       zero-pad to 128, and transform back to obtain H[k] for the data block. */
    memset(g_fft_a, 0, sizeof(g_fft_a));
    for(n = 0u; n < SCFDE_CHANNEL_TAPS; n++)
    {
        g_fft_a[n] = g_fft_b[n];
    }
    scfde_fft(g_fft_a, SCFDE_FFT_SIZE, 0u);
    for(n = 0u; n < SCFDE_FFT_SIZE; n++)
    {
        channel_power += scfde_complex_power(g_fft_a[n]);
    }

    /* The non-channel tail of the repeated-UW difference estimates complex
       noise power. Scale it to the unnormalized FFT domain used by Y[k]. */
    difference_energy *= 0.5f / (float)(SCFDE_UW_LENGTH - SCFDE_CHANNEL_TAPS);
    difference_energy *= (float)SCFDE_FFT_SIZE / 2.0f;
    if(difference_energy < channel_power * 0.002f / (float)SCFDE_FFT_SIZE)
    {
        /* A stronger floor prevents deep channel nulls from amplifying
           the ADC/noise floor during MMSE equalization. */
        difference_energy = channel_power * 0.01f / (float)SCFDE_FFT_SIZE;
    }
    return difference_energy;
}

static void scfde_equalize_data(float regularization, scfde_equalizer_mode_t mode)
{
    uint16_t n;

    for(n = 0u; n < SCFDE_FFT_SIZE; n++)
    {
        g_fft_b[n] = g_frame_symbols[2u * SCFDE_UW_LENGTH + n];
    }
    /* NLMS-TDE consumes time-domain symbols directly. All other fixed modes
       operate on the circular 128-symbol DATA|UW3 block through H[k]. */
    if(mode == SCFDE_EQUALIZER_NLMS_TDE)
    {
        scfde_equalizer_nlms_tde(g_fft_b, SCFDE_FFT_SIZE,
                                 &g_frame_symbols[SCFDE_UW_LENGTH],
                                 g_uw, SCFDE_UW_LENGTH);
        return;
    }
    scfde_equalizer_apply(mode, g_fft_a, g_fft_b, regularization,
                          SCFDE_FFT_SIZE, SCFDE_DATA_SYMBOLS,
                          g_uw, SCFDE_UW_LENGTH);
}

static uint8_t scfde_demodulate_packet(uint8_t *packet)
{
    uint16_t symbol;
    uint16_t bit;

    memset(packet, 0, SCFDE_PACKET_BYTES);
#if SCFDE_LDPC_ENABLED
    {
        float llr[SCFDE_LDPC_CODE_BITS];
        uint8_t decoded[SCFDE_LDPC_INFO_BITS];
        for(symbol = 0u; symbol < SCFDE_DATA_SYMBOLS; symbol++)
        {
            uint16_t bit_index = symbol * 2u;
            /* The transmitter maps bit 1 to positive I/Q. The decoder uses
               negative LLR for bit 1. */
            llr[bit_index] = -g_fft_b[symbol].re;
            llr[bit_index + 1u] = -g_fft_b[symbol].im;
        }
        /* LLR magnitude is intentionally left in equalizer output units. The
           min-sum decoder depends primarily on sign and relative reliability. */
        if(scfde_ldpc_decode(llr, decoded, 10u) == 0u)
        {
            return 0u;
        }
        for(bit = 0u; bit < SCFDE_LDPC_INFO_BITS; bit++)
        {
            if(decoded[bit] != 0u)
            {
                packet[bit >> 3u] |= (uint8_t)(1u << (bit & 7u));
            }
        }
    }
#else
    /* Baseline: hard decision per component. A positive component carries
       bit 1 (matches the transmitter mapping and the LLR convention). */
    for(bit = 0u; bit < (uint16_t)(SCFDE_DATA_SYMBOLS * 2u); bit++)
    {
        uint16_t sym = bit >> 1u;
        float value = ((bit & 1u) == 0u) ? g_fft_b[sym].re : g_fft_b[sym].im;
        if(value > 0.0f)
        {
            packet[bit >> 3u] |= (uint8_t)(1u << (bit & 7u));
        }
    }
#endif
    return 1u;
}

static uint8_t scfde_packet_is_valid(const uint8_t *packet)
{
    uint16_t received_crc;

    if((packet[0] != 0xA5u) || (packet[1] != 0x5Au) || (packet[2] > SCFDE_MAX_PAYLOAD))
    {
        return 0u;
    }
    received_crc = (uint16_t)(((uint16_t)packet[SCFDE_PACKET_CRC_INDEX] << 8u) |
                              packet[SCFDE_PACKET_CRC_INDEX + 1u]);
    return scfde_crc16_ccitt(packet, SCFDE_PACKET_CRC_INDEX) == received_crc ? 1u : 0u;
}

scfde_rx_result_t scfde_modem_decode(const uint16_t *samples, uint32_t sample_count)
{
    scfde_rx_result_t result;
    float midpoint = 0.0f;
    float best_metric = 0.0f;
    uint32_t best_sample = 0u;
    uint8_t phase;
    uint32_t i;
    uint8_t packet[SCFDE_PACKET_BYTES];
    float frequency_radians_start;
    float frequency_radians_end;
    float regularization;

    memset(&result, 0, sizeof(result));
    result.equalizer_used = SCFDE_EQUALIZER_MMSE_FDE;
    if((samples == 0) || (sample_count < (SCFDE_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)))
    {
        return result;
    }
    if(sample_count > SCFDE_RX_CAPTURE_LENGTH)
    {
        sample_count = SCFDE_RX_CAPTURE_LENGTH;
    }
    /* Stage 1: estimate and remove the ADC midpoint. */
    for(i = 0u; i < sample_count; i++)
    {
        midpoint += (float)samples[i];
    }
    midpoint /= (float)sample_count;

    /* Stage 2: test every integrate-and-dump sample phase. For each phase,
       downconvert at 12 kHz and search all frame-length symbol windows. */
    for(phase = 0u; phase < SCFDE_RX_SAMPLES_PER_SYMBOL; phase++)
    {
        uint32_t symbol_count = (sample_count - phase) / SCFDE_RX_SAMPLES_PER_SYMBOL;
        uint32_t symbol;

        if(symbol_count > SCFDE_MAX_RX_SYMBOLS)
        {
            symbol_count = SCFDE_MAX_RX_SYMBOLS;
        }
        for(symbol = 0u; symbol < symbol_count; symbol++)
        {
            float in_phase = 0.0f;
            float quadrature = 0.0f;
            uint8_t k;
            uint32_t start = phase + symbol * SCFDE_RX_SAMPLES_PER_SYMBOL;
            for(k = 0u; k < SCFDE_RX_SAMPLES_PER_SYMBOL; k++)
            {
                uint32_t sample_index = start + k;
                float value = (float)samples[sample_index] - midpoint;
                uint8_t carrier = (uint8_t)(sample_index & 3u);
                static const int8_t cos4[4] = {1, 0, -1, 0};
                static const int8_t sin4[4] = {0, 1, 0, -1};
                in_phase += value * (float)cos4[carrier];
                quadrature -= value * (float)sin4[carrier];
            }
            g_phase_symbols[symbol].re = in_phase;
            g_phase_symbols[symbol].im = quadrature;
        }

        if(symbol_count >= SCFDE_FRAME_SYMBOLS)
        {
            uint32_t offset;
            for(offset = 0u; offset <= (symbol_count - SCFDE_FRAME_SYMBOLS); offset++)
            {
                float metric = scfde_sync_metric(&g_phase_symbols[offset]);
                if(metric > best_metric)
                {
                    best_metric = metric;
                    best_sample = phase + offset * SCFDE_RX_SAMPLES_PER_SYMBOL;
                    memcpy(g_frame_symbols, &g_phase_symbols[offset], sizeof(g_frame_symbols));
                }
            }
        }
    }

    result.sync_metric = best_metric;
    result.frame_start_sample = best_sample;
    if(best_metric < SCFDE_SYNC_THRESHOLD)
    {
        return result;
    }

    /* Stage 3: track residual carrier/Doppler phase from all three UWs. */
    scfde_estimate_frequency_offsets(&frequency_radians_start, &frequency_radians_end);
    result.frequency_offset_hz = 0.5f * (frequency_radians_start + frequency_radians_end) *
                                 (float)SCFDE_SYMBOL_RATE_HZ / (2.0f * SCFDE_PI);
    scfde_correct_frequency_offset(frequency_radians_start, frequency_radians_end);
    /* Stage 4: construct H[k] and a noise regularization estimate from UW2. */
    regularization = scfde_build_channel_response();
    /* Stage 5: baseline MMSE-FDE, then hard decisions, header, and CRC. */
    scfde_equalize_data(regularization, SCFDE_EQUALIZER_MMSE_FDE);
    if((scfde_demodulate_packet(packet) != 0u) && (scfde_packet_is_valid(packet) != 0u))
    {
        result.payload_length = packet[2];
        result.sequence = packet[3];
        if(result.payload_length > 0u)
        {
            memcpy(result.payload, &packet[4], result.payload_length);
        }
        result.crc_ok = 1u;
        result.valid = 1u;
    }
    return result;
}
