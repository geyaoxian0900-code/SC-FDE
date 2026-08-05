#ifndef SCFDE_LDPC_H
#define SCFDE_LDPC_H

#include <stdint.h>

#define SCFDE_LDPC_INFO_BITS 128u
#define SCFDE_LDPC_CODE_BITS 192u
#define SCFDE_LDPC_PARITY_BITS 64u

/** Encode 128 unpacked information bits into 192 unpacked systematic bits. */
void scfde_ldpc_encode(const uint8_t *info_bits, uint8_t *code_bits);

/**
 * Decode the project-specific systematic (192,128) sparse code by normalized
 * min-sum message passing.
 * @param llr 192 log-likelihood metrics; negative values favor bit 1.
 * @param info_bits Receives 128 unpacked hard bits.
 * @param max_iterations Maximum check/variable update passes.
 * @return 1 when the final syndrome is zero, otherwise 0.
 */
uint8_t scfde_ldpc_decode(const float *llr, uint8_t *info_bits, uint8_t max_iterations);

#endif
