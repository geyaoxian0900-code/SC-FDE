#ifndef BSP_HALF_DUPLEX_H
#define BSP_HALF_DUPLEX_H

#include <stdint.h>

#define HALF_DUPLEX_CTRL_ENABLE          0u
#define HALF_DUPLEX_RX_TO_TX_GUARD_MS    2u
#define HALF_DUPLEX_TX_TO_RX_GUARD_MS    5u

typedef enum
{
    HALF_DUPLEX_STATE_IDLE = 0,
    HALF_DUPLEX_STATE_TX = 1,
    HALF_DUPLEX_STATE_RX = 2
} half_duplex_state_t;

void half_duplex_init(void);
void half_duplex_enter_idle(void);
void half_duplex_enter_tx(void);
void half_duplex_enter_rx(void);
void half_duplex_sync_init_tx(void);
void half_duplex_sync_init_rx(void);
void half_duplex_sync_pulse_start(void);
void half_duplex_sync_wait_start(void);
uint8_t half_duplex_sync_wait_start_timeout(uint32_t timeout_ms);

half_duplex_state_t half_duplex_get_state(void);
const char *half_duplex_get_state_name(half_duplex_state_t state);
uint8_t half_duplex_control_is_enabled(void);
uint16_t half_duplex_get_rx_to_tx_guard_ms(void);
uint16_t half_duplex_get_tx_to_rx_guard_ms(void);

#endif
