/* test_fblms.c - independent numeric regression for the frequency-domain
 * block LMS equalizer (overlap-save, constrained weights).
 *
 * The regression guards the constrained-weight rewrite: after the
 * frequency-domain weight update the code must IFFT, keep the first
 * SCFDE_FBLMS_FILTER taps, zero the rejected region, and transform the
 * constrained impulse back.  A previous bug cleared the whole weights
 * array and never copied the retained taps back, so every block
 * restarted with zero weights and the loopback failed deterministically.
 *
 * The test drives the REAL dispatch entry (scfde_equalizer_dfe with
 * SCFDE_EQUALIZER_FBLMS) - scfde_equalizer_apply coerces unknown modes
 * to MMSE and would silently bypass fblms_equalize().
 *
 * Red/green contract:
 *   - reverting the writeback (zeroing weights after the IFFT) makes the
 *     output identically zero and this test fail deterministically;
 *   - the fixed code retains the constrained weights across blocks, so
 *     the output is non-zero, finite and correlates with the
 *     transmitted data (fixed correlation threshold).
 * Full BER convergence depends on the firmware step-size normalization
 * and the modem-chain signal levels, and is covered end-to-end by
 * test_end_to_end.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "scfde_equalizer.h"
#include "scfde_fft.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

#define TRAIN_LEN 64u
#define DATA_LEN  96u
#define UW_LEN    32u
#define N         (TRAIN_LEN + DATA_LEN + UW_LEN)

static scfde_complex_t qpsk_map(uint16_t bits)
{
    /* Unit-energy QPSK (Es = 1): +/-1/sqrt(2) per component, matching
     * the firmware mapper (scfde_modem.c) and the equalizer helpers. */
    const float inv_sqrt2 = 0.7071067811865476f;
    scfde_complex_t s;
    s.re = (bits & 1u) ? inv_sqrt2 : -inv_sqrt2;
    s.im = (bits & 2u) ? inv_sqrt2 : -inv_sqrt2;
    return s;
}

int main(void)
{
    scfde_complex_t tx[N], channel[N], frame[N];
    scfde_complex_t output[DATA_LEN];
    uint16_t k;
    uint32_t nonzero = 0u;

    /* Deterministic training/data symbols (Es = 1). */
    for (k = 0u; k < TRAIN_LEN; k++)
    {
        tx[k] = qpsk_map((uint16_t)(k * 7u + k / 3u));
    }
    for (k = 0u; k < DATA_LEN; k++)
    {
        tx[TRAIN_LEN + k] = qpsk_map((uint16_t)(k * 13u + k / 5u + 11u));
    }
    for (k = 0u; k < UW_LEN; k++)
    {
        float p = (float)M_PI * k * k / 32.0f;
        tx[TRAIN_LEN + DATA_LEN + k].re = cosf(p);
        tx[TRAIN_LEN + DATA_LEN + k].im = -sinf(p);
    }

    /* Identity channel (h = [1]): removes frequency-selective dynamics;
     * the regression target is the constrained-weight retention, not the
     * step-size tuning. */
    for (k = 0u; k < N; k++)
    {
        channel[k].re = (k == 0u) ? 1.0f : 0.0f;
        channel[k].im = 0.0f;
    }
    memcpy(frame, tx, sizeof(frame));

    memset(output, 0, sizeof(output));

    /* Real FBLMS dispatch: scfde_equalizer_dfe with the FBLMS mode. */
    scfde_equalizer_dfe(SCFDE_EQUALIZER_FBLMS, frame, N, tx, channel, 1u,
                        0.0f, DATA_LEN, output);

    for (k = 0u; k < DATA_LEN; k++)
    {
        if (!isfinite(output[k].re) || !isfinite(output[k].im))
        {
            CHECK(0, "FBLMS output must be finite");
        }
        if (output[k].re != 0.0f || output[k].im != 0.0f)
        {
            nonzero++;
        }
    }
    CHECK(nonzero > 0u,
          "FBLMS constrained weights must be retained across blocks");

    /* Signal-present correlation: the equalized output must carry the
     * transmitted data (pre-fix output was identically zero, so the
     * correlation was exactly 0). */
    {
        float corr = 0.0f;
        float nout = 0.0f;
        float nref = 0.0f;
        for (k = 0u; k < DATA_LEN; k++)
        {
            scfde_complex_t e = tx[TRAIN_LEN + k];
            corr += output[k].re * e.re + output[k].im * e.im;
            nout += output[k].re * output[k].re + output[k].im * output[k].im;
            nref += e.re * e.re + e.im * e.im;
        }
        corr = fabsf(corr) / (sqrtf(nout) * sqrtf(nref) + 1e-12f);
        CHECK(corr > 0.1f,
              "FBLMS output must correlate with the transmitted data");
    }

    printf("FBLMS constrained-weight retention (nonzero, correlated): PASS\n");
    printf("PASS\n");
    return 0;
}
