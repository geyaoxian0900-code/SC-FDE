/* scfde_csk.c - Chapter-6 CSK modem (cyclic-shift keying spread spectrum)
 * ported from the MATLAB equalizer package (book 6.1-6.3).
 *
 * The MATLAB link uses a 28-chip root sequence (the channel length) with
 * M=4 cyclic shifts; the firmware uses an 8-chip root so the frame fits the
 * 8192-sample RX capture (48 symbols x 8 chips = 384 chips). The algorithm
 * structure (shift codebook, circular dictionary, matched filter, soft SIC
 * iterations, ESE fallback) matches the MATLAB ch6 family. */

#include "scfde_csk.h"
#include <math.h>
#include <string.h>

#define SCFDE_CSK_PI       3.14159265358979323846f
#define SCFDE_CSK_TAPS     28u
#define SCFDE_CSK_M        4u

static const int16_t g_carrier_cos[8] = {256, 181, 0, -181, -256, -181, 0, 181};
static const int16_t g_carrier_sin[8] = {0, 181, 256, 181, 0, -181, -256, -181};

/* Deterministic low-sidelobe +/-1 root (max cyclic sidelobe 4/8), chosen by
   exhaustive search over the 256 length-8 sequences. */
static const float g_root_raw[SCFDE_CSK_CODE_LENGTH] = {
    1.0f, 1.0f, 1.0f, -1.0f, -1.0f, -1.0f, -1.0f, -1.0f
};

static scfde_complex_t g_root[SCFDE_CSK_CODE_LENGTH];       /* unit-energy root. */
static scfde_complex_t g_book[SCFDE_CSK_M][SCFDE_CSK_CODE_LENGTH];
static scfde_complex_t g_dict[SCFDE_CSK_M][SCFDE_CSK_CODE_LENGTH]; /* circular h*book. */
static scfde_complex_t g_uw[SCFDE_UW_LENGTH];
static scfde_complex_t g_tx_symbols[SCFDE_CSK_FRAME_SYMBOLS];
static scfde_complex_t g_phase_symbols[SCFDE_CSK_RX_MAX_SYMBOLS];
static scfde_complex_t g_frame[SCFDE_CSK_FRAME_SYMBOLS];
static scfde_complex_t g_symbols[SCFDE_CSK_SYMBOLS][SCFDE_CSK_CODE_LENGTH];
static scfde_complex_t g_impulse[SCFDE_CSK_TAPS];

static uint8_t g_packet[SCFDE_CSK_PACKET_BYTES];

static scfde_complex_t csk_mul(scfde_complex_t a, scfde_complex_t b)
{
    scfde_complex_t r;
    r.re = a.re * b.re - a.im * b.im;
    r.im = a.re * b.im + a.im * b.re;
    return r;
}

static scfde_complex_t csk_conj(scfde_complex_t a)
{
    a.im = -a.im;
    return a;
}

static float csk_power(scfde_complex_t a)
{
    return a.re * a.re + a.im * a.im;
}

static uint16_t csk_crc16(const uint8_t *data, uint16_t length)
{
    uint16_t crc = 0xFFFFu;
    uint16_t i;
    for (i = 0u; i < length; i++)
    {
        uint8_t bit;
        crc ^= (uint16_t)data[i] << 8u;
        for (bit = 0u; bit < 8u; bit++)
        {
            if ((crc & 0x8000u) != 0u) { crc = (uint16_t)((crc << 1u) ^ 0x1021u); }
            else { crc <<= 1u; }
        }
    }
    return crc;
}

void scfde_csk_init(void)
{
    uint16_t n, s, c;

    scfde_fft_init();
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        float angle = -SCFDE_CSK_PI * (float)(n * n) / (float)SCFDE_UW_LENGTH;
        g_uw[n].re = cosf(angle);
        g_uw[n].im = sinf(angle);
    }
    for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
    {
        g_root[c].re = g_root_raw[c] * 0.35355339f;
        g_root[c].im = 0.0f;
    }
    for (s = 0u; s < SCFDE_CSK_M; s++)
    {
        for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
        {
            g_book[s][c] = g_root[(c + s) % SCFDE_CSK_CODE_LENGTH];
        }
    }
    memset(g_tx_symbols, 0, sizeof(g_tx_symbols));
}

uint8_t scfde_csk_prepare_tx(const uint8_t *payload, uint8_t length, uint8_t sequence)
{
    uint16_t n, c;
    uint16_t crc;

    if ((length > SCFDE_CSK_MAX_PAYLOAD) || ((length > 0u) && (payload == 0)))
    {
        return 0u;
    }
    memset(g_packet, 0, sizeof(g_packet));
    g_packet[0] = 0xA5u;
    g_packet[1] = 0x5Au;
    g_packet[2] = length;
    g_packet[3] = sequence;
    if (length > 0u) { memcpy(&g_packet[4], payload, length); }
    crc = csk_crc16(g_packet, SCFDE_CSK_PACKET_CRC_INDEX);
    g_packet[SCFDE_CSK_PACKET_CRC_INDEX] = (uint8_t)(crc >> 8u);
    g_packet[SCFDE_CSK_PACKET_CRC_INDEX + 1u] = (uint8_t)crc;

    for (n = 0u; n < 2u * SCFDE_UW_LENGTH; n++)
    {
        g_tx_symbols[n] = g_uw[n % SCFDE_UW_LENGTH];
    }
    /* Map 2 bits per symbol (LSB first) to the cyclic-shift index. */
    for (n = 0u; n < SCFDE_CSK_SYMBOLS; n++)
    {
        uint16_t packet_bit = n * SCFDE_CSK_ORDER;
        uint8_t b0 = (uint8_t)((g_packet[packet_bit >> 3u] >> (packet_bit & 7u)) & 1u);
        uint8_t b1 = (uint8_t)((g_packet[(packet_bit + 1u) >> 3u] >>
                                ((packet_bit + 1u) & 7u)) & 1u);
        uint16_t shift = (uint16_t)(b0 + 2u * b1);
        for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
        {
            g_tx_symbols[2u * SCFDE_UW_LENGTH + n * SCFDE_CSK_CODE_LENGTH + c] =
                g_book[shift][c];
        }
    }
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        g_tx_symbols[2u * SCFDE_UW_LENGTH + SCFDE_CSK_CHIPS + n] = g_uw[n];
    }
    return 1u;
}

uint32_t scfde_csk_get_tx_sample_length(void)
{
    return SCFDE_CSK_FRAME_SYMBOLS * SCFDE_TX_SAMPLES_PER_SYMBOL;
}

int16_t scfde_csk_get_tx_sample(uint32_t index)
{
    uint16_t symbol_index;
    uint8_t carrier_index;
    scfde_complex_t symbol;
    int32_t mixed;

    if (index >= scfde_csk_get_tx_sample_length()) { return 0; }
    symbol_index = (uint16_t)(index / SCFDE_TX_SAMPLES_PER_SYMBOL);
    carrier_index = (uint8_t)(index & 7u);
    symbol = g_tx_symbols[symbol_index];
    mixed = (int32_t)(symbol.re * (float)g_carrier_cos[carrier_index]) -
            (int32_t)(symbol.im * (float)g_carrier_sin[carrier_index]);
    return (int16_t)((mixed * 700) / 256);
}

/* ------------------------- receive chain ------------------------- */

static scfde_complex_t csk_correlate_uw(const scfde_complex_t *symbols)
{
    scfde_complex_t corr = {0.0f, 0.0f};
    uint16_t n;
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        scfde_complex_t p = csk_mul(symbols[n], csk_conj(g_uw[n]));
        corr.re += p.re;
        corr.im += p.im;
    }
    return corr;
}

static float csk_sync_metric(const scfde_complex_t *symbols)
{
    scfde_complex_t first = csk_correlate_uw(symbols);
    scfde_complex_t second = csk_correlate_uw(symbols + SCFDE_UW_LENGTH);
    float energy = 0.0f;
    uint16_t n;
    for (n = 0u; n < 2u * SCFDE_UW_LENGTH; n++)
    {
        energy += csk_power(symbols[n]);
    }
    if (energy < 1.0e-12f) { return 0.0f; }
    return (csk_power(first) + csk_power(second)) / ((float)SCFDE_UW_LENGTH * energy);
}

static float csk_phase_diff(scfde_complex_t later, scfde_complex_t earlier,
                            uint16_t gap)
{
    scfde_complex_t cross = csk_mul(later, csk_conj(earlier));
    return atan2f(cross.im, cross.re) / (float)gap;
}

static float csk_build_channel(void)
{
    scfde_complex_t a[SCFDE_UW_LENGTH], b[SCFDE_UW_LENGTH];
    uint16_t n;

    memset(a, 0, sizeof(a));
    memset(b, 0, sizeof(b));
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        a[n] = g_uw[n];
        b[n] = g_frame[SCFDE_UW_LENGTH + n];
    }
    scfde_fft(a, SCFDE_UW_LENGTH, 0u);
    scfde_fft(b, SCFDE_UW_LENGTH, 0u);
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        float den = csk_power(a[n]) + 1.0e-9f;
        scfde_complex_t num = csk_mul(b[n], csk_conj(a[n]));
        b[n].re = num.re / den;
        b[n].im = num.im / den;
    }
    scfde_fft(b, SCFDE_UW_LENGTH, 1u);
    memset(g_impulse, 0, sizeof(g_impulse));
    for (n = 0u; n < SCFDE_CSK_TAPS; n++)
    {
        g_impulse[n] = b[n];
    }
    {
        float energy = 0.0f;
        float scale;
        for (n = 0u; n < SCFDE_CSK_TAPS; n++)
        {
            energy += csk_power(g_impulse[n]);
        }
        scale = sqrtf(energy);
        if (scale < 1.0e-9f) { scale = 1.0f; }
        for (n = 0u; n < SCFDE_CSK_TAPS; n++)
        {
            g_impulse[n].re /= scale;
            g_impulse[n].im /= scale;
        }
        return scale;
    }
}

/* dictionary = circular convolution of the codebook with the channel. */
static void csk_build_dictionary(void)
{
    uint16_t s, c, j;
    for (s = 0u; s < SCFDE_CSK_M; s++)
    {
        for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
        {
            g_dict[s][c].re = 0.0f;
            g_dict[s][c].im = 0.0f;
            for (j = 0u; j < SCFDE_CSK_TAPS; j++)
            {
                scfde_complex_t v = g_book[s][(c + SCFDE_CSK_CODE_LENGTH - j) %
                                              SCFDE_CSK_CODE_LENGTH];
                scfde_complex_t p = csk_mul(g_impulse[j], v);
                g_dict[s][c].re += p.re;
                g_dict[s][c].im += p.im;
            }
        }
    }
}

/* hard dictionary detect: argmin |dict - obs|^2. */
static uint16_t csk_hard_detect(const scfde_complex_t *obs, scfde_complex_t *expected_out)
{
    uint16_t s, c;
    float best = 1.0e30f;
    uint16_t best_index = 0u;
    for (s = 0u; s < SCFDE_CSK_M; s++)
    {
        float dist = 0.0f;
        for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
        {
            float dr = obs[c].re - g_dict[s][c].re;
            float di = obs[c].im - g_dict[s][c].im;
            dist += dr * dr + di * di;
        }
        if (dist < best) { best = dist; best_index = s; }
    }
    if (expected_out != 0)
    {
        for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
        {
            expected_out[c] = g_dict[best_index][c];
        }
    }
    return best_index;
}

/* soft dictionary detect: weighted average of dictionary entries. */
static void csk_soft_detect(const scfde_complex_t *obs, float noise_variance,
                            uint16_t *decision_out, scfde_complex_t *soft_out)
{
    uint16_t s, c;
    float distances[SCFDE_CSK_M];
    float weights[SCFDE_CSK_M];
    float best_dist = 1.0e30f;
    float weight_sum = 0.0f;
    uint16_t best_index = 0u;

    if (noise_variance < 1.0e-8f) { noise_variance = 1.0e-8f; }
    for (s = 0u; s < SCFDE_CSK_M; s++)
    {
        float dist = 0.0f;
        for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
        {
            float dr = obs[c].re - g_dict[s][c].re;
            float di = obs[c].im - g_dict[s][c].im;
            dist += dr * dr + di * di;
        }
        distances[s] = dist;
        if (dist < best_dist) { best_dist = dist; best_index = s; }
    }
    for (s = 0u; s < SCFDE_CSK_M; s++)
    {
        weights[s] = 1.0f / (1.0f + (distances[s] - best_dist) / noise_variance);
        weight_sum += weights[s];
    }
    for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
    {
        soft_out[c].re = 0.0f;
        soft_out[c].im = 0.0f;
        for (s = 0u; s < SCFDE_CSK_M; s++)
        {
            float w = weights[s] / weight_sum;
            soft_out[c].re += w * g_dict[s][c].re;
            soft_out[c].im += w * g_dict[s][c].im;
        }
    }
    *decision_out = best_index;
}

static void csk_receive_mf(uint16_t *detected)
{
    uint16_t n;
    for (n = 0u; n < SCFDE_CSK_SYMBOLS; n++)
    {
        detected[n] = csk_hard_detect(g_symbols[n], 0);
    }
}

/* soft SIC (book 6.2.2): single user, 4 iterations of soft detection with
   the residual (no co-user interference here) and 0.45/0.55 smoothing. */
static void csk_receive_soft_sic(uint16_t *detected)
{
    scfde_complex_t soft[SCFDE_CSK_SYMBOLS][SCFDE_CSK_CODE_LENGTH];
    uint16_t n, c, iter;

    memset(soft, 0, sizeof(soft));
    for (iter = 0u; iter < 4u; iter++)
    {
        for (n = 0u; n < SCFDE_CSK_SYMBOLS; n++)
        {
            scfde_complex_t expected[SCFDE_CSK_CODE_LENGTH];
            uint16_t decision;
            csk_soft_detect(g_symbols[n], 0.001f, &decision, expected);
            detected[n] = decision;
            for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
            {
                soft[n][c].re = 0.45f * soft[n][c].re + 0.55f * expected[c].re;
                soft[n][c].im = 0.45f * soft[n][c].im + 0.55f * expected[c].im;
            }
        }
    }
}

/* ESE (book 6.3): the C firmware receiver is single-user, so the
   multiuser IDMA iterations (mean cancellation, interference variance,
   repeated soft detection) of ch6_csk_idma_detect cannot run; the
   single-user ESE reduces to SOFT-POSTERIOR detection (distance ->
   normalized weights -> posterior-mean soft chips -> decision), i.e.
   it is NOT a matched filter.  Each symbol is soft-detected with a
   short smoothing loop over the soft chips. */
static void csk_receive_ese(uint16_t *detected)
{
    uint16_t n, c, iter;
    scfde_complex_t soft[SCFDE_CSK_SYMBOLS][SCFDE_CSK_CODE_LENGTH];
    memset(soft, 0, sizeof(soft));
    for (iter = 0u; iter < 2u; iter++)
    {
        for (n = 0u; n < SCFDE_CSK_SYMBOLS; n++)
        {
            scfde_complex_t expected[SCFDE_CSK_CODE_LENGTH];
            uint16_t decision;
            csk_soft_detect(g_symbols[n], 0.001f, &decision, expected);
            detected[n] = decision;
            for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
            {
                soft[n][c].re = 0.5f * soft[n][c].re + 0.5f * expected[c].re;
                soft[n][c].im = 0.5f * soft[n][c].im + 0.5f * expected[c].im;
            }
        }
    }
}

static void csk_packet_from_indices(const uint16_t *detected)
{
    uint16_t bit;
    memset(g_packet, 0, sizeof(g_packet));
    for (bit = 0u; bit < SCFDE_CSK_SYMBOLS * SCFDE_CSK_ORDER; bit++)
    {
        uint16_t symbol_index = bit / SCFDE_CSK_ORDER;
        uint16_t bit_in_symbol = bit % SCFDE_CSK_ORDER;
        uint8_t value = (uint8_t)((detected[symbol_index] >> bit_in_symbol) & 1u);
        if (value != 0u)
        {
            g_packet[bit >> 3u] |= (uint8_t)(1u << (bit & 7u));
        }
    }
}

static uint8_t csk_packet_is_valid(uint8_t *length_out)
{
    uint16_t received_crc;
    if ((g_packet[0] != 0xA5u) || (g_packet[1] != 0x5Au) ||
        (g_packet[2] > SCFDE_CSK_MAX_PAYLOAD))
    {
        return 0u;
    }
    received_crc = (uint16_t)(((uint16_t)g_packet[SCFDE_CSK_PACKET_CRC_INDEX] << 8u) |
                              g_packet[SCFDE_CSK_PACKET_CRC_INDEX + 1u]);
    if (csk_crc16(g_packet, SCFDE_CSK_PACKET_CRC_INDEX) != received_crc)
    {
        return 0u;
    }
    *length_out = g_packet[2];
    return 1u;
}

scfde_rx_result_t scfde_csk_decode(const uint16_t *samples, uint32_t sample_count,
                                   scfde_csk_receiver_t receiver)
{
    scfde_rx_result_t result;
    uint16_t detected[SCFDE_CSK_SYMBOLS];
    float midpoint = 0.0f;
    float best_metric = 0.0f;
    uint32_t best_sample = 0u;
    float start_rate, end_rate;
    uint8_t phase;
    uint32_t i;
    uint16_t n, c;
    uint8_t length_out = 0u;

    memset(&result, 0, sizeof(result));
    if ((samples == 0) ||
        (sample_count < (SCFDE_CSK_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)))
    {
        return result;
    }
    if (sample_count > SCFDE_RX_CAPTURE_LENGTH) { sample_count = SCFDE_RX_CAPTURE_LENGTH; }
    for (i = 0u; i < sample_count; i++) { midpoint += (float)samples[i]; }
    midpoint /= (float)sample_count;

    for (phase = 0u; phase < SCFDE_RX_SAMPLES_PER_SYMBOL; phase++)
    {
        uint32_t symbol_count = (sample_count - phase) / SCFDE_RX_SAMPLES_PER_SYMBOL;
        uint32_t symbol;
        if (symbol_count > SCFDE_CSK_RX_MAX_SYMBOLS) { symbol_count = SCFDE_CSK_RX_MAX_SYMBOLS; }
        for (symbol = 0u; symbol < symbol_count; symbol++)
        {
            float in_phase = 0.0f, quadrature = 0.0f;
            uint8_t k;
            uint32_t start = phase + symbol * SCFDE_RX_SAMPLES_PER_SYMBOL;
            for (k = 0u; k < SCFDE_RX_SAMPLES_PER_SYMBOL; k++)
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
        if (symbol_count >= SCFDE_CSK_FRAME_SYMBOLS)
        {
            uint32_t offset;
            for (offset = 0u; offset <= (symbol_count - SCFDE_CSK_FRAME_SYMBOLS); offset++)
            {
                float metric = csk_sync_metric(&g_phase_symbols[offset]);
                if (metric > best_metric)
                {
                    best_metric = metric;
                    best_sample = phase + offset * SCFDE_RX_SAMPLES_PER_SYMBOL;
                    memcpy(g_frame, &g_phase_symbols[offset],
                           SCFDE_CSK_FRAME_SYMBOLS * sizeof(scfde_complex_t));
                }
            }
        }
    }
    result.sync_metric = best_metric;
    result.frame_start_sample = best_sample;
    if (best_metric < 0.18f) { return result; }

    {
        scfde_complex_t first = csk_correlate_uw(g_frame);
        scfde_complex_t second = csk_correlate_uw(g_frame + SCFDE_UW_LENGTH);
        scfde_complex_t third = csk_correlate_uw(
            g_frame + 2u * SCFDE_UW_LENGTH + SCFDE_CSK_CHIPS);
        start_rate = csk_phase_diff(second, first, SCFDE_UW_LENGTH);
        end_rate = csk_phase_diff(third, second,
                                  SCFDE_UW_LENGTH + SCFDE_CSK_CHIPS);
    }
    result.frequency_offset_hz = 0.5f * (start_rate + end_rate) *
                                 (float)SCFDE_SYMBOL_RATE_HZ / (2.0f * SCFDE_CSK_PI);
    {
        float slope = (end_rate - start_rate) / (float)(SCFDE_CSK_FRAME_SYMBOLS - 1u);
        for (n = 0u; n < SCFDE_CSK_FRAME_SYMBOLS; n++)
        {
            float symbol = (float)n;
            float angle = -(start_rate * symbol + 0.5f * slope * symbol * symbol);
            scfde_complex_t rotation;
            rotation.re = cosf(angle);
            rotation.im = sinf(angle);
            g_frame[n] = csk_mul(g_frame[n], rotation);
        }
    }

    {
        float h_scale = csk_build_channel();
        csk_build_dictionary();
        if (h_scale < 1.0e-9f) { h_scale = 1.0f; }
        for (n = 0u; n < SCFDE_CSK_SYMBOLS; n++)
        {
            for (c = 0u; c < SCFDE_CSK_CODE_LENGTH; c++)
            {
                g_symbols[n][c] = g_frame[2u * SCFDE_UW_LENGTH +
                                          n * SCFDE_CSK_CODE_LENGTH + c];
                g_symbols[n][c].re /= h_scale;
                g_symbols[n][c].im /= h_scale;
            }
        }
    }

    switch (receiver)
    {
    case SCFDE_CSK_RX_MF:
    default:
        csk_receive_mf(detected);
        break;
    case SCFDE_CSK_RX_SOFT_SIC:
        csk_receive_soft_sic(detected);
        break;
    case SCFDE_CSK_RX_ESE:
        csk_receive_ese(detected);
        break;
    }

    csk_packet_from_indices(detected);
    if (csk_packet_is_valid(&length_out) != 0u)
    {
        result.payload_length = length_out;
        result.sequence = g_packet[3];
        memcpy(result.payload, &g_packet[4], length_out);
        result.crc_ok = 1u;
        result.valid = 1u;
    }
    result.equalizer_used = (scfde_equalizer_mode_t)(
        (uint8_t)SCFDE_EQUALIZER_CSK_MF + (uint8_t)receiver);
    return result;
}

const char *scfde_csk_receiver_name(scfde_csk_receiver_t receiver)
{
    static const char *const names[3] = {
        "CSK-MF", "CSK-SOFT-SIC", "CSK-ESE"
    };
    if ((uint8_t)receiver > 2u) { return "UNKNOWN"; }
    return names[(uint8_t)receiver];
}
