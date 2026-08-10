#ifndef SCFDE_CCK_H
#define SCFDE_CCK_H

#include "scfde_fft.h"
#include "scfde_modem.h"
#include <stdint.h>

/* Chapter-5 CCK modem (IEEE 802.11b complementary-code keying, FR-CCK).
   Frame: UW1(32) | UW2(32) | 16 CCK words (128 chips) | UW3(32) = 224 symbols.
   Each word carries 8 bits -> 16 bytes of packet data per frame. */

#define SCFDE_CCK_WORDS          16u
#define SCFDE_CCK_CHIPS          (SCFDE_CCK_WORDS * 8u)
#define SCFDE_CCK_BOOK_SIZE      256u
#define SCFDE_CCK_MAX_PAYLOAD    10u
#define SCFDE_CCK_PACKET_BYTES   16u
#define SCFDE_CCK_PACKET_CRC_INDEX 14u
#define SCFDE_CCK_FRAME_SYMBOLS  (2u * SCFDE_UW_LENGTH + SCFDE_CCK_CHIPS + SCFDE_UW_LENGTH)
#define SCFDE_CCK_RX_MAX_SYMBOLS 256u

/** Receiver type used by scfde_cck_decode. */
typedef enum
{
    SCFDE_CCK_RX_MFB = 0,      /**< Matched-filter bound (nearest book). */
    SCFDE_CCK_RX_RAKE,         /**< Chip-level rake combining. */
    SCFDE_CCK_RX_DFE,          /**< Candidate-list decision-feedback (limit 128). */
    SCFDE_CCK_RX_BIDFE,        /**< Bidirectional DFE score fusion (BiDFE-1). */
    SCFDE_CCK_RX_BIDFE2,       /**< BiDFE-1 plus refinement pass (BiDFE-2). */
    SCFDE_CCK_RX_TR_DIVERSITY, /**< Time-reversal dual-branch diversity. */
    SCFDE_CCK_RX_FDE           /**< Frequency-domain IBDFE, 2 iterations. */
} scfde_cck_receiver_t;

/** Initialize the CCK codebook (256 x 8 chips, unit energy). */
void scfde_cck_init(void);

/**
 * Prepare a CCK transmit frame from a packet.
 * @param payload Up to SCFDE_CCK_MAX_PAYLOAD bytes; framed as
 *        A5 5A len seq payload CRC16, then 8 bits per CCK word.
 * @return 1 on success, 0 on invalid length.
 */
uint8_t scfde_cck_prepare_tx(const uint8_t *payload, uint8_t length, uint8_t sequence);

/** Total modulated samples of the prepared CCK frame. */
uint32_t scfde_cck_get_tx_sample_length(void);

/** One 16-bit DAC sample of the prepared CCK frame. */
int16_t scfde_cck_get_tx_sample(uint32_t index);

/**
 * Full CCK receive chain: I&D downconvert, UW correlation sync, CFO
 * correction, LS channel estimate, then the selected receiver, CRC.
 * @param samples ADC capture buffer.
 * @param sample_count Number of captured samples.
 * @param receiver Which of the seven receivers to run.
 */
scfde_rx_result_t scfde_cck_decode(const uint16_t *samples, uint32_t sample_count,
                                   scfde_cck_receiver_t receiver);

/** Receiver display name. */
const char *scfde_cck_receiver_name(scfde_cck_receiver_t receiver);

#endif
