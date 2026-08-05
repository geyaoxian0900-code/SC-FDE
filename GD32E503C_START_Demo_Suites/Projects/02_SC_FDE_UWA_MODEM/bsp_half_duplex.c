#include "bsp_half_duplex.h"
#include "bsp_usart.h"
#include "gd32e50x.h"
/**
 * @file bsp_half_duplex.c
 * @brief Optional PB0/PB1 front-end direction control and guard timing.
 *
 * With control disabled, logical state changes but no GPIO is driven. Guard
 * intervals allow the power amplifier and receive preamplifier to settle.
 */
//==================== 负责收发半双工状态和切换保护时间 ====================
#define HALF_DUPLEX_CTRL_GPIO_PORT       GPIOB
#define HALF_DUPLEX_CTRL_GPIO_CLOCK      RCU_GPIOB
#define HALF_DUPLEX_TX_EN_PIN            GPIO_PIN_0
#define HALF_DUPLEX_RX_EN_PIN            GPIO_PIN_1
#define HALF_DUPLEX_TX_ACTIVE_LEVEL      1u
#define HALF_DUPLEX_RX_ACTIVE_LEVEL      1u
#define HALF_DUPLEX_SYNC_TX_PIN          GPIO_PIN_0
#define HALF_DUPLEX_SYNC_RX_PIN          GPIO_PIN_1
#define HALF_DUPLEX_SYNC_PULSE_MS        2u

static half_duplex_state_t g_half_duplex_state = HALF_DUPLEX_STATE_IDLE;

static uint8_t half_duplex_sync_rx_is_active(void)
{
    return (gpio_input_bit_get(HALF_DUPLEX_CTRL_GPIO_PORT, HALF_DUPLEX_SYNC_RX_PIN) != RESET) ? 1u : 0u;
}

static void half_duplex_write_pin(uint32_t pin, uint8_t active_level, uint8_t enabled)
{
    if(enabled == 0u)
    {
        if(active_level != 0u)
        {
            gpio_bit_reset(HALF_DUPLEX_CTRL_GPIO_PORT, pin);
        }
        else
        {
            gpio_bit_set(HALF_DUPLEX_CTRL_GPIO_PORT, pin);
        }
        return;
    }

    if(active_level != 0u)
    {
        gpio_bit_set(HALF_DUPLEX_CTRL_GPIO_PORT, pin);
    }
    else
    {
        gpio_bit_reset(HALF_DUPLEX_CTRL_GPIO_PORT, pin);
    }
}

static void half_duplex_apply_state(half_duplex_state_t state)
{
#if HALF_DUPLEX_CTRL_ENABLE
    /* TX and RX are never enabled together. IDLE leaves RX enabled. */
    switch(state)
    {
    case HALF_DUPLEX_STATE_TX:
        half_duplex_write_pin(HALF_DUPLEX_TX_EN_PIN, HALF_DUPLEX_TX_ACTIVE_LEVEL, 1u);
        half_duplex_write_pin(HALF_DUPLEX_RX_EN_PIN, HALF_DUPLEX_RX_ACTIVE_LEVEL, 0u);
        break;

    case HALF_DUPLEX_STATE_RX:
        half_duplex_write_pin(HALF_DUPLEX_TX_EN_PIN, HALF_DUPLEX_TX_ACTIVE_LEVEL, 0u);
        half_duplex_write_pin(HALF_DUPLEX_RX_EN_PIN, HALF_DUPLEX_RX_ACTIVE_LEVEL, 1u);
        break;

    case HALF_DUPLEX_STATE_IDLE:
    default:
        half_duplex_write_pin(HALF_DUPLEX_TX_EN_PIN, HALF_DUPLEX_TX_ACTIVE_LEVEL, 0u);
        half_duplex_write_pin(HALF_DUPLEX_RX_EN_PIN, HALF_DUPLEX_RX_ACTIVE_LEVEL, 1u);
        break;
    }
#else
    (void)state;
#endif
}

void half_duplex_init(void)
{
#if HALF_DUPLEX_CTRL_ENABLE
    rcu_periph_clock_enable(HALF_DUPLEX_CTRL_GPIO_CLOCK);
    gpio_init(HALF_DUPLEX_CTRL_GPIO_PORT, GPIO_MODE_OUT_PP, GPIO_OSPEED_50MHZ, HALF_DUPLEX_TX_EN_PIN | HALF_DUPLEX_RX_EN_PIN);
#endif

    g_half_duplex_state = HALF_DUPLEX_STATE_IDLE;
    half_duplex_apply_state(g_half_duplex_state);
}

void half_duplex_enter_idle(void)
{
    g_half_duplex_state = HALF_DUPLEX_STATE_IDLE;
    half_duplex_apply_state(g_half_duplex_state);
}

void half_duplex_enter_tx(void)
{
    g_half_duplex_state = HALF_DUPLEX_STATE_TX;
    half_duplex_apply_state(g_half_duplex_state);
    delay_ms(HALF_DUPLEX_RX_TO_TX_GUARD_MS);
}

void half_duplex_enter_rx(void)
{
    g_half_duplex_state = HALF_DUPLEX_STATE_RX;
    half_duplex_apply_state(g_half_duplex_state);
    delay_ms(HALF_DUPLEX_TX_TO_RX_GUARD_MS);
}

void half_duplex_sync_init_tx(void)
{
    rcu_periph_clock_enable(HALF_DUPLEX_CTRL_GPIO_CLOCK);
    gpio_init(HALF_DUPLEX_CTRL_GPIO_PORT, GPIO_MODE_OUT_PP, GPIO_OSPEED_50MHZ, HALF_DUPLEX_SYNC_TX_PIN);
    gpio_bit_reset(HALF_DUPLEX_CTRL_GPIO_PORT, HALF_DUPLEX_SYNC_TX_PIN);
}

void half_duplex_sync_init_rx(void)
{
    rcu_periph_clock_enable(HALF_DUPLEX_CTRL_GPIO_CLOCK);
    gpio_init(HALF_DUPLEX_CTRL_GPIO_PORT, GPIO_MODE_IPD, GPIO_OSPEED_50MHZ, HALF_DUPLEX_SYNC_RX_PIN);
}

void half_duplex_sync_pulse_start(void)
{
    gpio_bit_set(HALF_DUPLEX_CTRL_GPIO_PORT, HALF_DUPLEX_SYNC_TX_PIN);
    delay_ms(HALF_DUPLEX_SYNC_PULSE_MS);
    gpio_bit_reset(HALF_DUPLEX_CTRL_GPIO_PORT, HALF_DUPLEX_SYNC_TX_PIN);
}

void half_duplex_sync_wait_start(void)
{
    while(half_duplex_sync_rx_is_active() != 0u)
    {
    }

    while(half_duplex_sync_rx_is_active() == 0u)
    {
    }
}

uint8_t half_duplex_sync_wait_start_timeout(uint32_t timeout_ms)
{
    uint32_t waited_ms;

    waited_ms = 0u;

    while(half_duplex_sync_rx_is_active() != 0u)
    {
        if(waited_ms >= timeout_ms)
        {
            return 0u;
        }

        delay_ms(1);
        waited_ms++;
    }

    while(half_duplex_sync_rx_is_active() == 0u)
    {
        if(waited_ms >= timeout_ms)
        {
            return 0u;
        }

        delay_ms(1);
        waited_ms++;
    }

    return 1u;
}

half_duplex_state_t half_duplex_get_state(void)
{
    return g_half_duplex_state;
}

const char *half_duplex_get_state_name(half_duplex_state_t state)
{
    switch(state)
    {
    case HALF_DUPLEX_STATE_TX:
        return "tx";

    case HALF_DUPLEX_STATE_RX:
        return "rx";

    case HALF_DUPLEX_STATE_IDLE:
    default:
        return "idle";
    }
}

uint8_t half_duplex_control_is_enabled(void)
{
#if HALF_DUPLEX_CTRL_ENABLE
    return 1u;
#else
    return 0u;
#endif
}

uint16_t half_duplex_get_rx_to_tx_guard_ms(void)
{
    return HALF_DUPLEX_RX_TO_TX_GUARD_MS;
}

uint16_t half_duplex_get_tx_to_rx_guard_ms(void)
{
    return HALF_DUPLEX_TX_TO_RX_GUARD_MS;
}
