#ifndef BSP_PASSBAND_RX_H
#define BSP_PASSBAND_RX_H

#include <stdint.h>

#define PASSBAND_RX_DEFAULT_CAPTURE_LENGTH    49152u

void passband_rx_init(void);
void passband_rx_start_dma(uint32_t length);
void passband_rx_start_dma_append(uint32_t start_index, uint32_t length);
void passband_rx_wait_complete(void);
void passband_rx_set_signal_wait_profile(uint16_t range_threshold, uint8_t stable_batches);
void passband_rx_restore_default_signal_wait_profile(void);
uint32_t passband_rx_wait_signal(uint32_t timeout_ms);
void passband_rx_stop(void);
uint32_t passband_rx_get_captured_length(void);
uint32_t passband_rx_get_buffer_capacity(void);
uint16_t passband_rx_get_sample(uint32_t index);
const uint16_t *passband_rx_get_buffer(void);
void passband_rx_dma_irq_handler(void);

#endif
