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
static scfde_complex_t g_impulse_hold[SCFDE_UW_LENGTH];    /* LS impulse copy for A-grade equalizers. */
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
    /* Time-domain DFE family consumes the full symbol stream. All other
       modes operate on the circular 128-symbol DATA|UW3 block through H[k]. */
    switch(mode)
    {
    case SCFDE_EQUALIZER_DFE:
    case SCFDE_EQUALIZER_LMS_DFE:
    case SCFDE_EQUALIZER_NLMS_DFE:
    case SCFDE_EQUALIZER_RLS_DFE:
    case SCFDE_EQUALIZER_DPLL_DFE:
    case SCFDE_EQUALIZER_FBLMS:
    case SCFDE_EQUALIZER_FDDA_TEQ:
    case SCFDE_EQUALIZER_TDDA_TEQ:
    case SCFDE_EQUALIZER_FDDA_DFE_TEQ:
        scfde_equalizer_dfe(mode, g_frame_symbols, SCFDE_FRAME_SYMBOLS,
                            g_uw, g_impulse_hold, SCFDE_CHANNEL_TAPS,
                            regularization, SCFDE_DATA_SYMBOLS, g_fft_b);
        break;
    case SCFDE_EQUALIZER_HTFDE:
    case SCFDE_EQUALIZER_SD_IBDFE:
    case SCFDE_EQUALIZER_HD_IBDFE:
    case SCFDE_EQUALIZER_ICE_SD_IBDFE:
    case SCFDE_EQUALIZER_ICE_HD_IBDFE:
        scfde_equalizer_apply_a(mode, g_fft_a, g_impulse_hold, g_fft_b,
                                regularization, SCFDE_FFT_SIZE,
                                SCFDE_DATA_SYMBOLS, g_uw, SCFDE_UW_LENGTH,
                                &g_frame_symbols[SCFDE_UW_LENGTH]);
        break;
    case SCFDE_EQUALIZER_NLMS_TDE:
    {
        /* Scale the training reference to the actual I&D symbol amplitude:
           g_uw is unit magnitude but the received symbols integrate ~12x350
           samples, so an unscaled reference would shrink the data output
           and corrupt the hard decisions. */
        static scfde_complex_t nlms_ref[SCFDE_UW_LENGTH];
        float scale = 0.0f;
        for (n = 0u; n < SCFDE_UW_LENGTH; n++)
        {
            scale += sqrtf(scfde_complex_power(
                g_frame_symbols[SCFDE_UW_LENGTH + n]));
        }
        scale /= (float)SCFDE_UW_LENGTH;
        if (scale < 1.0e-6f) { scale = 1.0f; }
        for (n = 0u; n < SCFDE_UW_LENGTH; n++)
        {
            nlms_ref[n].re = g_uw[n].re * scale;
            nlms_ref[n].im = g_uw[n].im * scale;
        }
        scfde_equalizer_nlms_tde(g_fft_b, SCFDE_FFT_SIZE,
                                 &g_frame_symbols[SCFDE_UW_LENGTH],
                                 nlms_ref, SCFDE_UW_LENGTH);
        break;
    }
    default:
        scfde_equalizer_apply(mode, g_fft_a, g_fft_b, regularization,
                              SCFDE_FFT_SIZE, SCFDE_DATA_SYMBOLS,
                              g_uw, SCFDE_UW_LENGTH);
        break;
    }
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
    memcpy(g_impulse_hold, g_fft_b, SCFDE_UW_LENGTH * sizeof(scfde_complex_t));
    /* Stage 5: equalize with the selected mode, then hard decisions,
       header, and CRC. */
    scfde_equalize_data(regularization, g_equalizer_mode);
    result.equalizer_used = g_equalizer_mode;
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

/* ------------------------------------------------------------------ */
/* Chapter-4 turbo mode (B1 core): conv code + interleaver + BCJR     */
/* ------------------------------------------------------------------ */

uint8_t scfde_modem_prepare_tx_turbo(const uint8_t *payload, uint8_t length,
                                     uint8_t sequence)
{
    uint8_t packet[SCFDE_TURBO_PACKET_BYTES];
    uint8_t info_bits[SCFDE_TURBO_INFO_BITS];
    uint8_t code_bits[SCFDE_TURBO_CODE_BITS];
    uint8_t interleaved[SCFDE_TURBO_CODE_BITS];
    uint16_t bit;
    uint16_t symbol;
    uint16_t crc;

    if((length > SCFDE_TURBO_MAX_PAYLOAD) ||
       ((length > 0u) && (payload == 0)))
    {
        return 0u;
    }
    memset(packet, 0, sizeof(packet));
    packet[0] = 0xA5u;
    packet[1] = 0x5Au;
    packet[2] = length;
    packet[3] = sequence;
    if(length > 0u)
    {
        memcpy(&packet[4], payload, length);
    }
    crc = scfde_crc16_ccitt(packet, SCFDE_TURBO_CRC_INDEX);
    packet[SCFDE_TURBO_CRC_INDEX] = (uint8_t)(crc >> 8u);
    packet[SCFDE_TURBO_CRC_INDEX + 1u] = (uint8_t)crc;

    for(bit = 0u; bit < SCFDE_TURBO_INFO_BITS; bit++)
    {
        info_bits[bit] = (uint8_t)((packet[bit >> 3u] >> (bit & 7u)) & 1u);
    }
    scfde_turbo_conv_encode(info_bits, code_bits);
    scfde_turbo_interleave(code_bits, interleaved);
    for(symbol = 0u; symbol < SCFDE_DATA_SYMBOLS; symbol++)
    {
        uint16_t bit_index = symbol * 2u;
        g_tx_data[symbol].re = interleaved[bit_index] ? 1.0f : -1.0f;
        g_tx_data[symbol].im = interleaved[bit_index + 1u] ? 1.0f : -1.0f;
    }
    return 1u;
}

static void turbo_iterate(scfde_equalizer_mode_t mode,
                          const scfde_complex_t *channel,
                          const scfde_complex_t *block,
                          float noise_variance,
                          uint16_t size,
                          uint16_t data_symbols,
                          const scfde_complex_t *tail_uw,
                          uint16_t tail_length,
                          float *info_llr_out,
                          uint8_t *info_bits_out);

scfde_rx_result_t scfde_modem_decode_turbo_mode(scfde_equalizer_mode_t mode,
                                           const uint16_t *samples,
                                           uint32_t sample_count)
{
    scfde_rx_result_t result;
    float midpoint = 0.0f;
    float best_metric = 0.0f;
    uint32_t best_sample = 0u;
    uint8_t phase;
    uint32_t i;
    float frequency_radians_start;
    float frequency_radians_end;
    float regularization;
    uint8_t packet[SCFDE_TURBO_PACKET_BYTES];
    float info_llr[SCFDE_TURBO_INFO_BITS];
    uint8_t info_bits[SCFDE_TURBO_INFO_BITS];
    uint16_t bit;

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
    /* Stage 1: DC removal. */
    for(i = 0u; i < sample_count; i++)
    {
        midpoint += (float)samples[i];
    }
    midpoint /= (float)sample_count;
    /* Stage 2: sample-phase + UW search (same as the base decoder). */
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
    /* Stage 3: CFO correction. */
    scfde_estimate_frequency_offsets(&frequency_radians_start, &frequency_radians_end);
    result.frequency_offset_hz = 0.5f * (frequency_radians_start + frequency_radians_end) *
                                 (float)SCFDE_SYMBOL_RATE_HZ / (2.0f * SCFDE_PI);
    scfde_correct_frequency_offset(frequency_radians_start, frequency_radians_end);
    /* Stage 4: LS channel estimate only (the turbo kernel equalizes). */
    regularization = scfde_build_channel_response();
    memcpy(g_impulse_hold, g_fft_b, SCFDE_UW_LENGTH * sizeof(scfde_complex_t));
    /* Stage 5: turbo decode on the RAW DATA|UW3 block. */
    {
        static scfde_complex_t rx_block[SCFDE_FFT_SIZE];
        for(bit = 0u; bit < SCFDE_FFT_SIZE; bit++)
        {
            rx_block[bit] = g_frame_symbols[2u * SCFDE_UW_LENGTH + bit];
        }
        turbo_iterate(mode, g_fft_a, rx_block,
                      regularization, SCFDE_FFT_SIZE, SCFDE_DATA_SYMBOLS,
                      g_uw, SCFDE_UW_LENGTH, info_llr, info_bits);
    }
    memset(packet, 0, sizeof(packet));
    for(bit = 0u; bit < SCFDE_TURBO_INFO_BITS; bit++)
    {
        if(info_bits[bit])
        {
            packet[bit >> 3u] |= (uint8_t)(1u << (bit & 7u));
        }
    }
    if((packet[0] == 0xA5u) && (packet[1] == 0x5Au) &&
       (packet[2] <= SCFDE_TURBO_MAX_PAYLOAD))
    {
        uint16_t received_crc = (uint16_t)(((uint16_t)packet[SCFDE_TURBO_CRC_INDEX] << 8u) |
                                            packet[SCFDE_TURBO_CRC_INDEX + 1u]);
        if(scfde_crc16_ccitt(packet, SCFDE_TURBO_CRC_INDEX) == received_crc)
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
    }
    return result;
}

/* ------------------------------------------------------------------ */
/* Chapter-4 turbo family: unified frequency-domain iterative kernel.  */
/* The 128-symbol DATA|UW3 block is circular (UW protected), so the     */
/* time-domain LMMSE reduces to the frequency-domain MMSE (diagonal    */
/* channel). All variants share: sync, LS, MMSE pre-equalization,       */
/* then BCJR soft feedback iterations.                                  */
/* ------------------------------------------------------------------ */

#define TURBO_ITERATIONS 4u
#define TURBO_DAMPING    0.75f

static scfde_complex_t g_turbo_soft[SCFDE_FFT_SIZE];
static scfde_complex_t g_turbo_spectrum[SCFDE_FFT_SIZE];
static scfde_complex_t g_turbo_work[SCFDE_FFT_SIZE];
static scfde_complex_t g_turbo_h[SCFDE_FFT_SIZE];

static void turbo_iterate(scfde_equalizer_mode_t mode,
                          const scfde_complex_t *channel,
                          const scfde_complex_t *block,
                          float noise_variance,
                          uint16_t size,
                          uint16_t data_symbols,
                          const scfde_complex_t *tail_uw,
                          uint16_t tail_length,
                          float *info_llr_out,
                          uint8_t *info_bits_out);

/* Run one turbo equalization-decoding pass. Returns the info bits.
   mode: 0=fd-turbo(IBDFE), 1=fd-dfe(hard FB, single decode),
         2=tf-turbo(MMSE+IBDFE avg), 3=bitf-turbo(+reverse),
         4=blms-tf-turbo(adaptive W), 5=td-turbo(MMSE) */
static void turbo_iterate(scfde_equalizer_mode_t mode,
                          const scfde_complex_t *channel,
                          const scfde_complex_t *block,
                          float noise_variance,
                          uint16_t size,
                          uint16_t data_symbols,
                          const scfde_complex_t *tail_uw,
                          uint16_t tail_length,
                          float *info_llr_out,
                          uint8_t *info_bits_out)
{
    uint16_t iter, n, bit;
    float rho = 0.0f;
    scfde_complex_t *y = g_turbo_spectrum;
    scfde_complex_t *soft = g_turbo_soft;
    scfde_complex_t *estimate = g_turbo_work;
    static float coded_llr[SCFDE_TURBO_CODE_BITS];
    static float info_llr[SCFDE_TURBO_INFO_BITS];
    static float coded_post[SCFDE_TURBO_CODE_BITS];
    static uint8_t info_bits[SCFDE_TURBO_INFO_BITS];
    static scfde_complex_t soft_data[SCFDE_DATA_SYMBOLS];

    (void)tail_length;
    /* Y = FFT(DATA|UW3) */
    memcpy(estimate, block, size * sizeof(scfde_complex_t));
    scfde_fft(estimate, size, 0u);
    memcpy(y, estimate, size * sizeof(scfde_complex_t));
    /* initial soft: data zero, tail locked to known UW */
    memset(soft, 0, size * sizeof(scfde_complex_t));
    for (n = 0u; n < tail_length; n++)
    {
        soft[data_symbols + n] = tail_uw[n];
    }

    for (iter = 0u; iter < TURBO_ITERATIONS; iter++)
    {
        float mean_power = 0.0f;
        for (n = 0u; n < size; n++)
        {
            mean_power += soft[n].re * soft[n].re + soft[n].im * soft[n].im;
        }
        mean_power /= (float)size;
        rho = mean_power < 0.995f ? mean_power : 0.995f;

        /* feedback spectrum */
        memcpy(g_turbo_work, soft, size * sizeof(scfde_complex_t));
        scfde_fft(g_turbo_work, size, 0u);

        if (mode == SCFDE_EQUALIZER_FD_DFE)
        {
            /* hard-decision feedback, single pass (W = MMSE normalized) */
            scfde_complex_t fb_spec[SCFDE_FFT_SIZE];
            for (n = 0u; n < size; n++)
            {
                scfde_complex_t w;
                float p = scfde_complex_power(channel[n]);
                float den = p + noise_variance;
                if (den < 1.0e-12f) { den = 1.0e-12f; }
                /* pure MMSE coefficient: W = conj(H)/(|H|^2+nu) */
                w.re = channel[n].re / den;
                w.im = -channel[n].im / den;
                /* B = W*H - 1; store W*Y for the feedback pass */
                fb_spec[n].re = w.re * channel[n].re - w.im * channel[n].im - 1.0f;
                fb_spec[n].im = w.re * channel[n].im + w.im * channel[n].re;
                estimate[n].re = w.re * y[n].re - w.im * y[n].im;
                estimate[n].im = w.re * y[n].im + w.im * y[n].re;
            }
            for (n = 0u; n < size; n++)
            {
                scfde_complex_t fb = scfde_complex_multiply(fb_spec[n], g_turbo_work[n]);
                estimate[n].re -= fb.re;
                estimate[n].im -= fb.im;
            }
        }
        else
        {
            /* IBDFE weights (4-56..4-58) */
            float sum_inv = 0.0f, sum_ratio = 0.0f;
            float lambda;
            scfde_complex_t w, b;
            for (n = 0u; n < size; n++)
            {
                float p = scfde_complex_power(channel[n]);
                float den = noise_variance + p - rho * p;
                if (den < 1.0e-12f) { den = 1.0e-12f; }
                sum_inv += 1.0f / den;
                sum_ratio += (noise_variance + p) / den;
            }
            lambda = (sum_ratio > 1.0e-12f) ?
                     noise_variance * sum_inv / sum_ratio : 0.0f;
            for (n = 0u; n < size; n++)
            {
                float p = scfde_complex_power(channel[n]);
                float den = noise_variance + p - rho * p;
                if (den < 1.0e-12f) { den = 1.0e-12f; }
                b.re = (lambda * (noise_variance + p) - noise_variance) / den;
                b.im = 0.0f;
                w.re = (channel[n].re * (1.0f + b.re)) / (noise_variance + p);
                w.im = (-channel[n].im * (1.0f + b.re)) / (noise_variance + p);
                if (mode == SCFDE_EQUALIZER_TF_TURBO ||
                    mode == SCFDE_EQUALIZER_BITF_TURBO ||
                    mode == SCFDE_EQUALIZER_TD_TURBO)
                {
                    /* time-domain LMMSE == frequency MMSE here; tf/bitf/td
                       average the MMSE and IBDFE estimates */
                    scfde_complex_t wm, fb;
                    wm.re = channel[n].re / (noise_variance + p);
                    wm.im = -channel[n].im / (noise_variance + p);
                    fb = scfde_complex_multiply(w, channel[n]);
                    estimate[n].re = 0.5f * (wm.re * y[n].re - wm.im * y[n].im +
                        w.re * y[n].re - w.im * y[n].im - fb.re * g_turbo_work[n].re +
                        fb.im * g_turbo_work[n].im + g_turbo_work[n].re);
                    estimate[n].im = 0.5f * (wm.re * y[n].im + wm.im * y[n].re +
                        w.re * y[n].im + w.im * y[n].re - fb.re * g_turbo_work[n].im -
                        fb.im * g_turbo_work[n].re + g_turbo_work[n].im);
                    continue;
                }
                estimate[n].re = w.re * y[n].re - w.im * y[n].im -
                                 b.re * g_turbo_work[n].re;
                estimate[n].im = w.re * y[n].im + w.im * y[n].re -
                                 b.re * g_turbo_work[n].im;
            }
            if (mode == SCFDE_EQUALIZER_BLMS_TF_TURBO)
            {
                /* adaptive weight update (leaky BLMS): operate on a local
                   copy of the channel (the caller buffer is const) */
                memcpy(g_turbo_h, channel, size * sizeof(scfde_complex_t));
                for (n = 0u; n < size; n++)
                {
                    estimate[n].re = 0.0f; estimate[n].im = 0.0f;
                }
                scfde_complex_t residual[SCFDE_FFT_SIZE];
                for (n = 0u; n < size; n++)
                {
                    residual[n].re = soft[n].re - estimate[n].re;
                    residual[n].im = soft[n].im - estimate[n].im;
                }
                scfde_fft(residual, size, 0u);
                for (n = 0u; n < size; n++)
                {
                    float py = scfde_complex_power(y[n]);
                    float den = py + 1.0e-3f;
                    scfde_complex_t num;
                    num.re = y[n].re * residual[n].re + y[n].im * residual[n].im;
                    num.im = y[n].re * residual[n].im - y[n].im * residual[n].re;
                    g_turbo_h[n].re = 0.999f * g_turbo_h[n].re +
                                    0.06f * num.re / den;
                    g_turbo_h[n].im = 0.999f * g_turbo_h[n].im +
                                    0.06f * num.im / den;
                }
                /* re-equalize with the updated channel (MMSE) */
                for (n = 0u; n < size; n++)
                {
                    float p = scfde_complex_power(channel[n]);
                    float den = p + noise_variance;
                    if (den < 1.0e-12f) { den = 1.0e-12f; }
                    estimate[n].re = (y[n].re * channel[n].re +
                                      y[n].im * channel[n].im) / den;
                    estimate[n].im = (y[n].im * channel[n].re -
                                      y[n].re * channel[n].im) / den;
                }
            }
        }

        scfde_fft(estimate, size, 1u);
        /* reverse direction for bitf-turbo: average with reversed estimate */
        if (mode == SCFDE_EQUALIZER_BITF_TURBO)
        {
            scfde_complex_t reverse[SCFDE_FFT_SIZE];
            scfde_complex_t rev_soft[SCFDE_FFT_SIZE];
            uint16_t r;
            for (r = 0u; r < size; r++)
            {
                reverse[r] = block[size - 1u - r];
                rev_soft[r] = soft[size - 1u - r];
            }
            scfde_fft(reverse, size, 0u);
            scfde_fft(rev_soft, size, 0u);
            for (r = 0u; r < size; r++)
            {
                float p = scfde_complex_power(channel[r]);
                float den = p + noise_variance;
                if (den < 1.0e-12f) { den = 1.0e-12f; }
                reverse[r].re = (reverse[r].re * channel[r].re +
                                 reverse[r].im * channel[r].im) / den;
                reverse[r].im = (reverse[r].im * channel[r].re -
                                 reverse[r].re * channel[r].im) / den;
            }
            scfde_fft(reverse, size, 1u);
            for (r = 0u; r < size; r++)
            {
                scfde_complex_t rev = reverse[size - 1u - r];
                estimate[r].re = 0.5f * (estimate[r].re + rev.re);
                estimate[r].im = 0.5f * (estimate[r].im + rev.im);
            }
        }

        /* coded LLRs from the data symbols */
        for (bit = 0u; bit < SCFDE_TURBO_CODE_BITS; bit++)
        {
            uint16_t sym = (uint16_t)(bit / 2u);
            coded_llr[bit] = ((bit & 1u) == 0u) ?
                estimate[sym].re : estimate[sym].im;
        }
        scfde_turbo_deinterleave(coded_llr, coded_llr);
        scfde_turbo_bcjr_ext(coded_llr, info_llr, coded_post, info_bits, 0u);
        scfde_turbo_interleave_f(coded_post, coded_post);
        scfde_turbo_soft_symbols(coded_post, soft_data);
        /* rebuild soft frame with damping; tail UW locked */
        for (n = 0u; n < data_symbols; n++)
        {
            soft[n].re = (1.0f - TURBO_DAMPING) * soft[n].re +
                         TURBO_DAMPING * soft_data[n].re;
            soft[n].im = (1.0f - TURBO_DAMPING) * soft[n].im +
                         TURBO_DAMPING * soft_data[n].im;
        }
        for (n = 0u; n < tail_length; n++)
        {
            soft[data_symbols + n] = tail_uw[n];
        }
    }

    if (info_llr_out != 0)
    {
        memcpy(info_llr_out, info_llr, SCFDE_TURBO_INFO_BITS * sizeof(float));
    }
    memcpy(info_bits_out, info_bits, SCFDE_TURBO_INFO_BITS);
}

scfde_rx_result_t scfde_modem_decode_turbo(const uint16_t *samples,
                                           uint32_t sample_count)
{
    return scfde_modem_decode_turbo_mode(SCFDE_EQUALIZER_FD_TURBO,
                                         samples, sample_count);
}
