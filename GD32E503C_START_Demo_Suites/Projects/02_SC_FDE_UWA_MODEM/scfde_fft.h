#ifndef SCFDE_FFT_H
#define SCFDE_FFT_H

#include <stdint.h>

typedef struct
{
    float re; /**< Real component. */
    float im; /**< Imaginary component. */
} scfde_complex_t;

/** Precompute the 128-point master twiddle table. Safe to call repeatedly. */
void scfde_fft_init(void);

/**
 * Perform an in-place radix-2 complex FFT.
 * @param x Array containing n complex values.
 * @param n Power of two in [2,128]. Invalid lengths are ignored.
 * @param inverse 0 for forward FFT; nonzero for inverse FFT scaled by 1/n.
 */
void scfde_fft(scfde_complex_t *x, uint16_t n, uint8_t inverse);

#endif
