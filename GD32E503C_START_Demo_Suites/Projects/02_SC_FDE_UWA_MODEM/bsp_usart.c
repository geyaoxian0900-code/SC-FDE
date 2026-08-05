/**
 * @file bsp_usart.c
 * @brief Blocking USART0 console and low-rate control delay helpers.
 *
 * PA9 is TX and PA10 is RX at 9600 8-N-1. printf is retargeted through fputc;
 * do not call it from timing-critical ADC or DAC interrupt service routines.
 */

#include "bsp_usart.h"
#include <stdio.h>

/** Retarget one stdio character to the blocking USART0 transmitter. */
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
    /* Clock startup is performed by system_gd32e50x.c before main(). This
       hook is retained to match the vendor demo application structure. */
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

    /* Approximate busy delay for analog guard intervals and UI pacing only.
       TIMER peripherals, not this loop, define symbol and sample timing. */
    for(i = 0u; i < ms; i++)
    {
        for(j = 0u; j < 3000u; j++)
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
