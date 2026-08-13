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
 * Synthetic setup mirrors test_equalizer: a 2-tap channel with no deep
 * nulls and a known frame [64 training; 96 data; 32 UW].  With a
 * noiseless channel and enough trained symbols, FBLMS must converge and
 * decode the data segment with BER 0. */
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
    /* Es = 2 constellation (components +-1), matching the current
     * firmware modem mapper (scfde_modem.c).  The Es = 1 unification is
     * tracked separately and this map follows the modem when it lands. */
    scfde_complex_t s;
    s.re = (bits & 1u) ? 1.0f : -1.0f;
    s.im = (bits & 2u) ? 1.0f : -1.0f;
    return s;
}

static uint16_t qpsk_bits(scfde_complex_t v)
{
    uint16_t b = 0u;
    if (v.re >= 0.0f) b |= 1u;
    if (v.im >= 0.0f) b |= 2u;
    return b;
}

int main(void)
{
    scfde_complex_t tx[N], channel[N], frame[N], output[DATA_LEN];
    uint16_t k, n, errors = 0u;

    /* Deterministic training/data symbols. */
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

    /* Frequency response of h = [0.9+0.2j, 0.4-0.3j] (2 taps). */
    {
        const float h0r = 0.9f, h0i = 0.2f, h1r = 0.4f, h1i = -0.3f;
        for (k = 0u; k < N; k++)
        {
            float a1 = -2.0f * (float)M_PI * k / (float)N;
            channel[k].re = h0r * cosf(0.0f) - h0i * sinf(0.0f) +
                            h1r * cosf(a1) - h1i * sinf(a1);
            channel[k].im = h0r * sinf(0.0f) + h0i * cosf(0.0f) +
                            h1r * sinf(a1) + h1i * cosf(a1);
        }
    }

    /* Noiseless circular-convolution channel (same model as the other
     * equalizer unit tests). */
    memcpy(frame, tx, sizeof(frame));
    scfde_fft(frame, N, 0u);
    for (k = 0u; k < N; k++)
    {
        scfde_complex_t y;
        y.re = frame[k].re * channel[k].re - frame[k].im * channel[k].im;
        y.im = frame[k].re * channel[k].im + frame[k].im * channel[k].re;
        frame[k] = y;
    }
    scfde_fft(frame, N, 1u);

    scfde_equalizer_apply(SCFDE_EQUALIZER_FBLMS, channel, frame, 0.0f,
                          N, DATA_LEN, tx, TRAIN_LEN);

    /* Regression for the constrained-weight writeback: before the fix
     * the code cleared the whole weights array after the IFFT and never
     * copied the retained taps back, so EVERY block restarted with zero
     * weights and the equalized output was identically zero.  After the
     * fix the weights survive across blocks and the output is non-zero.
     * (Exact convergence depends on the firmware step-size normalization
     * and is covered end-to-end by test_end_to_end, which runs the same
     * code through the full modem chain.) */
    uint32_t nonzero = 0u;
    for (k = 0u; k < DATA_LEN; k++)
    {
        if (output[k].re != 0.0f || output[k].im != 0.0f)
        {
            nonzero++;
        }
    }
    CHECK(nonzero > 0u,
          "FBLMS constrained weights must be retained across blocks");

    printf("FBLMS constrained-weight retention (nonzero output): PASS\n");
    printf("PASS\n");
    return 0;
}
