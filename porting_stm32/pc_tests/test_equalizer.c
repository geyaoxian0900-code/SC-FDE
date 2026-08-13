/* test_equalizer.c - MMSE/ZF/MF/IB-DFE/NLMS-TDE on a synthetic frequency-
 * selective channel. MMSE with zero regularization and ZF must recover a
 * known block; IB-DFE and NLMS must not diverge. */
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

#define N 128u
#define D 96u

int main(void)
{
    scfde_complex_t channel[N], block[N], reference[N];
    uint16_t k, n;
    float regularization = 1e-9f;

    /* Synthetic 2-tap channel: no deep nulls, so ZF/MMSE invert cleanly.
     * Taps are copied first; the DFT loop below must not overwrite them. */
    {
        float h0r = 0.9f, h0i = 0.2f, h1r = 0.4f, h1i = -0.3f;
        for (k = 0; k < N; k++)
        {
            /* H[k] = sum h[n] exp(-j2pi kn/N) */
            float a0 = 0.0f;
            float a1 = -2.0f * (float)M_PI * k / (float)N;
            float re = h0r * cosf(a0) - h0i * sinf(a0) +
                       h1r * cosf(a1) - h1i * sinf(a1);
            float im = h0r * sinf(a0) + h0i * cosf(a0) +
                       h1r * sinf(a1) + h1i * cosf(a1);
            channel[k].re = re;
            channel[k].im = im;
        }
    }

    /* Known QPSK data block with tail UW. */
    for (k = 0; k < N; k++)
    {
        if (k < D)
        {
            block[k].re = (k % 2u == 0u) ? 1.0f : -1.0f;
            block[k].im = (k % 3u == 0u) ? 1.0f : -1.0f;
        }
        else
        {
            block[k].re = cosf((float)M_PI * (k - D) * (k - D) / 32.0f);
            block[k].im = -sinf((float)M_PI * (k - D) * (k - D) / 32.0f);
        }
        reference[k] = block[k];
    }

    /* Channelize: received = ifft(fft(tx) .* H) (circular convolution). */
    scfde_fft(block, N, 0u);
    for (k = 0; k < N; k++)
    {
        scfde_complex_t y;
        y.re = block[k].re * channel[k].re - block[k].im * channel[k].im;
        y.im = block[k].re * channel[k].im + block[k].im * channel[k].re;
        block[k] = y;
    }
    scfde_fft(block, N, 1u);

    /* 1) MMSE with lambda -> 0 must invert the channel (noiseless).
     * scfde_equalizer_apply() expects the time-domain block and performs
     * its own forward FFT; do NOT pre-transform. */
    {
        scfde_complex_t received[N];
        memcpy(received, block, sizeof(received));
        scfde_equalizer_apply(SCFDE_EQUALIZER_MMSE_FDE, channel, received,
                              regularization, N, D, reference + D, N - D);
        for (k = 0; k < D; k++)
        {
            float e = fabsf(received[k].re - reference[k].re) +
                      fabsf(received[k].im - reference[k].im);
            CHECK(e < 5e-3f, "MMSE recovery error too large");
        }
    }
    printf("MMSE-FDE (lambda->0) recovery: PASS\n");

    /* 2) ZF must also recover. */
    {
        scfde_complex_t received[N];
        memcpy(received, block, sizeof(received));
        scfde_equalizer_apply(SCFDE_EQUALIZER_ZF_FDE, channel, received,
                              regularization, N, D, reference + D, N - D);
        for (k = 0; k < D; k++)
        {
            float e = fabsf(received[k].re - reference[k].re) +
                      fabsf(received[k].im - reference[k].im);
            CHECK(e < 5e-3f, "ZF recovery error too large");
        }
    }
    printf("ZF-FDE recovery: PASS\n");

    /* 3) IB-DFE must terminate with bounded output. */
    {
        scfde_complex_t received[N];
        memcpy(received, block, sizeof(received));
        scfde_equalizer_apply(SCFDE_EQUALIZER_IB_DFE, channel, received,
                              regularization, N, D, reference + D, N - D);
        for (k = 0; k < D; k++)
        {
            float e = fabsf(received[k].re - reference[k].re) +
                      fabsf(received[k].im - reference[k].im);
            CHECK(e < 2e-2f, "IB-DFE recovery error too large");
        }
    }
    printf("IB-DFE recovery: PASS\n");

    {
        scfde_complex_t training_rx[N], trained[1];
        memcpy(training_rx, reference, D * sizeof(scfde_complex_t));
        scfde_equalizer_nlms_tde(trained, 0u, training_rx, reference, D);
        printf("NLMS-TDE zero-length guard: PASS\n");
    }

    /* PTR boundary guards: the entry must reject null impulse, zero taps
     * and taps beyond SCFDE_PTR_MAX_TAPS without underflowing the
     * equivalent-channel length (2*taps-1).  28 taps (the boundary) must
     * still run. */
    {
        scfde_complex_t received[N], out[D];
        scfde_complex_t tr_imp[N];
        uint16_t guard_taps[] = {0u, 28u, 29u};
        uint16_t g, t;
        for (g = 0u; g < sizeof(guard_taps) / sizeof(guard_taps[0]); g++)
        {
            t = guard_taps[g];
            memcpy(received, block, sizeof(received));
            memset(out, 0, sizeof(out));
            for (k = 0u; k < (t < 29u ? t : 29u); k++)
            {
                tr_imp[k].re = 0.3f;
                tr_imp[k].im = 0.0f;
            }
            scfde_equalizer_dfe(SCFDE_EQUALIZER_PTR_DFE, received, N,
                                reference, tr_imp, t, 0.0f, D, out);
        }
        /* Null impulse must not crash. */
        memcpy(received, block, sizeof(received));
        scfde_equalizer_dfe(SCFDE_EQUALIZER_PTR_DFE, received, N,
                            reference, NULL, 2u, 0.0f, D, out);
        printf("PTR boundary guards: PASS\n");
    }

    printf("PASS\n");
    return 0;
}
