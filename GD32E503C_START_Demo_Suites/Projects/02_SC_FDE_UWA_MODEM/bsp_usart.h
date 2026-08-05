#ifndef BSP_USART_H
#define BSP_USART_H

#include "gd32e50x.h"
#include <stdint.h>

/** Application-level system hook retained for compatibility with demo projects. */
void system_init(void);

/** Configure USART0 on PA9/PA10 for 9600 baud, 8 data bits, no parity, 1 stop bit. */
void usart0_init(void);

/** Busy-wait millisecond delay used only for low-rate control and guard timing. */
void delay_ms(uint32_t ms);

/** Block until one USART0 byte is received. */
uint8_t usart_get_byte(void);

/** Return 1 and store a byte when available; return 0 without blocking otherwise. */
uint8_t usart_try_get_byte(uint8_t *byte_out);

#endif
