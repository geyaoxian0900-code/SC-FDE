#ifndef BSP_PASSBAND_TX_H
#define BSP_PASSBAND_TX_H

#include <stdint.h>

void passband_tx_init(void);
void passband_tx_send_blocking(const int16_t *samples, uint32_t length);
void passband_tx_send_dma_blocking(const int16_t *samples, uint32_t length);

#endif
