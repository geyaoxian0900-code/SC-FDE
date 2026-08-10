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

/* Trellis for (7,5)_8, state number = s1*2+s2 with s1 = most recent input:
 *   state 0 (00): next = {0,2}, out = {(0,0),(1,1)}
 *   state 1 (01): next = {0,2}, out = {(1,1),(0,0)}
 *   state 2 (10): next = {1,3}, out = {(1,0),(0,1)}
 *   state 3 (11): next = {1,3}, out = {(0,1),(1,0)} */
static const uint8_t turbo_next[SCFDE_TURBO_STATES][2] = {
    {0u, 2u}, {0u, 2u}, {1u, 3u}, {1u, 3u}
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

/* Hull-Dobell compliant LCG for full period 192: A=1 mod 12 (37),
   C coprime to 192 (17). */
#define TURBO_PERM_A 37u
#define TURBO_PERM_C 17u
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
    static uint8_t temp[SCFDE_TURBO_CODE_BITS];
    uint16_t i;
    if (!turbo_perm_ready) { turbo_build_perm(); }
    /* support in-place operation */
    if (in == out)
    {
        memcpy(temp, in, sizeof(temp));
        in = temp;
    }
    for (i = 0u; i < SCFDE_TURBO_CODE_BITS; i++)
    {
        out[i] = in[turbo_perm[i]];
    }
}

void scfde_turbo_deinterleave(const float *in, float *out)
{
    static float temp[SCFDE_TURBO_CODE_BITS];
    uint16_t i;
    if (!turbo_perm_ready) { turbo_build_perm(); }
    if (in == out)
    {
        memcpy(temp, in, sizeof(temp));
        in = temp;
    }
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
    if (maximum <= -1.0e29f)
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
    if (maximum > -1.0e29f)
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

    /* branch metrics: gamma = 0.5 * sum(out * llr) with the LLR convention
       positive = bit 1 (P(b=1)/P(b=0)) */
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        float l0 = coded_llr[2u * t];
        float l1 = coded_llr[2u * t + 1u];
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                float b0 = (float)turbo_out[s][u][0] * l0;
                float b1 = (float)turbo_out[s][u][1] * l1;
                gamma_metric[t][s][u] = 0.5f * (b0 + b1);
            }
        }
    }

    /* forward recursion */
    for (s = 0u; s < SCFDE_TURBO_STATES; s++)
    {
        alpha[0][s] = (s == 0u) ? 0.0f : -1.0e30f;
    }
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            alpha[t + 1u][s] = -1.0e30f;
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
            beta[tprev][s] = -1.0e30f;
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
        float input_value[2] = {-1.0e30f, -1.0e30f};
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                uint8_t ns = turbo_next[s][u];
                float path = alpha[t][s] + gamma_metric[t][s][u] + beta[t + 1u][ns];
                input_value[u] = turbo_log_combine(input_value[u], path, max_log);
            }
        }
        info_llr[t] = input_value[1] - input_value[0];
    }
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        info_bits[t] = (info_llr[t] >= 0.0f) ? 1u : 0u;
    }
}

/* ------------------------------------------------------------------ */
/* Extended BCJR: also output the coded-bit posterior LLRs             */
/* ------------------------------------------------------------------ */

void scfde_turbo_bcjr_ext(const float *coded_llr, float *info_llr,
                          float *coded_out, uint8_t *info_bits,
                          uint8_t max_log)
{
    static float alpha[SCFDE_TURBO_TIME + 1u][SCFDE_TURBO_STATES];
    static float beta[SCFDE_TURBO_TIME + 1u][SCFDE_TURBO_STATES];
    static float gamma_metric[SCFDE_TURBO_TIME][SCFDE_TURBO_STATES][2];
    uint16_t t;
    uint8_t s, u, c;

    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        float l0 = coded_llr[2u * t];
        float l1 = coded_llr[2u * t + 1u];
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                gamma_metric[t][s][u] = 0.5f * ((float)turbo_out[s][u][0] * l0 +
                                                (float)turbo_out[s][u][1] * l1);
            }
        }
    }
    for (s = 0u; s < SCFDE_TURBO_STATES; s++)
    {
        alpha[0][s] = (s == 0u) ? 0.0f : -1.0e30f;
    }
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            alpha[t + 1u][s] = -1.0e30f;
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
    for (s = 0u; s < SCFDE_TURBO_STATES; s++)
    {
        beta[SCFDE_TURBO_TIME][s] = 0.0f;
    }
    for (t = SCFDE_TURBO_TIME; t > 0u; t--)
    {
        uint16_t tprev = t - 1u;
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            beta[tprev][s] = -1.0e30f;
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
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        float input_value[2] = {-1.0e30f, -1.0e30f};
        float code_value[2][2] = {{-1.0e30f, -1.0e30f},
                                  {-1.0e30f, -1.0e30f}};
        for (s = 0u; s < SCFDE_TURBO_STATES; s++)
        {
            for (u = 0u; u < 2u; u++)
            {
                uint8_t ns = turbo_next[s][u];
                float path = alpha[t][s] + gamma_metric[t][s][u] + beta[t + 1u][ns];
                input_value[u] = turbo_log_combine(input_value[u], path, max_log);
                for (c = 0u; c < 2u; c++)
                {
                    code_value[turbo_out[s][u][c]][c] =
                        turbo_log_combine(code_value[turbo_out[s][u][c]][c], path, max_log);
                }
            }
        }
        info_llr[t] = input_value[1] - input_value[0];
        coded_out[2u * t] = code_value[1][0] - code_value[0][0];
        coded_out[2u * t + 1u] = code_value[1][1] - code_value[0][1];
    }
    for (t = 0u; t < SCFDE_TURBO_TIME; t++)
    {
        info_bits[t] = (info_llr[t] >= 0.0f) ? 1u : 0u;
    }
}

/* ------------------------------------------------------------------ */
/* QPSK soft symbols from coded LLRs: E[s] = (tanh(l0/2)+j*tanh(l1/2))/sqrt(2) */
/* ------------------------------------------------------------------ */

void scfde_turbo_soft_symbols(const float *coded_llr, scfde_complex_t *symbols)
{
    uint16_t i;
    for (i = 0u; i < SCFDE_TURBO_TIME; i++)
    {
        symbols[i].re = tanhf(coded_llr[2u * i] * 0.5f) * 0.7071067811865476f;
        symbols[i].im = tanhf(coded_llr[2u * i + 1u] * 0.5f) * 0.7071067811865476f;
    }
}

/* float in-place interleaver for coded LLR feedback */
void scfde_turbo_interleave_f(const float *in, float *out)
{
    static float temp[SCFDE_TURBO_CODE_BITS];
    uint16_t i;
    if (!turbo_perm_ready) { turbo_build_perm(); }
    if (in == out)
    {
        memcpy(temp, in, sizeof(temp));
        in = temp;
    }
    for (i = 0u; i < SCFDE_TURBO_CODE_BITS; i++)
    {
        out[i] = in[turbo_perm[i]];
    }
}
