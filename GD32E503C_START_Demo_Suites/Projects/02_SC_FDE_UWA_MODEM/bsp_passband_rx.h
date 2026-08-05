#ifndef BSP_PASSBAND_RX_H
#define BSP_PASSBAND_RX_H

#include <stdint.h>

#define PASSBAND_RX_DEFAULT_CAPTURE_LENGTH    8192u

/** Configure PA0/ADC0, TIMER2, DMA0 channel 0, and the capture buffer. */
void passband_rx_init(void);

/** Start a fresh DMA capture at buffer index zero. */
void passband_rx_start_dma(uint32_t length);

/** Start DMA after a previously copied signal-detection preroll. */
void passband_rx_start_dma_append(uint32_t start_index, uint32_t length);

/** Block until the DMA ISR marks the active capture complete. */
void passband_rx_wait_complete(void);

/** Set peak-to-peak trigger threshold and required consecutive 32-sample batches. */
void passband_rx_set_signal_wait_profile(uint16_t range_threshold, uint8_t stable_batches);

/** Restore the compiled signal-detection threshold and stability count. */
void passband_rx_restore_default_signal_wait_profile(void);

/**
 * Poll ADC samples until a stable signal is detected or timeout expires.
 * @return Number of preroll samples copied into the capture buffer, or zero
 *         on timeout. A nonzero result must be followed by start_dma_append.
 */
uint32_t passband_rx_wait_signal(uint32_t timeout_ms);

/** Stop TIMER2, ADC triggering, and DMA capture. */
void passband_rx_stop(void);

/** Return the number of valid entries currently stored in the RX buffer. */
uint32_t passband_rx_get_captured_length(void);

/** Return the statically allocated receive-buffer capacity. */
uint32_t passband_rx_get_buffer_capacity(void);

/** Return one captured sample, or zero when index is outside the valid range. */
uint16_t passband_rx_get_sample(uint32_t index);

/** Return the read-only base address of the static ADC capture buffer. */
const uint16_t *passband_rx_get_buffer(void);

/** DMA0 channel 0 ISR service routine called by gd32e50x_it.c. */
void passband_rx_dma_irq_handler(void);

#endif
