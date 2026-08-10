#ifndef SCFDE_TURBO_H
#define SCFDE_TURBO_H

#include <stdint.h>
#include "scfde_fft.h"

/* Chapter-4 turbo components for the embedded modem.
 *
 * Frame contract inside the fixed SC-FDE frame:
 *   DATA(96 QPSK symbols) = 192 coded bits = 96 information bits
 *   code: rate-1/2 convolutional (7,5)_8, no tail termination
 *   interleaver: fixed 192-bit permutation (deterministic, MCU-safe)
 *
 * The decoder is Log-MAP BCJR (4 states, T=96) with the standard
 * forward/backward recursion and max* combination (max-log optional).
 */

#define SCFDE_TURBO_INFO_BITS   96u
#define SCFDE_TURBO_CODE_BITS   192u
#define SCFDE_TURBO_STATES      4u
#define SCFDE_TURBO_TIME        (SCFDE_TURBO_CODE_BITS / 2u)   /* 96 */

/** Encode 96 info bits into 192 systematic-free coded bits ((7,5) conv). */
void scfde_turbo_conv_encode(const uint8_t *info_bits, uint8_t *coded_bits);

/** Fixed 192-bit interleaver (bit level). out[i] = in[perm[i]]. */
void scfde_turbo_interleave(const uint8_t *in, uint8_t *out);

/** Fixed 192-bit deinterleaver. out[perm[i]] = in[i]. */
void scfde_turbo_deinterleave(const float *in, float *out);

/**
 * Log-MAP BCJR SISO decoder.
 * @param coded_llr 192 coded-bit LLRs (positive favors bit 1).
 * @param info_llr  96 information-bit LLRs out.
 * @param info_bits 96 hard decisions out.
 * @param max_log   nonzero to use Max-Log-MAP approximation.
 */
void scfde_turbo_bcjr(const float *coded_llr, float *info_llr,
                      uint8_t *info_bits, uint8_t max_log);

/**
 * Extended BCJR: also returns the coded-bit posterior LLRs (used to
 * rebuild the soft-symbol feedback frame in turbo iterations).
 */
void scfde_turbo_bcjr_ext(const float *coded_llr, float *info_llr,
                          float *coded_out, uint8_t *info_bits,
                          uint8_t max_log);

/** Float-domain interleaver (coded LLR feedback). */
void scfde_turbo_interleave_f(const float *in, float *out);

/** QPSK soft symbols from coded LLRs: tanh(l/2)/sqrt(2) per axis. */
void scfde_turbo_soft_symbols(const float *coded_llr, scfde_complex_t *symbols);

#endif
