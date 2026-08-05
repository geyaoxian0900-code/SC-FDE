#include "bsp_passband_tx.h"
#include "gd32e50x.h"
#include "uwa_modem.h"
//==================== 负责用DAC+TIMER6发射通带波形 ====================
#define PASSBAND_TX_TIMER                TIMER6
#define PASSBAND_TX_GPIO_PORT            GPIOA
#define PASSBAND_TX_GPIO_PIN             GPIO_PIN_4
#define PASSBAND_TX_DAC_CHANNEL          DAC_OUT_0
#define PASSBAND_TX_DMA_PERIPH           DMA1
#define PASSBAND_TX_DMA_CHANNEL          DMA_CH2
#define PASSBAND_TX_DAC_DATA_ADDR        ((uint32_t)(&OUT0_R12DH))
#define PASSBAND_TX_DMA_ALL_FLAGS        (DMA_FLAG_G | DMA_FLAG_FTF | DMA_FLAG_HTF | DMA_FLAG_ERR)
#define PASSBAND_TX_SAMPLE_RATE_HZ       DSSS_TX_SAMPLE_RATE_HZ
#define PASSBAND_TX_DAC_ALIGN            DAC_ALIGN_12B_R
#define PASSBAND_TX_DAC_MIDPOINT         2048u
#define PASSBAND_TX_DAC_MIN              0u
#define PASSBAND_TX_DAC_MAX              4095u
#define PASSBAND_TX_DMA_BUFFER_LENGTH    512u

static uint16_t g_passband_tx_dma_buffer[PASSBAND_TX_DMA_BUFFER_LENGTH];

static uint32_t passband_tx_get_apb1_divider(void)
{
    uint32_t apb1_psc_bits;

    apb1_psc_bits = GET_BITS(RCU_CFG0, 8, 10);

    switch(apb1_psc_bits)
    {
    case 4u:
        return 2u;

    case 5u:
        return 4u;

    case 6u:
        return 8u;

    case 7u:
        return 16u;

    default:
        return 1u;
    }
}

static uint32_t passband_tx_get_timer_clock_hz(void)
{
    uint32_t apb1_divider;
    uint32_t apb1_clock_hz;

    SystemCoreClockUpdate();

    apb1_divider = passband_tx_get_apb1_divider();
    apb1_clock_hz = SystemCoreClock / apb1_divider;

    if(apb1_divider == 1u)
    {
        return apb1_clock_hz;
    }

    return apb1_clock_hz * 2u;
}

static uint16_t passband_tx_convert_sample_to_dac(int16_t sample)
{
    int32_t dac_value;

    dac_value = (int32_t)PASSBAND_TX_DAC_MIDPOINT + sample;

    if(dac_value < (int32_t)PASSBAND_TX_DAC_MIN)
    {
        dac_value = PASSBAND_TX_DAC_MIN;
    }
    else if(dac_value > (int32_t)PASSBAND_TX_DAC_MAX)
    {
        dac_value = PASSBAND_TX_DAC_MAX;
    }

    return (uint16_t)dac_value;
}

static void passband_tx_prepare_dma_buffer(const int16_t *samples, uint32_t length)
{
    uint32_t index;

    for(index = 0; index < length; index++)
    {
        g_passband_tx_dma_buffer[index] = passband_tx_convert_sample_to_dac(samples[index]);
    }
}

static void passband_tx_wait_one_update_event(void)
{
    while(timer_flag_get(PASSBAND_TX_TIMER, TIMER_FLAG_UP) == RESET)
    {
    }

    timer_flag_clear(PASSBAND_TX_TIMER, TIMER_FLAG_UP);
}

static void passband_tx_stop_output(void)
{
    timer_disable(PASSBAND_TX_TIMER);
    dma_channel_disable(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL);
    dma_flag_clear(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, PASSBAND_TX_DMA_ALL_FLAGS);
    dac_dma_disable(PASSBAND_TX_DAC_CHANNEL);
    dac_trigger_disable(PASSBAND_TX_DAC_CHANNEL);
    dac_flag_clear(PASSBAND_TX_DAC_CHANNEL, DAC_FLAG_DDUDR0);
    dac_data_set(PASSBAND_TX_DAC_CHANNEL, PASSBAND_TX_DAC_ALIGN, PASSBAND_TX_DAC_MIDPOINT);
}

static void passband_tx_enter_cpu_mode(void)
{
    timer_disable(PASSBAND_TX_TIMER);
    dma_channel_disable(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL);
    dma_flag_clear(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, PASSBAND_TX_DMA_ALL_FLAGS);
    dac_dma_disable(PASSBAND_TX_DAC_CHANNEL);
    dac_trigger_disable(PASSBAND_TX_DAC_CHANNEL);
    dac_flag_clear(PASSBAND_TX_DAC_CHANNEL, DAC_FLAG_DDUDR0);
}

static void passband_tx_enter_dma_mode(void)
{
    timer_disable(PASSBAND_TX_TIMER);
    dma_channel_disable(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL);
    dma_flag_clear(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, PASSBAND_TX_DMA_ALL_FLAGS);
    dac_flag_clear(PASSBAND_TX_DAC_CHANNEL, DAC_FLAG_DDUDR0);
    timer_master_output_trigger_source_select(PASSBAND_TX_TIMER, TIMER_TRI_OUT_SRC_UPDATE);
    dac_trigger_source_config(PASSBAND_TX_DAC_CHANNEL, DAC_TRIGGER_T6_TRGO);
    dac_trigger_enable(PASSBAND_TX_DAC_CHANNEL);
    dac_dma_enable(PASSBAND_TX_DAC_CHANNEL);
}

void passband_tx_init(void)
{
    timer_parameter_struct timer_init_struct;
    uint32_t timer_clock_hz;
    uint32_t autoreload_value;

    rcu_periph_clock_enable(RCU_GPIOA);
    rcu_periph_clock_enable(RCU_DAC);
    rcu_periph_clock_enable(RCU_TIMER6);
    rcu_periph_clock_enable(RCU_DMA1);

    gpio_init(PASSBAND_TX_GPIO_PORT, GPIO_MODE_AIN, GPIO_OSPEED_50MHZ, PASSBAND_TX_GPIO_PIN);

    dac_deinit();
    dac_trigger_disable(PASSBAND_TX_DAC_CHANNEL);
    dac_dma_disable(PASSBAND_TX_DAC_CHANNEL);
    dac_wave_mode_config(PASSBAND_TX_DAC_CHANNEL, DAC_WAVE_DISABLE);
    dac_output_buffer_enable(PASSBAND_TX_DAC_CHANNEL);
    dac_enable(PASSBAND_TX_DAC_CHANNEL);
    dac_flag_clear(PASSBAND_TX_DAC_CHANNEL, DAC_FLAG_DDUDR0);
    dac_data_set(PASSBAND_TX_DAC_CHANNEL, PASSBAND_TX_DAC_ALIGN, PASSBAND_TX_DAC_MIDPOINT);

    timer_deinit(PASSBAND_TX_TIMER);
    timer_struct_para_init(&timer_init_struct);

    timer_clock_hz = passband_tx_get_timer_clock_hz();
    autoreload_value = (timer_clock_hz / PASSBAND_TX_SAMPLE_RATE_HZ) - 1u;

    timer_init_struct.prescaler = 0u;
    timer_init_struct.alignedmode = TIMER_COUNTER_EDGE;
    timer_init_struct.counterdirection = TIMER_COUNTER_UP;
    timer_init_struct.period = (uint16_t)autoreload_value;
    timer_init_struct.clockdivision = TIMER_CKDIV_DIV1;
    timer_init_struct.repetitioncounter = 0u;

    timer_init(PASSBAND_TX_TIMER, &timer_init_struct);
    timer_master_output_trigger_source_select(PASSBAND_TX_TIMER, TIMER_TRI_OUT_SRC_UPDATE);
    timer_auto_reload_shadow_enable(PASSBAND_TX_TIMER);
    timer_update_event_enable(PASSBAND_TX_TIMER);
    timer_flag_clear(PASSBAND_TX_TIMER, TIMER_FLAG_UP);
    timer_disable(PASSBAND_TX_TIMER);

    dma_deinit(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL);
    dma_flag_clear(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, PASSBAND_TX_DMA_ALL_FLAGS);
}

void passband_tx_send_blocking(const int16_t *samples, uint32_t length)
{
    uint32_t index;

    if(length == 0u)
    {
        return;
    }

    passband_tx_enter_cpu_mode();

    timer_counter_value_config(PASSBAND_TX_TIMER, 0u);
    timer_flag_clear(PASSBAND_TX_TIMER, TIMER_FLAG_UP);
    timer_enable(PASSBAND_TX_TIMER);

    for(index = 0; index < length; index++)
    {
        int16_t sample_value;

        if(samples != 0)
        {
            sample_value = samples[index];
        }
        else
        {
            sample_value = dsss_modem_get_tx_sample(index);
        }

        passband_tx_wait_one_update_event();
        dac_data_set(PASSBAND_TX_DAC_CHANNEL, PASSBAND_TX_DAC_ALIGN, passband_tx_convert_sample_to_dac(sample_value));
    }

    passband_tx_stop_output();
}

void passband_tx_send_dma_blocking(const int16_t *samples, uint32_t length)
{
    dma_parameter_struct dma_init_struct;

    if((samples == 0) || (length == 0u) || (length > PASSBAND_TX_DMA_BUFFER_LENGTH))
    {
        return;
    }

    passband_tx_prepare_dma_buffer(samples, length);
    passband_tx_enter_dma_mode();

    dac_data_set(PASSBAND_TX_DAC_CHANNEL, PASSBAND_TX_DAC_ALIGN, g_passband_tx_dma_buffer[0]);
    timer_counter_value_config(PASSBAND_TX_TIMER, 0u);
    timer_flag_clear(PASSBAND_TX_TIMER, TIMER_FLAG_UP);

    if(length == 1u)
    {
        timer_enable(PASSBAND_TX_TIMER);
        passband_tx_wait_one_update_event();
        passband_tx_stop_output();
        return;
    }

    dma_struct_para_init(&dma_init_struct);
    dma_init_struct.periph_addr = PASSBAND_TX_DAC_DATA_ADDR;
    dma_init_struct.periph_width = DMA_PERIPHERAL_WIDTH_16BIT;
    dma_init_struct.periph_inc = DMA_PERIPH_INCREASE_DISABLE;
    dma_init_struct.memory_addr = (uint32_t)(&g_passband_tx_dma_buffer[1]);
    dma_init_struct.memory_width = DMA_MEMORY_WIDTH_16BIT;
    dma_init_struct.memory_inc = DMA_MEMORY_INCREASE_ENABLE;
    dma_init_struct.number = length - 1u;
    dma_init_struct.direction = DMA_MEMORY_TO_PERIPHERAL;
    dma_init_struct.priority = DMA_PRIORITY_ULTRA_HIGH;

    dma_deinit(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL);
    dma_flag_clear(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, PASSBAND_TX_DMA_ALL_FLAGS);
    dma_init(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, &dma_init_struct);
    dma_circulation_disable(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL);
    dma_channel_enable(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL);

    timer_enable(PASSBAND_TX_TIMER);

    while(dma_flag_get(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, DMA_FLAG_FTF) == RESET)
    {
    }

    dma_flag_clear(PASSBAND_TX_DMA_PERIPH, PASSBAND_TX_DMA_CHANNEL, PASSBAND_TX_DMA_ALL_FLAGS);

    /* The last sample is already in the DAC holding register, so one more
       timer update is needed to push it to the PA4 output pin. */
    timer_flag_clear(PASSBAND_TX_TIMER, TIMER_FLAG_UP);
    passband_tx_wait_one_update_event();

    passband_tx_stop_output();
}
