#ifndef SCFDE_MODEM_H
#define SCFDE_MODEM_H

#include <stdint.h>
#include "scfde_equalizer.h"
#include "scfde_turbo.h"

/* Chapter-4 turbo mode (B1 core): DATA carries 96 info bits coded by the
   rate-1/2 (7,5) convolutional code, interleaved, then QPSK-mapped.
   Packet: magic(2)+len(1)+seq(1)+payload(<=6)+CRC16(2) = 12 bytes. */
#define SCFDE_TURBO_PACKET_BYTES   12u
#define SCFDE_TURBO_MAX_PAYLOAD    6u
#define SCFDE_TURBO_CRC_INDEX      (SCFDE_TURBO_PACKET_BYTES - 2u)

/* Fixed over-the-air profile compiled into the MCU firmware.
 *
 * Frame in complex symbols:
 *   UW1(32) | UW2(32) | QPSK DATA(96) | UW3(32)
 *
 * UW1 is the cyclic prefix for UW2. UW2 is the channel-estimation training
 * block. DATA plus UW3 forms the 128-symbol circular equalization block.
 * Keep the sample rates integer multiples of SCFDE_SYMBOL_RATE_HZ. Changing
 * any block length also requires checking the packet size, static arrays,
 * DMA capture length, and the corresponding MATLAB profile.
 *
 * Baseline scheme: rectangular pulse shape (24-sample TX hold, 12-sample
 * integrate-and-dump RX), MMSE-FDE only. LDPC is compiled out by default
 * (SCFDE_LDPC_ENABLED 0); re-enabling it restores the coded frame and the
 * smaller 16-byte packet, and must be mirrored in MATLAB (ldpcEnabled).
 */
#define SCFDE_TX_SAMPLE_RATE_HZ       96000u
#define SCFDE_RX_SAMPLE_RATE_HZ       48000u
#define SCFDE_CARRIER_FREQ_HZ         12000u
#define SCFDE_SYMBOL_RATE_HZ          4000u
#define SCFDE_TX_SAMPLES_PER_SYMBOL   24u
#define SCFDE_RX_SAMPLES_PER_SYMBOL   12u
#define SCFDE_FFT_SIZE                128u
#define SCFDE_UW_LENGTH               32u
#define SCFDE_DATA_SYMBOLS            96u
#define SCFDE_FRAME_SYMBOLS           192u
#define SCFDE_RX_CAPTURE_LENGTH       4096u

#define SCFDE_LDPC_ENABLED            0u
#if SCFDE_LDPC_ENABLED
#define SCFDE_MAX_PAYLOAD             10u
#define SCFDE_PACKET_BYTES            16u
#else
#define SCFDE_MAX_PAYLOAD             18u
#define SCFDE_PACKET_BYTES            24u
#endif

typedef struct
{
    uint8_t valid;                 /**< 1 only after synchronization, LDPC, header, and CRC pass. */
    uint8_t crc_ok;                /**< CRC16-CCITT result; currently identical to valid on success. */
    uint8_t payload_length;        /**< Number of valid bytes in payload. */
    uint8_t sequence;              /**< Transmitter frame sequence field. */
    uint8_t payload[SCFDE_MAX_PAYLOAD]; /**< Decoded application bytes. */
    uint32_t frame_start_sample;   /**< Detected frame start in the supplied ADC buffer. */
    float sync_metric;             /**< Normalized two-UW correlation metric. */
    float frequency_offset_hz;     /**< Mean residual carrier offset estimated from three UWs. */
    scfde_equalizer_mode_t equalizer_used; /**< Equalizer that produced the CRC-valid packet. */
} scfde_rx_result_t;

/** Initialize FFT tables, construct the Chu UW, and clear modem state. */
void scfde_modem_init(void);

/**
 * Build one LDPC-coded QPSK transmit frame.
 * @param payload Application bytes; may be NULL only when length is zero.
 * @param length Number of bytes, limited to SCFDE_MAX_PAYLOAD.
 * @param sequence Application sequence number inserted in the packet header.
 * @return 1 when the frame was accepted and prepared, otherwise 0.
 */
uint8_t scfde_modem_prepare_tx(const uint8_t *payload, uint8_t length, uint8_t sequence);

/** Return the fixed number of 96 kHz DAC samples in one prepared frame. */
uint32_t scfde_modem_get_tx_sample_length(void);

/**
 * Generate one signed passband sample from the prepared frame.
 * @param index Sample index in [0, scfde_modem_get_tx_sample_length()).
 * @return Sample centered on zero; the DAC BSP adds its 2048-code bias.
 */
int16_t scfde_modem_get_tx_sample(uint32_t index);

/**
 * Decode one ADC capture through synchronization, Doppler correction,
 * channel estimation, equalization, LDPC, and CRC.
 * @param samples Unsigned 12-bit ADC samples with an arbitrary DC midpoint.
 * @param sample_count Number of entries in samples; values above the capture
 *        limit are clipped internally.
 * @return Fully initialized result. Check result.valid before using payload.
 * @note This function uses static work buffers and is not reentrant.
 */
scfde_rx_result_t scfde_modem_decode(const uint16_t *samples, uint32_t sample_count);

/** Select AUTO or one fixed equalizer for subsequent decode calls. */
void scfde_modem_set_equalizer(scfde_equalizer_mode_t mode);

/** Return the currently configured equalizer mode. */
scfde_equalizer_mode_t scfde_modem_get_equalizer(void);

/**
 * Chapter-4 turbo mode transmit: prepare a conv-coded, interleaved QPSK
 * frame from a payload (<= SCFDE_TURBO_MAX_PAYLOAD bytes).
 */
uint8_t scfde_modem_prepare_tx_turbo(const uint8_t *payload, uint8_t length,
                                     uint8_t sequence);

/**
 * Chapter-4 turbo mode receive: full sync/LS/MMSE chain, then
 * deinterleave and Log-MAP BCJR decode of the 96 coded information bits.
 */
scfde_rx_result_t scfde_modem_decode_turbo(const uint16_t *samples,
                                           uint32_t sample_count);

#endif
