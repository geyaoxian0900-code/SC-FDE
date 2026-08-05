#include "scfde_fft.h"
#include <math.h>

/**
 * @file scfde_fft.c
 * @brief In-place radix-2 decimation-in-time FFT for lengths up to 128.
 *
 * One 128-point twiddle table serves both the 32-point UW estimator and the
 * 128-point SC-FDE block. Short transforms stride through the master table.
 */

#define SCFDE_FFT_MAX_SIZE 128u
#define SCFDE_PI           3.14159265358979323846f

static scfde_complex_t g_twiddle[SCFDE_FFT_MAX_SIZE / 2u];
static uint8_t g_fft_initialized;

void scfde_fft_init(void)
{
    uint16_t k;

    /* Store exp(-j*2*pi*k/128). The inverse transform conjugates each entry. */
    for(k = 0u; k < (SCFDE_FFT_MAX_SIZE / 2u); k++)
    {
        float angle = -2.0f * SCFDE_PI * (float)k / (float)SCFDE_FFT_MAX_SIZE;
        g_twiddle[k].re = cosf(angle);
        g_twiddle[k].im = sinf(angle);
    }
    g_fft_initialized = 1u;
}

static uint16_t scfde_reverse_bits(uint16_t value, uint8_t bits)
{
    uint16_t result = 0u;

    while(bits > 0u)
    {
        result = (uint16_t)((result << 1u) | (value & 1u));
        value >>= 1u;
        bits--;
    }
    return result;
}

void scfde_fft(scfde_complex_t *x, uint16_t n, uint8_t inverse)
{
    uint16_t i;
    uint16_t length;
    uint8_t bits = 0u;

    if((x == 0) || (n < 2u) || (n > SCFDE_FFT_MAX_SIZE) || ((n & (n - 1u)) != 0u))
    {
        return;
    }
    if(g_fft_initialized == 0u)
    {
        scfde_fft_init();
    }

    for(length = n; length > 1u; length >>= 1u)
    {
        bits++;
    }
    /* Bit reversal prepares natural-order input for iterative butterflies. */
    for(i = 0u; i < n; i++)
    {
        uint16_t j = scfde_reverse_bits(i, bits);
        if(j > i)
        {
            scfde_complex_t temp = x[i];
            x[i] = x[j];
            x[j] = temp;
        }
    }

    /* Each stage doubles the butterfly span. twiddle_step maps transforms
       shorter than 128 onto the fixed master twiddle table. */
    for(length = 2u; length <= n; length <<= 1u)
    {
        uint16_t half = length >> 1u;
        uint16_t twiddle_step = SCFDE_FFT_MAX_SIZE / length;
        uint16_t base;

        for(base = 0u; base < n; base += length)
        {
            uint16_t j;
            for(j = 0u; j < half; j++)
            {
                scfde_complex_t w = g_twiddle[j * twiddle_step];
                scfde_complex_t even = x[base + j];
                scfde_complex_t odd = x[base + j + half];
                scfde_complex_t product;

                if(inverse != 0u)
                {
                    w.im = -w.im;
                }
                product.re = odd.re * w.re - odd.im * w.im;
                product.im = odd.re * w.im + odd.im * w.re;
                x[base + j].re = even.re + product.re;
                x[base + j].im = even.im + product.im;
                x[base + j + half].re = even.re - product.re;
                x[base + j + half].im = even.im - product.im;
            }
        }
    }

    if(inverse != 0u)
    {
        float scale = 1.0f / (float)n;
        for(i = 0u; i < n; i++)
        {
            x[i].re *= scale;
            x[i].im *= scale;
        }
    }
}
