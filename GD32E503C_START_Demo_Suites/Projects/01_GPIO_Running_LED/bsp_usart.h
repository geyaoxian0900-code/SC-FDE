#ifndef BSP_USART_H
#define BSP_USART_H

#include "gd32e50x.h"
#include <stdint.h>

void system_init(void);
void usart0_init(void);
void delay_ms(uint32_t ms);
uint8_t usart_get_byte(void);
uint8_t usart_try_get_byte(uint8_t *byte_out);

#endif
