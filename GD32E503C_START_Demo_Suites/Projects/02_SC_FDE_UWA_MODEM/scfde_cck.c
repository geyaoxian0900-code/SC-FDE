/* scfde_cck.c - Chapter-5 CCK modem (IEEE 802.11b complementary-code
 * keying, FR-CCK 8-bit words) ported from the MATLAB equalizer package.
 *
 * Frame: UW1(32) | UW2(32) | 16 CCK words (128 chips) | UW3(32) = 224 symbols.
 * The Chu UW, carrier profile, and sample rates match the baseline modem so
 * the same BSP and PC test infrastructure apply. Each 8-bit word maps to one
 * of 256 CCK code words (8 QPSK chips, unit energy); the seven receivers are
 * the MATLAB ch5 family: MFB, Rake, DFE (candidate list 128), BiDFE-1,
 * BiDFE-2 (refinement), TR diversity (2-47), and FDE-IBDFE (5-80). */

#include "scfde_cck.h"
#include <math.h>
#include <string.h>

#define SCFDE_CCK_PI       3.14159265358979323846f
#define SCFDE_CCK_TAPS     28u

static const int16_t g_carrier_cos[8] = {256, 181, 0, -181, -256, -181, 0, 181};
static const int16_t g_carrier_sin[8] = {0, 181, 256, 181, 0, -181, -256, -181};

static scfde_complex_t g_book[SCFDE_CCK_BOOK_SIZE][8];  /* 256 x 8 unit-energy words. */
static scfde_complex_t g_uw[SCFDE_UW_LENGTH];           /* Chu training (same as baseline). */
static scfde_complex_t g_tx_symbols[SCFDE_CCK_FRAME_SYMBOLS]; /* Prepared frame. */
static scfde_complex_t g_phase_symbols[SCFDE_CCK_RX_MAX_SYMBOLS];
static scfde_complex_t g_frame[SCFDE_CCK_FRAME_SYMBOLS];
static scfde_complex_t g_data[SCFDE_CCK_CHIPS];         /* CFO-corrected data chips. */
static scfde_complex_t g_impulse[SCFDE_CCK_TAPS];       /* LS channel impulse. */
static scfde_complex_t g_work[SCFDE_FFT_SIZE * 2u];     /* FDE workspace (2 blocks). */
static scfde_complex_t g_trd[SCFDE_CCK_FRAME_SYMBOLS];  /* TR diversity combined. */
static scfde_complex_t g_trd_focused[SCFDE_CCK_FRAME_SYMBOLS + SCFDE_CCK_TAPS];

static uint8_t g_packet[SCFDE_CCK_PACKET_BYTES];

static scfde_complex_t cck_mul(scfde_complex_t a, scfde_complex_t b)
{
    scfde_complex_t r;
    r.re = a.re * b.re - a.im * b.im;
    r.im = a.re * b.im + a.im * b.re;
    return r;
}

static scfde_complex_t cck_conj(scfde_complex_t a)
{
    a.im = -a.im;
    return a;
}

static float cck_power(scfde_complex_t a)
{
    return a.re * a.re + a.im * a.im;
}

static uint16_t cck_crc16(const uint8_t *data, uint16_t length)
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

void scfde_cck_init(void)
{
    uint16_t index, n;

    scfde_fft_init();
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        float angle = -SCFDE_CCK_PI * (float)(n * n) / (float)SCFDE_UW_LENGTH;
        g_uw[n].re = cosf(angle);
        g_uw[n].im = sinf(angle);
    }
    /* Codebook: row index 0..255, bits LSB first; four QPSK phases feed the
       CCK word construction with chip 4 and 7 sign-flipped, /sqrt(8). */
    for (index = 0u; index < SCFDE_CCK_BOOK_SIZE; index++)
    {
        uint8_t b[8];
        float phase[4];
        float angle[8];
        for (n = 0u; n < 8u; n++)
        {
            b[n] = (uint8_t)((index >> n) & 1u);
        }
        for (n = 0u; n < 4u; n++)
        {
            phase[n] = SCFDE_CCK_PI * (float)b[2u * n] +
                       0.5f * SCFDE_CCK_PI * (float)b[2u * n + 1u];
        }
        angle[0] = phase[0] + phase[1] + phase[2] + phase[3];
        angle[1] = phase[0] + phase[2] + phase[3];
        angle[2] = phase[0] + phase[1] + phase[3];
        angle[3] = phase[0] + phase[3];
        angle[4] = phase[0] + phase[1] + phase[2];
        angle[5] = phase[0] + phase[2];
        angle[6] = phase[0] + phase[1];
        angle[7] = phase[0];
        for (n = 0u; n < 8u; n++)
        {
            g_book[index][n].re = cosf(angle[n]) * 0.35355339f;
            g_book[index][n].im = sinf(angle[n]) * 0.35355339f;
        }
        g_book[index][3].re = -g_book[index][3].re;
        g_book[index][3].im = -g_book[index][3].im;
        g_book[index][6].re = -g_book[index][6].re;
        g_book[index][6].im = -g_book[index][6].im;
    }
    memset(g_tx_symbols, 0, sizeof(g_tx_symbols));
}

uint8_t scfde_cck_prepare_tx(const uint8_t *payload, uint8_t length, uint8_t sequence)
{
    uint16_t bit, chip, n;
    uint16_t crc;

    if ((length > SCFDE_CCK_MAX_PAYLOAD) || ((length > 0u) && (payload == 0)))
    {
        return 0u;
    }
    memset(g_packet, 0, sizeof(g_packet));
    g_packet[0] = 0xA5u;
    g_packet[1] = 0x5Au;
    g_packet[2] = length;
    g_packet[3] = sequence;
    if (length > 0u) { memcpy(&g_packet[4], payload, length); }
    crc = cck_crc16(g_packet, SCFDE_CCK_PACKET_CRC_INDEX);
    g_packet[SCFDE_CCK_PACKET_CRC_INDEX] = (uint8_t)(crc >> 8u);
    g_packet[SCFDE_CCK_PACKET_CRC_INDEX + 1u] = (uint8_t)crc;

    /* UW1 | UW2 | data words | UW3. */
    for (n = 0u; n < 2u * SCFDE_UW_LENGTH; n++)
    {
        g_tx_symbols[n] = g_uw[n % SCFDE_UW_LENGTH];
    }
    for (chip = 0u; chip < SCFDE_CCK_CHIPS; chip += 8u)
    {
        uint16_t word_index = 0u;
        for (bit = 0u; bit < 8u; bit++)
        {
            uint16_t packet_bit = chip + bit;
            uint8_t value = (uint8_t)((g_packet[packet_bit >> 3u] >> (packet_bit & 7u)) & 1u);
            word_index |= (uint16_t)(value << bit);
        }
        for (n = 0u; n < 8u; n++)
        {
            g_tx_symbols[2u * SCFDE_UW_LENGTH + chip + n] = g_book[word_index][n];
        }
    }
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        g_tx_symbols[2u * SCFDE_UW_LENGTH + SCFDE_CCK_CHIPS + n] = g_uw[n];
    }
    return 1u;
}

uint32_t scfde_cck_get_tx_sample_length(void)
{
    return SCFDE_CCK_FRAME_SYMBOLS * SCFDE_TX_SAMPLES_PER_SYMBOL;
}

int16_t scfde_cck_get_tx_sample(uint32_t index)
{
    uint16_t symbol_index;
    uint8_t carrier_index;
    scfde_complex_t symbol;
    int32_t mixed;

    if (index >= scfde_cck_get_tx_sample_length()) { return 0; }
    symbol_index = (uint16_t)(index / SCFDE_TX_SAMPLES_PER_SYMBOL);
    carrier_index = (uint8_t)(index & 7u);
    symbol = g_tx_symbols[symbol_index];
    mixed = (int32_t)(symbol.re * (float)g_carrier_cos[carrier_index]) -
            (int32_t)(symbol.im * (float)g_carrier_sin[carrier_index]);
    return (int16_t)((mixed * 700) / 256);
}

/* ------------------------- receive chain ------------------------- */

static scfde_complex_t cck_correlate_uw(const scfde_complex_t *symbols)
{
    scfde_complex_t corr = {0.0f, 0.0f};
    uint16_t n;
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        scfde_complex_t p = cck_mul(symbols[n], cck_conj(g_uw[n]));
        corr.re += p.re;
        corr.im += p.im;
    }
    return corr;
}

static float cck_sync_metric(const scfde_complex_t *symbols)
{
    scfde_complex_t first = cck_correlate_uw(symbols);
    scfde_complex_t second = cck_correlate_uw(symbols + SCFDE_UW_LENGTH);
    float energy = 0.0f;
    uint16_t n;
    for (n = 0u; n < 2u * SCFDE_UW_LENGTH; n++)
    {
        energy += cck_power(symbols[n]);
    }
    if (energy < 1.0e-12f) { return 0.0f; }
    return (cck_power(first) + cck_power(second)) / ((float)SCFDE_UW_LENGTH * energy);
}

static float cck_phase_diff(scfde_complex_t later, scfde_complex_t earlier,
                            uint16_t gap)
{
    scfde_complex_t cross = cck_mul(later, cck_conj(earlier));
    return atan2f(cross.im, cross.re) / (float)gap;
}

/* LS channel estimate from UW2, 28-tap impulse; also returns a noise
   variance estimate from the repeated-UW difference (as the baseline). */
static float cck_build_channel(float *noise_out)
{
    scfde_complex_t a[SCFDE_UW_LENGTH], b[SCFDE_UW_LENGTH];
    float difference_energy = 0.0f;
    float channel_power = 0.0f;
    uint16_t n;

    memset(a, 0, sizeof(a));
    memset(b, 0, sizeof(b));
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        scfde_complex_t d;
        a[n] = g_uw[n];
        b[n] = g_frame[SCFDE_UW_LENGTH + n];
        if (n >= SCFDE_CCK_TAPS)
        {
            d.re = g_frame[n].re - g_frame[SCFDE_UW_LENGTH + n].re;
            d.im = g_frame[n].im - g_frame[SCFDE_UW_LENGTH + n].im;
            difference_energy += cck_power(d);
        }
    }
    scfde_fft(a, SCFDE_UW_LENGTH, 0u);
    scfde_fft(b, SCFDE_UW_LENGTH, 0u);
    for (n = 0u; n < SCFDE_UW_LENGTH; n++)
    {
        float den = cck_power(a[n]) + 1.0e-9f;
        scfde_complex_t num = cck_mul(b[n], cck_conj(a[n]));
        b[n].re = num.re / den;
        b[n].im = num.im / den;
    }
    scfde_fft(b, SCFDE_UW_LENGTH, 1u);
    memset(g_impulse, 0, sizeof(g_impulse));
    for (n = 0u; n < SCFDE_CCK_TAPS; n++)
    {
        g_impulse[n] = b[n];
        channel_power += cck_power(b[n]);
    }
    {
        float noise = difference_energy * 0.5f /
                      (float)(SCFDE_UW_LENGTH - SCFDE_CCK_TAPS);
        if (noise < channel_power * 0.002f / (float)SCFDE_UW_LENGTH)
        {
            noise = channel_power * 0.01f / (float)SCFDE_UW_LENGTH;
        }
        *noise_out = noise;
    }
    return channel_power;
}

/* ----------------------- receivers (ch5) ------------------------ */

/* nearest_book: argmin_k |obs-book_k|^2 across the 256-word codebook. */
static void cck_nearest_book(const scfde_complex_t *observations,
                             uint16_t block_count, uint16_t *detected)
{
    uint16_t block, k, chip;
    for (block = 0u; block < block_count; block++)
    {
        float best = 1.0e30f;
        uint16_t best_index = 0u;
        const scfde_complex_t *obs = &observations[block * 8u];
        for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
        {
            float dist = 0.0f;
            for (chip = 0u; chip < 8u; chip++)
            {
                float dr = obs[chip].re - g_book[k][chip].re;
                float di = obs[chip].im - g_book[k][chip].im;
                dist += dr * dr + di * di;
            }
            if (dist < best) { best = dist; best_index = k; }
        }
        detected[block] = best_index;
    }
}

/* MFB: TR matched filter, aligned to the data block, then nearest book. */
static void cck_receive_mfb(uint16_t *detected)
{
    scfde_complex_t focused[SCFDE_CCK_CHIPS + SCFDE_CCK_TAPS];
    uint16_t n, m;

    memset(focused, 0, sizeof(focused));
    for (n = 0u; n < SCFDE_CCK_CHIPS + SCFDE_CCK_TAPS - 1u; n++)
    {
        for (m = 0u; m < SCFDE_CCK_TAPS; m++)
        {
            if ((m <= n) && ((n - m) < SCFDE_CCK_CHIPS))
            {
                scfde_complex_t tr;
                scfde_complex_t v;
                tr.re = g_impulse[SCFDE_CCK_TAPS - 1u - m].re;
                tr.im = -g_impulse[SCFDE_CCK_TAPS - 1u - m].im;
                v = cck_mul(tr, g_data[n - m]);
                focused[n].re += v.re;
                focused[n].im += v.im;
            }
        }
    }
    cck_nearest_book(&focused[SCFDE_CCK_TAPS - 1u], SCFDE_CCK_WORDS, detected);
}

/* Rake: per-tap chip correlation over each word window, normalized by
   the channel energy, then nearest book. */
static void cck_receive_rake(uint16_t *detected)
{
    scfde_complex_t combined[SCFDE_CCK_WORDS][8];
    float energy = 0.0f;
    uint16_t block, tap, chip;

    for (tap = 0u; tap < SCFDE_CCK_TAPS; tap++)
    {
        energy += cck_power(g_impulse[tap]);
    }
    if (energy < 1.0e-8f) { energy = 1.0e-8f; }
    for (block = 0u; block < SCFDE_CCK_WORDS; block++)
    {
        for (chip = 0u; chip < 8u; chip++)
        {
            combined[block][chip].re = 0.0f;
            combined[block][chip].im = 0.0f;
        }
        for (tap = 0u; tap < SCFDE_CCK_TAPS; tap++)
        {
            for (chip = 0u; chip < 8u; chip++)
            {
                uint16_t idx = block * 8u + chip + tap;
                if (idx < SCFDE_CCK_CHIPS + SCFDE_CCK_TAPS - 1u)
                {
                    scfde_complex_t v = (idx < SCFDE_CCK_CHIPS) ?
                                        g_data[idx] : (scfde_complex_t){0.0f, 0.0f};
                    scfde_complex_t c = cck_mul(cck_conj(g_impulse[tap]), v);
                    combined[block][chip].re += c.re;
                    combined[block][chip].im += c.im;
                }
            }
        }
        for (chip = 0u; chip < 8u; chip++)
        {
            combined[block][chip].re /= energy;
            combined[block][chip].im /= energy;
        }
    }
    cck_nearest_book(&combined[0][0], SCFDE_CCK_WORDS, detected);
}

/* expected_block: convolution of (state | word) with the channel, taking
   the memory+1..memory+8 window (the ISI-free part). input[i] = state[i]
   for i < memory, word[i-memory] otherwise. */
static void cck_expected_block(const scfde_complex_t *state,
                               const scfde_complex_t *word,
                               const scfde_complex_t *channel,
                               scfde_complex_t *output)
{
    uint16_t chip, tap;
    for (chip = 0u; chip < 8u; chip++)
    {
        output[chip].re = 0.0f;
        output[chip].im = 0.0f;
        for (tap = 0u; tap < SCFDE_CCK_TAPS; tap++)
        {
            int32_t idx = (int32_t)chip + (int32_t)SCFDE_CCK_TAPS - 1u - (int32_t)tap;
            scfde_complex_t v;
            if (idx < 0) { continue; }
            if (idx < (int32_t)(SCFDE_CCK_TAPS - 1u))
            {
                v = state[idx];
            }
            else
            {
                v = word[idx - (SCFDE_CCK_TAPS - 1u)];
            }
            {
                scfde_complex_t p = cck_mul(channel[tap], v);
                output[chip].re += p.re;
                output[chip].im += p.im;
            }
        }
    }
}

/* candidate list: 128 nearest code words by observation distance. */
static void cck_candidate_list(const scfde_complex_t *observation,
                               uint16_t *active)
{
    uint16_t order[SCFDE_CCK_BOOK_SIZE];
    uint16_t k, chip, i;
    for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
    {
        float dist = 0.0f;
        for (chip = 0u; chip < 8u; chip++)
        {
            float dr = observation[chip].re - g_book[k][chip].re;
            float di = observation[chip].im - g_book[k][chip].im;
            dist += dr * dr + di * di;
        }
        order[k] = k;
        if (k >= 128u)
        {
            uint16_t worst = 0u;
            float worst_dist = -1.0f;
            for (i = 0u; i < 128u; i++)
            {
                float d = 0.0f;
                uint16_t w = order[i];
                for (chip = 0u; chip < 8u; chip++)
                {
                    float dr = observation[chip].re - g_book[w][chip].re;
                    float di = observation[chip].im - g_book[w][chip].im;
                    d += dr * dr + di * di;
                }
                if (d > worst_dist) { worst_dist = d; worst = i; }
            }
            if (dist < worst_dist) { order[worst] = k; }
        }
    }
    for (i = 0u; i < 128u; i++)
    {
        active[i] = order[i];
    }
}

/* append_channel_state: new state = last 27 entries of [state, word8]. */
static void cck_append_state(scfde_complex_t *state, const scfde_complex_t *word)
{
    uint16_t c;
    for (c = 0u; c < SCFDE_CCK_TAPS - 9u; c++)
    {
        state[c] = state[c + 8u];
    }
    for (c = 0u; c < 8u; c++)
    {
        state[SCFDE_CCK_TAPS - 9u + c] = word[c];
    }
}

/* DFE core: candidate scores with channel-state feedback. reverse flips
   the stream, book rows, and channel (conj(fliplr(...))) for BiDFE; the
   reversed stream then needs a 27-chip observation offset because the
   flipped channel is causal from the far end (convolution delay of the
   time-reversed model). Blocks that fall off the stream end are skipped. */
static void cck_dfe_core(const scfde_complex_t *received, uint16_t block_count,
                         uint8_t reverse, float noise_variance,
                         uint16_t *detected,
                         float *scores /* block_count x 256, -1e30 elsewhere */)
{
    scfde_complex_t state[SCFDE_CCK_TAPS - 1u];
    scfde_complex_t channel[SCFDE_CCK_TAPS];
    uint16_t active[128u];
    uint16_t block, c, tap;

    memset(state, 0, sizeof(state));
    for (tap = 0u; tap < SCFDE_CCK_TAPS; tap++)
    {
        channel[tap] = reverse ? cck_conj(g_impulse[SCFDE_CCK_TAPS - 1u - tap])
                               : g_impulse[tap];
    }
    if (noise_variance < 1.0e-8f) { noise_variance = 1.0e-8f; }
    for (block = 0u; block < block_count; block++)
    {
        scfde_complex_t obs[8u];
        float best_score = -1.0e30f;
        uint16_t best_index = 0u;
        for (c = 0u; c < 8u; c++)
        {
            uint16_t src = (uint16_t)(reverse ? (SCFDE_CCK_CHIPS - 1u - (block * 8u + c))
                                              : (block * 8u + c));
            obs[c] = reverse ? cck_conj(received[src]) : received[src];
        }
        cck_candidate_list(obs, active);
        for (c = 0u; c < 128u; c++)
        {
            scfde_complex_t predicted[8u];
            scfde_complex_t word[8u];
            float score = 0.0f;
            uint16_t chip;
            for (chip = 0u; chip < 8u; chip++)
            {
                word[chip] = reverse ? cck_conj(g_book[active[c]][7u - chip])
                                     : g_book[active[c]][chip];
            }
            cck_expected_block(state, word, channel, predicted);
            for (chip = 0u; chip < 8u; chip++)
            {
                float dr = obs[chip].re - predicted[chip].re;
                float di = obs[chip].im - predicted[chip].im;
                score -= (dr * dr + di * di);
            }
            score /= noise_variance;
            if (scores != 0)
            {
                scores[block * SCFDE_CCK_BOOK_SIZE + active[c]] = score;
            }
            if (score > best_score) { best_score = score; best_index = active[c]; }
        }
        detected[block] = best_index;
        {
            scfde_complex_t word[8u];
            for (c = 0u; c < 8u; c++)
            {
                word[c] = reverse ? cck_conj(g_book[best_index][7u - c])
                                  : g_book[best_index][c];
            }
            cck_append_state(state, word);
        }
    }
}

static void cck_receive_dfe(uint16_t *detected)
{
    cck_dfe_core(g_data, SCFDE_CCK_WORDS, 0u, 0.001f, detected, 0);
}

/* fuse: forward + backward normalized scores, argmax. Rows where the
   backward scores carry no discrimination (the time-reversed channel
   model is degenerate, e.g. a short impulse) are dropped so the fusion
   degrades gracefully to the forward pass. */
static void cck_fuse_scores(const float *forward, const float *backward,
                            uint16_t *detected)
{
    uint16_t block, k;
    for (block = 0u; block < SCFDE_CCK_WORDS; block++)
    {
        float fmax = -1.0e30f, bmax = -1.0e30f;
        float bsecond = -1.0e30f;
        float best = -1.0e30f;
        uint16_t best_index = 0u;
        uint8_t use_backward = 1u;
        const float *fs = &forward[block * SCFDE_CCK_BOOK_SIZE];
        const float *bs = &backward[block * SCFDE_CCK_BOOK_SIZE];
        for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
        {
            if (fs[k] > fmax) { fmax = fs[k]; }
            if (bs[k] > bmax) { bsecond = bmax; bmax = bs[k]; }
            else if (bs[k] > bsecond) { bsecond = bs[k]; }
        }
        if ((bmax - bsecond) < 0.05f * (1.0f + fabsf(bmax)))
        {
            /* degenerate backward row (time-reversed model has no
               discrimination, e.g. short impulse): drop it so the fusion
               degrades to the forward pass. */
            use_backward = 0u;
        }
        for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
        {
            float bterm = use_backward ? (bs[k] - bmax) : 0.0f;
            float combined = (fs[k] - fmax) + bterm;
            if (combined > best) { best = combined; best_index = k; }
        }
        detected[block] = best_index;
    }
}

/* backward view: conj(fliplr(received)), conj(fliplr(book)), conj(fliplr(channel)). */
static void cck_receive_bidfe(uint16_t *detected)
{    static float f_scores[SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE];
    static float b_scores[SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE];
    static float flipped[SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE];
    uint16_t fwd[SCFDE_CCK_WORDS];
    uint16_t bwd[SCFDE_CCK_WORDS];
    uint16_t block, k, i;

    for (i = 0u; i < SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE; i++)
    {
        f_scores[i] = -1.0e30f;
        b_scores[i] = -1.0e30f;
    }
    cck_dfe_core(g_data, SCFDE_CCK_WORDS, 0u, 0.001f, fwd, f_scores);
    cck_dfe_core(g_data, SCFDE_CCK_WORDS, 1u, 0.001f, bwd, b_scores);
#ifdef SCFDE_CCK_DEBUG
    {
        uint16_t dbg;
        printf("fwd: "); for (dbg = 0; dbg < SCFDE_CCK_WORDS; dbg++) printf("%02x ", fwd[dbg]); printf("\n");
        printf("bwd: "); for (dbg = 0; dbg < SCFDE_CCK_WORDS; dbg++) printf("%02x ", bwd[dbg]); printf("\n");
    }
#endif
    for (block = 0u; block < SCFDE_CCK_WORDS; block++)
    {
        for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
        {
            flipped[block * SCFDE_CCK_BOOK_SIZE + k] =
                b_scores[(SCFDE_CCK_WORDS - 1u - block) * SCFDE_CCK_BOOK_SIZE + k];
        }
    }
    cck_fuse_scores(f_scores, flipped, detected);
}

/* BiDFE-2: fuse forward/backward candidate scores driven by the fused
   decisions as channel state (ch5_bidirectional_refine). */
static void cck_receive_bidfe2(uint16_t *detected)
{
    static float f_scores[SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE];
    static float b_scores[SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE];
    static float flipped[SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE];
    uint16_t bi1[SCFDE_CCK_WORDS];
    uint16_t block, c, k, i;

    cck_receive_bidfe(bi1);
    for (i = 0u; i < SCFDE_CCK_WORDS * SCFDE_CCK_BOOK_SIZE; i++)
    {
        f_scores[i] = -1.0e30f;
        b_scores[i] = -1.0e30f;
    }
    /* forward refinement: scores with bi1 decisions as state. */
    {
        scfde_complex_t state[SCFDE_CCK_TAPS - 1u];
        uint16_t active[128u];
        memset(state, 0, sizeof(state));
        for (block = 0u; block < SCFDE_CCK_WORDS; block++)
        {
            const scfde_complex_t *obs = &g_data[block * 8u];
            cck_candidate_list(obs, active);
            for (c = 0u; c < 128u; c++)
            {
                scfde_complex_t predicted[8u];
                float score = 0.0f;
                uint16_t chip;
                cck_expected_block(state, &g_book[active[c]][0], g_impulse, predicted);
                for (chip = 0u; chip < 8u; chip++)
                {
                    float dr = obs[chip].re - predicted[chip].re;
                    float di = obs[chip].im - predicted[chip].im;
                    score -= (dr * dr + di * di);
                }
                score /= 0.001f;
                f_scores[block * SCFDE_CCK_BOOK_SIZE + active[c]] = score;
            }
            cck_append_state(state, &g_book[bi1[block]][0]);
        }
    }
    /* backward refinement: reversed view with reversed bi1 decisions. */
    {
        scfde_complex_t state[SCFDE_CCK_TAPS - 1u];
        scfde_complex_t channel[SCFDE_CCK_TAPS];
        uint16_t active[128u];
        for (k = 0u; k < SCFDE_CCK_TAPS; k++)
        {
            channel[k] = cck_conj(g_impulse[SCFDE_CCK_TAPS - 1u - k]);
        }
        memset(state, 0, sizeof(state));
        for (block = 0u; block < SCFDE_CCK_WORDS; block++)
        {
            scfde_complex_t obs[8u];
            for (c = 0u; c < 8u; c++)
            {
                uint16_t src = (uint16_t)(SCFDE_CCK_CHIPS - 1u - (block * 8u + c));
                obs[c] = cck_conj(g_data[src]);
            }
            cck_candidate_list(obs, active);
            for (c = 0u; c < 128u; c++)
            {
                scfde_complex_t predicted[8u];
                scfde_complex_t word[8u];
                float score = 0.0f;
                uint16_t chip;
                for (chip = 0u; chip < 8u; chip++)
                {
                    word[chip] = cck_conj(g_book[active[c]][7u - chip]);
                }
                cck_expected_block(state, word, channel, predicted);
                for (chip = 0u; chip < 8u; chip++)
                {
                    float dr = obs[chip].re - predicted[chip].re;
                    float di = obs[chip].im - predicted[chip].im;
                    score -= (dr * dr + di * di);
                }
                score /= 0.001f;
                b_scores[block * SCFDE_CCK_BOOK_SIZE + active[c]] = score;
            }
            {
                scfde_complex_t word[8u];
                for (c = 0u; c < 8u; c++)
                {
                    word[c] = cck_conj(g_book[bi1[SCFDE_CCK_WORDS - 1u - block]][7u - c]);
                }
                cck_append_state(state, word);
            }
        }
    }
    for (block = 0u; block < SCFDE_CCK_WORDS; block++)
    {
        for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
        {
            flipped[block * SCFDE_CCK_BOOK_SIZE + k] =
                b_scores[(SCFDE_CCK_WORDS - 1u - block) * SCFDE_CCK_BOOK_SIZE + k];
        }
    }
    cck_fuse_scores(f_scores, flipped, detected);
}

static void cck_receive_tr_diversity(uint16_t *detected)
{
    scfde_complex_t *combined = &g_trd[0];
    scfde_complex_t *focused = &g_trd_focused[0];
    uint16_t n, m, branch;
    float branch_energy[2];
    uint16_t delay = SCFDE_CCK_TAPS - 1u;
    uint16_t channel_peak = 0u;
    const uint16_t frame_chips = SCFDE_CCK_FRAME_SYMBOLS;
    uint16_t usable;

    memset(combined, 0, SCFDE_CCK_FRAME_SYMBOLS * sizeof(scfde_complex_t));
    {
        float best_h = -1.0f;
        for (n = 0u; n < SCFDE_CCK_TAPS; n++)
        {
            float p = cck_power(g_impulse[n]);
            if (p > best_h) { best_h = p; channel_peak = n; }
        }
    }
    for (branch = 0u; branch < 2u; branch++)
    {
        scfde_complex_t channel[SCFDE_CCK_TAPS];
        branch_energy[branch] = 0.0f;
        for (n = 0u; n < SCFDE_CCK_TAPS; n++)
        {
            channel[n] = (branch == 0u) ? g_impulse[n] :
                          cck_conj(g_impulse[SCFDE_CCK_TAPS - 1u - n]);
            branch_energy[branch] += cck_power(channel[n]);
        }
        if (branch_energy[branch] < 1.0e-8f) { branch_energy[branch] = 1.0e-8f; }
        memset(focused, 0, (frame_chips + SCFDE_CCK_TAPS) * sizeof(scfde_complex_t));
        for (n = 0u; n < frame_chips + SCFDE_CCK_TAPS - 1u; n++)
        {
            for (m = 0u; m < SCFDE_CCK_TAPS; m++)
            {
                if ((m <= n) && ((n - m) < frame_chips))
                {
                    scfde_complex_t tr;
                    scfde_complex_t v;
                    tr.re = channel[SCFDE_CCK_TAPS - 1u - m].re;
                    tr.im = -channel[SCFDE_CCK_TAPS - 1u - m].im;
                    v = cck_mul(tr, g_frame[n - m]);
                    focused[n].re += v.re;
                    focused[n].im += v.im;
                }
            }
        }
        /* Align each branch to the channel main tap: the TR matched
           filter of h focuses at delay 27-channel_peak, the TR of the
           time-reversed channel focuses at delay channel_peak. */
        {
            uint16_t align = (branch == 0u) ?
                             (uint16_t)(delay - channel_peak) : channel_peak;
            for (n = 0u; n < frame_chips - align; n++)
            {
                combined[n].re += focused[n + align].re / branch_energy[branch];
                combined[n].im += focused[n + align].im / branch_energy[branch];
            }
        }
    }
    for (n = 0u; n < frame_chips - delay; n++)
    {
        combined[n].re *= 0.5f;
        combined[n].im *= 0.5f;
    }
    /* Data words begin at symbol 64 = block 8 of the full frame. */
    usable = ((frame_chips - delay) / 8u) * 8u;
    cck_nearest_book(&combined[8u * 8u], (usable - 8u * 8u) / 8u, detected);
}

/* FDE-IBDFE (5-80): 128-point FFT, 2 iterations, soft feedback. */
static void cck_receive_fde(uint16_t *detected, float noise_variance)
{
    scfde_complex_t *H = &g_work[0];
    scfde_complex_t *Y = &g_work[SCFDE_FFT_SIZE];
    scfde_complex_t soft[SCFDE_CCK_CHIPS];
    scfde_complex_t estimate[SCFDE_FFT_SIZE];
    float residual_energy[2];
    uint16_t iteration, n, block, k, chip;

    if (noise_variance < 1.0e-8f) { noise_variance = 1.0e-8f; }

    memset(H, 0, SCFDE_FFT_SIZE * sizeof(scfde_complex_t));
    for (n = 0u; n < SCFDE_CCK_TAPS; n++) { H[n] = g_impulse[n]; }
    scfde_fft(H, SCFDE_FFT_SIZE, 0u);
    for (n = 0u; n < SCFDE_FFT_SIZE; n++) { Y[n] = (n < SCFDE_CCK_CHIPS) ? g_data[n] : (scfde_complex_t){0.0f, 0.0f}; }
    scfde_fft(Y, SCFDE_FFT_SIZE, 0u);
    memset(soft, 0, sizeof(soft));

    for (iteration = 0u; iteration < 2u; iteration++)
    {
        scfde_complex_t C[SCFDE_FFT_SIZE];
        scfde_complex_t B[SCFDE_FFT_SIZE];
        scfde_complex_t fft_soft[SCFDE_FFT_SIZE];
        scfde_complex_t freq;
        float reliability = 0.0f, mean_ch = 0.0f;
        float mean_soft_power = 0.0f;

        for (n = 0u; n < SCFDE_CCK_CHIPS; n++)
        {
            mean_soft_power += cck_power(soft[n]);
        }
        mean_soft_power /= (float)SCFDE_CCK_CHIPS;
        reliability = 8.0f * mean_soft_power;
        if (reliability > 0.98f) { reliability = 0.98f; }

        for (n = 0u; n < SCFDE_FFT_SIZE; n++)
        {
            float den = noise_variance + (1.0f - reliability) * cck_power(H[n]);
            scfde_complex_t ch = H[n];
            C[n].re = ch.re / den;
            C[n].im = -ch.im / den;
            mean_ch += C[n].re * ch.re + C[n].im * ch.im;
        }
        mean_ch /= (float)SCFDE_FFT_SIZE;
        if (mean_ch < 1.0e-8f) { mean_ch = 1.0e-8f; }
        for (n = 0u; n < SCFDE_FFT_SIZE; n++)
        {
            C[n].re /= mean_ch;
            C[n].im /= mean_ch;
        }
        for (n = 0u; n < SCFDE_FFT_SIZE; n++)
        {
            B[n].re = C[n].re * H[n].re - C[n].im * H[n].im - 1.0f;
            B[n].im = C[n].re * H[n].im + C[n].im * H[n].re;
        }
        for (n = 0u; n < SCFDE_FFT_SIZE; n++) { fft_soft[n] = (n < SCFDE_CCK_CHIPS) ? soft[n] : (scfde_complex_t){0.0f, 0.0f}; }
        scfde_fft(fft_soft, SCFDE_FFT_SIZE, 0u);
        for (n = 0u; n < SCFDE_FFT_SIZE; n++)
        {
            scfde_complex_t cy = cck_mul(C[n], Y[n]);
            scfde_complex_t bs = cck_mul(B[n], fft_soft[n]);
            freq.re = cy.re - bs.re;
            freq.im = cy.im - bs.im;
            estimate[n] = freq;
        }
        scfde_fft(estimate, SCFDE_FFT_SIZE, 1u);

        /* soft book detect: nearest word plus exponential soft symbol. */
        {
            scfde_complex_t soft_word[SCFDE_CCK_CHIPS];
            uint16_t idx[SCFDE_CCK_WORDS];
            for (block = 0u; block < SCFDE_CCK_WORDS; block++)
            {
                float best_dist = 1.0e30f;
                float weight_sum = 0.0f;
                uint16_t best_index = 0u;
                float distances[SCFDE_CCK_BOOK_SIZE];
                for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
                {
                    float dist = 0.0f;
                    for (chip = 0u; chip < 8u; chip++)
                    {
                        float dr = estimate[block * 8u + chip].re - g_book[k][chip].re;
                        float di = estimate[block * 8u + chip].im - g_book[k][chip].im;
                        dist += dr * dr + di * di;
                    }
                    distances[k] = dist;
                    if (dist < best_dist) { best_dist = dist; best_index = k; }
                }
                idx[block] = best_index;
                for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
                {
                    distances[k] = expf(-(distances[k] - best_dist) / noise_variance);
                    weight_sum += distances[k];
                }
                for (chip = 0u; chip < 8u; chip++)
                {
                    soft_word[block * 8u + chip].re = 0.0f;
                    soft_word[block * 8u + chip].im = 0.0f;
                    for (k = 0u; k < SCFDE_CCK_BOOK_SIZE; k++)
                    {
                        float w = distances[k] / weight_sum;
                        soft_word[block * 8u + chip].re += w * g_book[k][chip].re;
                        soft_word[block * 8u + chip].im += w * g_book[k][chip].im;
                    }
                }
            }
            {
                float residual = 0.0f;
                scfde_complex_t reconstructed[SCFDE_CCK_CHIPS + SCFDE_CCK_TAPS - 1u];
                memset(reconstructed, 0, sizeof(reconstructed));
                for (n = 0u; n < SCFDE_CCK_CHIPS; n++)
                {
                    for (k = 0u; k < SCFDE_CCK_TAPS; k++)
                    {
                        reconstructed[n + k].re += g_impulse[k].re * soft_word[n].re -
                                                  g_impulse[k].im * soft_word[n].im;
                        reconstructed[n + k].im += g_impulse[k].re * soft_word[n].im +
                                                  g_impulse[k].im * soft_word[n].re;
                    }
                }
                for (n = 0u; n < SCFDE_CCK_CHIPS; n++)
                {
                    float dr = g_data[n].re - reconstructed[n].re;
                    float di = g_data[n].im - reconstructed[n].im;
                    residual += dr * dr + di * di;
                }
                residual /= (float)SCFDE_CCK_CHIPS;
                residual_energy[iteration] = residual;
                if ((iteration > 0u) &&
                    (residual_energy[iteration] > residual_energy[iteration - 1u]))
                {
                    /* keep previous detection: detected already holds the
                       previous iteration's indices; stop updating. */
                    for (block = 0u; block < SCFDE_CCK_WORDS; block++)
                    {
                        detected[block] = idx[block];
                    }
                    return;
                }
                for (block = 0u; block < SCFDE_CCK_WORDS; block++)
                {
                    detected[block] = idx[block];
                }
                for (n = 0u; n < SCFDE_CCK_CHIPS; n++)
                {
                    soft[n].re = 0.65f * soft[n].re + 0.35f * soft_word[n].re;
                    soft[n].im = 0.65f * soft[n].im + 0.35f * soft_word[n].im;
                }
            }
        }
    }
}

static void cck_packet_from_indices(const uint16_t *detected, uint16_t block_count)
{
    uint16_t bit, block;
    memset(g_packet, 0, sizeof(g_packet));
    for (block = 0u; block < block_count; block++)
    {
        for (bit = 0u; bit < 8u; bit++)
        {
            uint16_t packet_bit = block * 8u + bit;
            uint8_t value = (uint8_t)((detected[block] >> bit) & 1u);
            if (value != 0u)
            {
                g_packet[packet_bit >> 3u] |= (uint8_t)(1u << (packet_bit & 7u));
            }
        }
    }
}

static uint8_t cck_packet_is_valid(uint8_t *length_out)
{
    uint16_t received_crc;
    if ((g_packet[0] != 0xA5u) || (g_packet[1] != 0x5Au) ||
        (g_packet[2] > SCFDE_CCK_MAX_PAYLOAD))
    {
        return 0u;
    }
    received_crc = (uint16_t)(((uint16_t)g_packet[SCFDE_CCK_PACKET_CRC_INDEX] << 8u) |
                              g_packet[SCFDE_CCK_PACKET_CRC_INDEX + 1u]);
    if (cck_crc16(g_packet, SCFDE_CCK_PACKET_CRC_INDEX) != received_crc)
    {
        return 0u;
    }
    *length_out = g_packet[2];
    return 1u;
}

scfde_rx_result_t scfde_cck_decode(const uint16_t *samples, uint32_t sample_count,
                                   scfde_cck_receiver_t receiver)
{
    scfde_rx_result_t result;
    uint16_t detected[SCFDE_CCK_WORDS];
    float midpoint = 0.0f;
    float best_metric = 0.0f;
    uint32_t best_sample = 0u;
    float start_rate, end_rate, noise;
    uint8_t phase;
    uint32_t i;
    uint16_t n;
    uint8_t length_out = 0u;

    memset(&result, 0, sizeof(result));
    if ((samples == 0) ||
        (sample_count < (SCFDE_CCK_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)))
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
        if (symbol_count > SCFDE_CCK_RX_MAX_SYMBOLS) { symbol_count = SCFDE_CCK_RX_MAX_SYMBOLS; }
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
        if (symbol_count >= SCFDE_CCK_FRAME_SYMBOLS)
        {
            uint32_t offset;
            for (offset = 0u; offset <= (symbol_count - SCFDE_CCK_FRAME_SYMBOLS); offset++)
            {
                float metric = cck_sync_metric(&g_phase_symbols[offset]);
                if (metric > best_metric)
                {
                    best_metric = metric;
                    best_sample = phase + offset * SCFDE_RX_SAMPLES_PER_SYMBOL;
                    memcpy(g_frame, &g_phase_symbols[offset],
                           SCFDE_CCK_FRAME_SYMBOLS * sizeof(scfde_complex_t));
                }
            }
        }
    }
    result.sync_metric = best_metric;
    result.frame_start_sample = best_sample;
    if (best_metric < 0.18f) { return result; }

    /* CFO from UW1/UW2 and UW2/UW3, linear-quadratic correction. */
    {
        scfde_complex_t first = cck_correlate_uw(g_frame);
        scfde_complex_t second = cck_correlate_uw(g_frame + SCFDE_UW_LENGTH);
        scfde_complex_t third = cck_correlate_uw(
            g_frame + 2u * SCFDE_UW_LENGTH + SCFDE_CCK_CHIPS);
        start_rate = cck_phase_diff(second, first, SCFDE_UW_LENGTH);
        end_rate = cck_phase_diff(third, second,
                                  SCFDE_UW_LENGTH + SCFDE_CCK_CHIPS);
    }
    result.frequency_offset_hz = 0.5f * (start_rate + end_rate) *
                                 (float)SCFDE_SYMBOL_RATE_HZ / (2.0f * SCFDE_CCK_PI);
    {
        float slope = (end_rate - start_rate) / (float)(SCFDE_CCK_FRAME_SYMBOLS - 1u);
        for (n = 0u; n < SCFDE_CCK_FRAME_SYMBOLS; n++)
        {
            float symbol = (float)n;
            float angle = -(start_rate * symbol + 0.5f * slope * symbol * symbol);
            scfde_complex_t rotation;
            rotation.re = cosf(angle);
            rotation.im = sinf(angle);
            g_frame[n] = cck_mul(g_frame[n], rotation);
        }
    }

    cck_build_channel(&noise);
    /* Normalize the channel impulse and the data chips to the unit-energy
       symbol domain used by the codebook and the MATLAB receivers. */
    {
        float h_energy = 0.0f;
        float h_scale;
        for (n = 0u; n < SCFDE_CCK_TAPS; n++)
        {
            h_energy += cck_power(g_impulse[n]);
        }
        h_scale = sqrtf(h_energy);
        if (h_scale < 1.0e-9f) { h_scale = 1.0f; }
        for (n = 0u; n < SCFDE_CCK_TAPS; n++)
        {
            g_impulse[n].re /= h_scale;
            g_impulse[n].im /= h_scale;
        }
        for (n = 0u; n < SCFDE_CCK_FRAME_SYMBOLS; n++)
        {
            g_frame[n].re /= h_scale;
            g_frame[n].im /= h_scale;
        }
        for (n = 0u; n < SCFDE_CCK_CHIPS; n++)
        {
            g_data[n] = g_frame[2u * SCFDE_UW_LENGTH + n];
        }
    }

    switch (receiver)
    {
    case SCFDE_CCK_RX_MFB:
        cck_receive_mfb(detected);
        break;
    case SCFDE_CCK_RX_RAKE:
        cck_receive_rake(detected);
        break;
    case SCFDE_CCK_RX_DFE:
        cck_receive_dfe(detected);
        break;
    case SCFDE_CCK_RX_BIDFE:
        cck_receive_bidfe(detected);
        break;
    case SCFDE_CCK_RX_BIDFE2:
        cck_receive_bidfe2(detected);
        break;
    case SCFDE_CCK_RX_TR_DIVERSITY:
        cck_receive_tr_diversity(detected);
        break;
    case SCFDE_CCK_RX_FDE:
    default:
        cck_receive_fde(detected, noise);
        break;
    }

    cck_packet_from_indices(detected, SCFDE_CCK_WORDS);
    if (cck_packet_is_valid(&length_out) != 0u)
    {
        result.payload_length = length_out;
        result.sequence = g_packet[3];
        memcpy(result.payload, &g_packet[4], length_out);
        result.crc_ok = 1u;
        result.valid = 1u;
    }
    result.equalizer_used = (scfde_equalizer_mode_t)(
        (uint8_t)SCFDE_EQUALIZER_CCK_MFB + (uint8_t)receiver);
    return result;
}

const char *scfde_cck_receiver_name(scfde_cck_receiver_t receiver)
{
    static const char *const names[7] = {
        "CCK-MFB", "CCK-RAKE", "CCK-DFE", "CCK-BIDFE",
        "CCK-BIDFE2", "CCK-TR-DIV", "CCK-FDE"
    };
    if ((uint8_t)receiver > 6u) { return "UNKNOWN"; }
    return names[(uint8_t)receiver];
}
