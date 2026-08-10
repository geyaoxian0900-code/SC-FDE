#include "scfde_turbo.h"
#include <math.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Rate-1/2 convolutional code (7,5)_8                                 */
/*   c1 = u ^ s1 ^ s2   (G1 = 111b)                                   */
/*   c2 = u ^ s2        (G2 = 101b)                                   */
/* state = [s1 s2], s1 = most recent input                             */
/* ------------------------------------------------------------------ */

void scfde_turbo_conv_encode(const uint8_t *info_bits, uint8_t *coded_bits)
{
    uint8_t s1 = 0u, s2 = 0u;
    uint16_t i;
    for (i = 0u; i < SCFDE_TURBO_INFO_BITS; i++)
    {
        uint8_t u = info_bits[i] & 1u;
        coded_bits[2u * i]     = (u ^ s1 ^ s2) & 1u;
        coded_bits[2u * i + 1u] = (u ^ s2) & 1u;
        s2 = s1;
        s1 = u;
    }
}

/* Trellis: nextState[state][input], outputBits[state][input][2] */
static const uint8_t turbo_next[SCFDE_TURBO_STATES][2] = {
    {0u, 2u}, {1u, 3u}, {0u, 2u}, {1u, 3u}
};
static const uint8_t turbo_out[SCFDE_TURBO_STATES][2][2] = {
    {{0u, 0u}, {1u, 1u}},
    {{1u, 1u}, {0u, 0u}},
    {{1u, 0u}, {0u, 1u}},
    {{0u, 1u}, {1u, 0u}}
};

/* ------------------------------------------------------------------ */
/* Fixed 192-bit interleaver (deterministic LCG-based permutation)     */
/* ------------------------------------------------------------------ */

#define TURBO_PERM_A 137u
#define TURBO_PERM_C 187u
#define TURBO_PERM_M 192u

static uint16_t turbo_perm[SCFDE_TURBO_CODE_BITS];
static uint8_t turbo_perm_ready;

static void turbo_build_perm(void)
{
    uint16_t i;
    uint16_t value = 7u;
    uint16_t filled = 0u;
    for (i = 0u; i < SCFDE_TURBO_CODE_BITS; i++)
    {
        turbo_perm[i] = 0xFFFFu;
    }
    /* LCG modulo 192 generates values in [0,192); keep distinct values. */
    while (filled < SCFDE_TURBO_CODE_BITS)
    {
        value = (uint16_t)((TURBO_PERM_A * value + TURBO_PERM_C) % TURBO_PERM_M);
        {
            uint16_t j;
            uint8_t duplicate = 0u;
            for (j = 0u; j < filled; j++)
            {
                if (turbo_perm[j] == value) { duplicate = 1u; break; }
            }
            if (!duplicate)
            {
                turbo_perm[filled++] = value;
            }
        }
    }
    turbo_perm_ready = 1u;
}

void scfde_turbo_interleave(const uint8_t *in, uint8_t *out)
{
    uint16_t i;
    if (!turbo_perm_ready) { turbo_build_perm(); }
    for (i = 0u; i < SCFDE_TURBO_CODE_BITS; i++)
    {
        out[i] = in[turbo_perm[i]];
    }
}

void scfde_turbo_deinterleave(const float *in, float *out)
{
    uint16_t i;
    if (!turbo_perm_ready) { turbo_build_perm(); }
    for (i = 0u; i < SCFDE_TURBO_CODE_BITS; i++)
    {
        out[turbo_perm[i]] = in[i];
    }
}

/* ------------------------------------------------------------------ */
/* Log-MAP BCJR                                                       */
/* ------------------------------------------------------------------ */

static float turbo_log_combine(float left, float right, uint8_t max_log)
{
    float maximum;
    if (max_log)
    {
        return left > right ? left : right;
    }
    maximum = left > right ? left : right;
    if (isinf(maximum))
    {
        return maximum;
    }
    return maximum + logf(expf(left - maximum) + expf(right - maximum));
}

static void turbo_normalize(float *row, uint8_t count)
{
    float maximum = row[0];
    uint8_t i;
    for (i = 1u; i < count; i++)
    {
        if (row[i] > maximum) { maximum = row[i]; }
    }
    if (isfinite(maximum))
    {
        for (i = 0u; i < count; i++)
        {
            row[i] -= maximum;
        }
    }
}

void scfde_turbo_bcjr(const float *coded_llr, float *info_llr,
                      uint8_t *info_bits, uint8_t max_log)
{
    static float alpha[SCFDE_TURBO_TIME + 1u][SCFDE_TURBO_STATES];
    static float beta[SCFDE_TURBO_TIME + 1u][SCFDE_TURBO_STATES];
    static float gamma_metric[SCFDE_TURBO_TIME][SCFDE_TURBO_STATES][2];
    uint16_t t;
    uint8_t s, u, c;

    /* branch metrics: gamma = 0.5 * sum((1-2*out)*llr) */
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        float l0 = coded_llr[2u * t];
        float l1 = coded_llr[2u * t + 1u];
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                float b0 = (1.0f - 2.0f * (float)turbo_out[s][u][0]) * l0;
                float b1 = (1.0f - 2.0f * (float)turbo_out[s][u][1]) * l1;
                gamma_metric[t][s][u] = 0.5f * (b0 + b1);
            }
        }
    }

    /* forward recursion */
    for (s = 0u; s < SCFDE_TURBO_STATES; s++)
    {
        alpha[0][s] = (s == 0u) ? 0.0f : -INFINITY;
    }
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            alpha[t + 1u][s] = -INFINITY;
        }
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                uint8_t ns = turbo_next[s][u];
                float value = alpha[t][s] + gamma_metric[t][s][u];
                alpha[t + 1u][ns] = turbo_log_combine(alpha[t + 1u][ns], value, max_log);
            }
        }
        turbo_normalize(alpha[t + 1u], SCFDE_TURBO_STATES);
    }

    /* backward recursion (beta(T+1) = 0 for all states) */
    for (s = 0u; s < SCFDE_TURBO_STATES; s++)
    {
        beta[SCFDE_TURBO_TIME][s] = 0.0f;
    }
    for (t = SCFDE_TURBO_TIME; t > 0u; t--)
    {
        uint16_t tprev = t - 1u;
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            beta[tprev][s] = -INFINITY;
        }
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                uint8_t ns = turbo_next[s][u];
                float value = gamma_metric[tprev][s][u] + beta[t][ns];
                beta[tprev][s] = turbo_log_combine(beta[tprev][s], value, max_log);
            }
        }
        turbo_normalize(beta[tprev], SCFDE_TURBO_STATES);
    }

    /* soft output */
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        float input_value[2] = {-INFINITY, -INFINITY};
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                uint8_t ns = turbo_next[s][u];
                float path = alpha[t][s] + gamma_metric[t][s][u] + beta[t + 1u][ns];
                input_value[u] = turbo_log_combine(input_value[u], path, max_log);
            }
        }
        info_llr[t] = input_value[0] - input_value[1];
    }
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        info_bits[t] = (info_llr[t] >= 0.0f) ? 1u : 0u;
    }
}
