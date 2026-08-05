#include "bsp_usart.h"
#include <stdio.h>
//==================== 负责串口，阻塞延时和printf重定向 ====================
int fputc(int ch, FILE *f)
{
    (void)f;
    usart_data_transmit(USART0, (uint8_t)ch);
    while(usart_flag_get(USART0, USART_FLAG_TC) == RESET)
    {
    }
    return ch;
}

void system_init(void)
{
}

void usart0_init(void)
{
    rcu_periph_clock_enable(RCU_GPIOA);
    rcu_periph_clock_enable(RCU_USART0);

    gpio_init(GPIOA, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_9);
    gpio_init(GPIOA, GPIO_MODE_IPU, GPIO_OSPEED_50MHZ, GPIO_PIN_10);

    usart_baudrate_set(USART0, 9600);
    usart_word_length_set(USART0, USART_WL_8BIT);
    usart_stop_bit_set(USART0, USART_STB_1BIT);
    usart_parity_config(USART0, USART_PM_NONE);
    usart_receive_config(USART0, USART_RECEIVE_ENABLE);
    usart_transmit_config(USART0, USART_TRANSMIT_ENABLE);

    usart_enable(USART0);
}

void delay_ms(uint32_t ms)
{
    volatile uint32_t i;
    volatile uint32_t j;

    for(i = 0; i < ms; i++)
    {
        for(j = 0; j < 3000; j++)
        {
        }
    }
}

uint8_t usart_get_byte(void)
{
    while(usart_flag_get(USART0, USART_FLAG_RBNE) == RESET)
    {
    }
    return (uint8_t)usart_data_receive(USART0);
}

uint8_t usart_try_get_byte(uint8_t *byte_out)
{
    if(byte_out == 0)
    {
        return 0u;
    }

    if(usart_flag_get(USART0, USART_FLAG_RBNE) == RESET)
    {
        return 0u;
    }

    *byte_out = (uint8_t)usart_data_receive(USART0);
    return 1u;
}
