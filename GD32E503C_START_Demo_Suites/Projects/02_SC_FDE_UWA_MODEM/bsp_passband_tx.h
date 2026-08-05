#ifndef BSP_PASSBAND_TX_H
#define BSP_PASSBAND_TX_H

#include <stdint.h>

/** Configure PA4/DAC0, TIMER6, and DMA1 channel 2 for 96 kHz output. */
void passband_tx_init(void);

/**
 * Send signed passband samples synchronously.
 * @param samples Optional source array. When NULL, samples are generated on
 *        demand by scfde_modem_get_tx_sample(), which avoids a frame buffer.
 * @param length Number of DAC updates to emit.
 */
void passband_tx_send_blocking(const int16_t *samples, uint32_t length);

/** Send a caller-provided block through the 512-sample staging DMA buffer. */
void passband_tx_send_dma_blocking(const int16_t *samples, uint32_t length);

#endif
