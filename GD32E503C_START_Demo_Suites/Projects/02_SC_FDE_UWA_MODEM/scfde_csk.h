#ifndef SCFDE_CSK_H
#define SCFDE_CSK_H

#include "scfde_fft.h"
#include "scfde_modem.h"
#include <stdint.h>

/* Chapter-6 CSK modem (cyclic-shift keying spread spectrum, book 6.1).
   Frame: UW1(32) | UW2(32) | 48 CSK symbols x 8 chips (384 chips) | UW3(32)
   = 512 symbols = 6144 RX samples (within the 8192-sample capture).
   Each symbol carries 2 bits (M=4 cyclic shifts of an 8-chip root
   sequence), so the packet (6-byte overhead) holds up to 6 payload bytes. */

#define SCFDE_CSK_CODE_LENGTH     8u
#define SCFDE_CSK_ORDER           2u            /* log2(M), M=4 */
#define SCFDE_CSK_SYMBOLS         48u
#define SCFDE_CSK_CHIPS           (SCFDE_CSK_SYMBOLS * SCFDE_CSK_CODE_LENGTH)
#define SCFDE_CSK_MAX_PAYLOAD     6u
#define SCFDE_CSK_PACKET_BYTES    (SCFDE_CSK_MAX_PAYLOAD + 6u)
#define SCFDE_CSK_PACKET_CRC_INDEX (SCFDE_CSK_PACKET_BYTES - 2u)
#define SCFDE_CSK_FRAME_SYMBOLS   (2u * SCFDE_UW_LENGTH + SCFDE_CSK_CHIPS + SCFDE_UW_LENGTH)
#define SCFDE_CSK_RX_MAX_SYMBOLS  640u

/** Receiver type used by scfde_csk_decode. */
typedef enum
{
    SCFDE_CSK_RX_MF = 0,   /**< Matched-filter dictionary correlation (6-7..6-12). */
    SCFDE_CSK_RX_SOFT_SIC, /**< Soft successive interference cancellation (6.2.2). */
    SCFDE_CSK_RX_ESE       /**< IDMA-ESE (single-user; output equals the MF
                                fallback, matching the MATLAB export). */
} scfde_csk_receiver_t;

/** Initialize the CSK root sequence and codebook. */
void scfde_csk_init(void);

/** Prepare a CSK transmit frame from a packet (<= SCFDE_CSK_MAX_PAYLOAD). */
uint8_t scfde_csk_prepare_tx(const uint8_t *payload, uint8_t length, uint8_t sequence);

/** Total modulated samples of the prepared CSK frame. */
uint32_t scfde_csk_get_tx_sample_length(void);

/** One 16-bit DAC sample of the prepared CSK frame. */
int16_t scfde_csk_get_tx_sample(uint32_t index);

/** Full CSK receive chain: sync, CFO, LS channel, dictionary receiver, CRC. */
scfde_rx_result_t scfde_csk_decode(const uint16_t *samples, uint32_t sample_count,
                                   scfde_csk_receiver_t receiver);

/** Receiver display name. */
const char *scfde_csk_receiver_name(scfde_csk_receiver_t receiver);

#endif
