/* test_fft.c - FFT/IFFT correctness: impulse, complex exponential, and
 * round-trip error. Uses the real firmware scfde_fft(). */
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include "scfde_fft.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

static double max_err(const scfde_complex_t *a, const double *ref, uint16_t n)
{
    double worst = 0.0;
    uint16_t k;
    for (k = 0; k < n; k++)
    {
        double e = fabs((double)a[k].re - ref[2 * k]) +
                   fabs((double)a[k].im - ref[2 * k + 1]);
        if (e > worst) worst = e;
    }
    return worst;
}

int main(void)
{
    scfde_complex_t x[128];
    uint16_t n = 128u, k;
    double ref[256];

    /* 1) FFT of delta(n) must be all ones. */
    for (k = 0; k < n; k++) { x[k].re = 0.0f; x[k].im = 0.0f; }
    x[0].re = 1.0f;
    scfde_fft(x, n, 0u);
    for (k = 0; k < n; k++)
    {
        CHECK(fabs(x[k].re - 1.0f) < 1e-5f && fabs(x[k].im) < 1e-5f,
              "FFT of delta must be all ones");
    }

    /* 2) FFT of exp(j*2*pi*m*k/N) must be a single peak at bin m. */
    for (k = 0; k < n; k++)
    {
        double a = 2.0 * M_PI * 7.0 * k / n;
        x[k].re = (float)cos(a); x[k].im = (float)sin(a);
    }
    scfde_fft(x, n, 0u);
    for (k = 0; k < n; k++)
    {
        double peak = (k == 7u) ? 128.0 : 0.0;
        CHECK(fabs((double)x[k].re - peak) < 1e-3 &&
              fabs((double)x[k].im) < 1e-3, "single-tone FFT peak wrong");
    }

    /* 3) IFFT(FFT(x)) == x round trip at 128 and 32 points. */
    for (k = 0; k < n; k++)
    {
        double a = 2.0 * M_PI * (13.0 * k + 5.0) / n;
        x[k].re = (float)(0.5 * cos(a) + 0.3 * sin(3 * a));
        x[k].im = (float)(-0.2 * cos(7 * a));
        ref[2 * k] = x[k].re; ref[2 * k + 1] = x[k].im;
    }
    scfde_fft(x, n, 0u);
    scfde_fft(x, n, 1u);
    {
        double e = max_err(x, ref, n);
        printf("128-pt round trip max err = %.3e\n", e);
        CHECK(e < 1e-4, "128-pt FFT round trip exceeds tolerance");
    }

    n = 32u;
    for (k = 0; k < n; k++)
    {
        double a = 2.0 * M_PI * 3.0 * k / n;
        x[k].re = (float)cos(a); x[k].im = (float)sin(2 * a);
        ref[2 * k] = x[k].re; ref[2 * k + 1] = x[k].im;
    }
    scfde_fft(x, n, 0u);
    scfde_fft(x, n, 1u);
    {
        double e = max_err(x, ref, n);
        printf("32-pt round trip max err = %.3e\n", e);
        CHECK(e < 1e-5, "32-pt FFT round trip exceeds tolerance");
    }

    printf("PASS\n");
    return 0;
}
