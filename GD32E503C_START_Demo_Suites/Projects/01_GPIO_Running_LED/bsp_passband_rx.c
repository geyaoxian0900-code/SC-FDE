#include "bsp_passband_rx.h"
#include "gd32e50x.h"
#include "gd32e50x_misc.h"
#include "uwa_modem.h"
#include "bsp_usart.h"
//==================== 负责用ADC0+TIMER2+DMA0_CH0采样接收 ====================
#define PASSBAND_RX_ADC_PERIPH             ADC0
#define PASSBAND_RX_GPIO_PORT              GPIOA
#define PASSBAND_RX_GPIO_PIN               GPIO_PIN_0
#define PASSBAND_RX_ADC_CHANNEL            ADC_CHANNEL_0
#define PASSBAND_RX_TIMER                  TIMER2
#define PASSBAND_RX_DMA_PERIPH             DMA0
#define PASSBAND_RX_DMA_CHANNEL            DMA_CH0
#define PASSBAND_RX_DMA_IRQn               DMA0_Channel0_IRQn
#define PASSBAND_RX_DMA_ALL_FLAGS          (DMA_FLAG_G | DMA_FLAG_FTF | DMA_FLAG_HTF | DMA_FLAG_ERR)
#define PASSBAND_RX_SAMPLE_RATE_HZ         DSSS_RX_SAMPLE_RATE_HZ
#define PASSBAND_RX_MAX_BUFFER_LENGTH      PASSBAND_RX_DEFAULT_CAPTURE_LENGTH
#define PASSBAND_RX_ADC_DATA_ADDR          ((uint32_t)(&ADC_RDATA(PASSBAND_RX_ADC_PERIPH)))
#define PASSBAND_RX_SIGNAL_BATCH_COUNT     32u
#define PASSBAND_RX_SIGNAL_RANGE_THRESHOLD_DEFAULT 600u
#define PASSBAND_RX_SIGNAL_STABLE_BATCHES_DEFAULT  2u
#define PASSBAND_RX_SIGNAL_PREROLL_SAMPLES 256u

static uint16_t g_passband_rx_buffer[PASSBAND_RX_MAX_BUFFER_LENGTH];
static uint16_t g_passband_rx_signal_preroll[PASSBAND_RX_SIGNAL_PREROLL_SAMPLES];
static volatile uint8_t g_passband_rx_capture_done = 0u;
static volatile uint8_t g_passband_rx_busy = 0u;
static uint32_t g_passband_rx_capture_length = 0u;
static uint16_t g_passband_rx_signal_range_threshold = PASSBAND_RX_SIGNAL_RANGE_THRESHOLD_DEFAULT;
static uint8_t g_passband_rx_signal_stable_batches = PASSBAND_RX_SIGNAL_STABLE_BATCHES_DEFAULT;

static void passband_rx_copy_preroll_to_buffer(uint32_t preroll_count, uint32_t preroll_write_index)
{
    uint32_t copy_index;
    uint32_t source_index;

    if(preroll_count > PASSBAND_RX_SIGNAL_PREROLL_SAMPLES)
    {
        preroll_count = PASSBAND_RX_SIGNAL_PREROLL_SAMPLES;
    }

    if(preroll_count > PASSBAND_RX_MAX_BUFFER_LENGTH)
    {
        preroll_count = PASSBAND_RX_MAX_BUFFER_LENGTH;
    }

    if(preroll_count == 0u)
    {
        return;
    }

    source_index = preroll_write_index;
    if(preroll_count < PASSBAND_RX_SIGNAL_PREROLL_SAMPLES)
    {
        source_index = 0u;
    }

    for(copy_index = 0u; copy_index < preroll_count; copy_index++)
    {
        g_passband_rx_buffer[copy_index] = g_passband_rx_signal_preroll[source_index];
        source_index++;
        if(source_index >= preroll_count)
        {
            source_index = 0u;
        }
    }
}

static void passband_rx_configure_dma_mode(void)
{
    adc_watchdog0_disable(PASSBAND_RX_ADC_PERIPH);
    adc_flag_clear(PASSBAND_RX_ADC_PERIPH, ADC_FLAG_WDE0);
    adc_special_function_config(PASSBAND_RX_ADC_PERIPH, ADC_CONTINUOUS_MODE, DISABLE);
    adc_external_trigger_source_config(PASSBAND_RX_ADC_PERIPH,
                                       ADC_REGULAR_CHANNEL,
                                       ADC0_1_EXTTRIG_REGULAR_T2_TRGO);
    adc_external_trigger_config(PASSBAND_RX_ADC_PERIPH, ADC_REGULAR_CHANNEL, ENABLE);
    adc_dma_mode_enable(PASSBAND_RX_ADC_PERIPH);
}

static void passband_rx_configure_signal_wait_mode(void)
{
    timer_disable(PASSBAND_RX_TIMER);
    dma_channel_disable(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL);
    dma_interrupt_disable(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, DMA_INT_FTF);
    dma_flag_clear(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, PASSBAND_RX_DMA_ALL_FLAGS);
    adc_dma_mode_disable(PASSBAND_RX_ADC_PERIPH);
    adc_external_trigger_source_config(PASSBAND_RX_ADC_PERIPH,
                                       ADC_REGULAR_CHANNEL,
                                       ADC0_1_2_EXTTRIG_REGULAR_NONE);
    adc_external_trigger_config(PASSBAND_RX_ADC_PERIPH, ADC_REGULAR_CHANNEL, ENABLE);
    adc_special_function_config(PASSBAND_RX_ADC_PERIPH, ADC_CONTINUOUS_MODE, ENABLE);
    adc_watchdog0_disable(PASSBAND_RX_ADC_PERIPH);
    adc_flag_clear(PASSBAND_RX_ADC_PERIPH, ADC_FLAG_WDE0);
    adc_flag_clear(PASSBAND_RX_ADC_PERIPH, ADC_FLAG_EOC);
}

static uint32_t passband_rx_get_apb1_divider(void)
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

static uint32_t passband_rx_get_timer_clock_hz(void)
{
    uint32_t apb1_divider;
    uint32_t apb1_clock_hz;

    SystemCoreClockUpdate();

    apb1_divider = passband_rx_get_apb1_divider();
    apb1_clock_hz = SystemCoreClock / apb1_divider;

    if(apb1_divider == 1u)
    {
        return apb1_clock_hz;
    }

    return apb1_clock_hz * 2u;
}

static void passband_rx_stop_capture(void)
{
    timer_disable(PASSBAND_RX_TIMER);
    dma_channel_disable(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL);
    dma_interrupt_disable(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, DMA_INT_FTF);
    dma_flag_clear(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, PASSBAND_RX_DMA_ALL_FLAGS);
    g_passband_rx_busy = 0u;
}

void passband_rx_init(void)
{
    timer_parameter_struct timer_init_struct;
    uint32_t timer_clock_hz;
    uint32_t autoreload_value;

    rcu_periph_clock_enable(RCU_GPIOA);
    rcu_periph_clock_enable(RCU_ADC0);
    rcu_periph_clock_enable(RCU_TIMER2);
    rcu_periph_clock_enable(RCU_DMA0);

    rcu_adc_clock_config(RCU_CKADC_CKAPB2_DIV8);

    gpio_init(PASSBAND_RX_GPIO_PORT, GPIO_MODE_AIN, GPIO_OSPEED_50MHZ, PASSBAND_RX_GPIO_PIN);

    timer_deinit(PASSBAND_RX_TIMER);
    timer_struct_para_init(&timer_init_struct);

    timer_clock_hz = passband_rx_get_timer_clock_hz();
    autoreload_value = (timer_clock_hz / PASSBAND_RX_SAMPLE_RATE_HZ) - 1u;

    timer_init_struct.prescaler = 0u;
    timer_init_struct.alignedmode = TIMER_COUNTER_EDGE;
    timer_init_struct.counterdirection = TIMER_COUNTER_UP;
    timer_init_struct.period = (uint16_t)autoreload_value;
    timer_init_struct.clockdivision = TIMER_CKDIV_DIV1;
    timer_init_struct.repetitioncounter = 0u;

    timer_init(PASSBAND_RX_TIMER, &timer_init_struct);
    timer_master_output_trigger_source_select(PASSBAND_RX_TIMER, TIMER_TRI_OUT_SRC_UPDATE);
    timer_auto_reload_shadow_enable(PASSBAND_RX_TIMER);
    timer_update_event_enable(PASSBAND_RX_TIMER);
    timer_flag_clear(PASSBAND_RX_TIMER, TIMER_FLAG_UP);
    timer_disable(PASSBAND_RX_TIMER);

    adc_deinit(PASSBAND_RX_ADC_PERIPH);
    adc_mode_config(ADC_MODE_FREE);
    adc_special_function_config(PASSBAND_RX_ADC_PERIPH, ADC_SCAN_MODE, DISABLE);
    adc_special_function_config(PASSBAND_RX_ADC_PERIPH, ADC_CONTINUOUS_MODE, DISABLE);
    adc_data_alignment_config(PASSBAND_RX_ADC_PERIPH, ADC_DATAALIGN_RIGHT);
    adc_channel_length_config(PASSBAND_RX_ADC_PERIPH, ADC_REGULAR_CHANNEL, 1u);
    adc_regular_channel_config(PASSBAND_RX_ADC_PERIPH, 0u, PASSBAND_RX_ADC_CHANNEL, ADC_SAMPLETIME_55POINT5);
    adc_external_trigger_source_config(PASSBAND_RX_ADC_PERIPH, ADC_REGULAR_CHANNEL, ADC0_1_EXTTRIG_REGULAR_T2_TRGO);
    adc_external_trigger_config(PASSBAND_RX_ADC_PERIPH, ADC_REGULAR_CHANNEL, ENABLE);
    adc_enable(PASSBAND_RX_ADC_PERIPH);
    adc_calibration_enable(PASSBAND_RX_ADC_PERIPH);
    adc_dma_mode_enable(PASSBAND_RX_ADC_PERIPH);
    passband_rx_configure_dma_mode();

    dma_deinit(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL);
    dma_flag_clear(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, PASSBAND_RX_DMA_ALL_FLAGS);

    nvic_irq_enable(PASSBAND_RX_DMA_IRQn, 1u, 0u);
}

static void passband_rx_start_dma_internal(uint32_t start_index, uint32_t length)
{
    dma_parameter_struct dma_init_struct;

    if(length == 0u)
    {
        return;
    }

    if(length > PASSBAND_RX_MAX_BUFFER_LENGTH)
    {
        length = PASSBAND_RX_MAX_BUFFER_LENGTH;
    }

    if(start_index >= PASSBAND_RX_MAX_BUFFER_LENGTH)
    {
        return;
    }

    if((start_index + length) > PASSBAND_RX_MAX_BUFFER_LENGTH)
    {
        length = PASSBAND_RX_MAX_BUFFER_LENGTH - start_index;
    }

    passband_rx_stop_capture();
    passband_rx_configure_dma_mode();

    g_passband_rx_capture_length = start_index + length;
    g_passband_rx_capture_done = 0u;
    g_passband_rx_busy = 1u;

    dma_struct_para_init(&dma_init_struct);
    dma_init_struct.periph_addr = PASSBAND_RX_ADC_DATA_ADDR;
    dma_init_struct.periph_width = DMA_PERIPHERAL_WIDTH_16BIT;
    dma_init_struct.periph_inc = DMA_PERIPH_INCREASE_DISABLE;
    dma_init_struct.memory_addr = (uint32_t)(&g_passband_rx_buffer[start_index]);
    dma_init_struct.memory_width = DMA_MEMORY_WIDTH_16BIT;
    dma_init_struct.memory_inc = DMA_MEMORY_INCREASE_ENABLE;
    dma_init_struct.number = length;
    dma_init_struct.direction = DMA_PERIPHERAL_TO_MEMORY;
    dma_init_struct.priority = DMA_PRIORITY_ULTRA_HIGH;

    dma_deinit(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL);
    dma_flag_clear(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, PASSBAND_RX_DMA_ALL_FLAGS);
    dma_init(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, &dma_init_struct);
    dma_circulation_disable(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL);
    dma_interrupt_enable(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, DMA_INT_FTF);
    dma_channel_enable(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL);

    timer_counter_value_config(PASSBAND_RX_TIMER, 0u);
    timer_flag_clear(PASSBAND_RX_TIMER, TIMER_FLAG_UP);
    timer_enable(PASSBAND_RX_TIMER);
}

void passband_rx_start_dma(uint32_t length)
{
    passband_rx_start_dma_internal(0u, length);
}

void passband_rx_start_dma_append(uint32_t start_index, uint32_t length)
{
    passband_rx_start_dma_internal(start_index, length);
}

void passband_rx_wait_complete(void)
{
    while(g_passband_rx_capture_done == 0u)
    {
    }
}

void passband_rx_set_signal_wait_profile(uint16_t range_threshold, uint8_t stable_batches)
{
    if(range_threshold == 0u)
    {
        range_threshold = PASSBAND_RX_SIGNAL_RANGE_THRESHOLD_DEFAULT;
    }

    if(stable_batches == 0u)
    {
        stable_batches = PASSBAND_RX_SIGNAL_STABLE_BATCHES_DEFAULT;
    }

    g_passband_rx_signal_range_threshold = range_threshold;
    g_passband_rx_signal_stable_batches = stable_batches;
}

void passband_rx_restore_default_signal_wait_profile(void)
{
    g_passband_rx_signal_range_threshold = PASSBAND_RX_SIGNAL_RANGE_THRESHOLD_DEFAULT;
    g_passband_rx_signal_stable_batches = PASSBAND_RX_SIGNAL_STABLE_BATCHES_DEFAULT;
}

uint32_t passband_rx_wait_signal(uint32_t timeout_ms)
{
    uint32_t preroll_count;
    uint32_t preroll_write_index;
    uint32_t waited_ms;
    uint32_t stable_batches;

    passband_rx_stop_capture();
    g_passband_rx_capture_done = 0u;
    g_passband_rx_capture_length = 0u;
    passband_rx_configure_signal_wait_mode();
    adc_software_trigger_enable(PASSBAND_RX_ADC_PERIPH, ADC_REGULAR_CHANNEL);

    preroll_count = 0u;
    preroll_write_index = 0u;
    waited_ms = 0u;
    stable_batches = 0u;

    for(;;)
    {
        uint16_t sample_min;
        uint16_t sample_max;
        uint32_t sample_count;
        uint32_t spin_guard;

        sample_min = 4095u;
        sample_max = 0u;
        sample_count = 0u;
        spin_guard = 0u;
        adc_software_trigger_enable(PASSBAND_RX_ADC_PERIPH, ADC_REGULAR_CHANNEL);

        while((sample_count < PASSBAND_RX_SIGNAL_BATCH_COUNT) &&
              (spin_guard < (PASSBAND_RX_SIGNAL_BATCH_COUNT * 64u)))
        {
            if(adc_flag_get(PASSBAND_RX_ADC_PERIPH, ADC_FLAG_EOC) != RESET)
            {
                uint16_t sample;

                sample = adc_regular_data_read(PASSBAND_RX_ADC_PERIPH);
                g_passband_rx_signal_preroll[preroll_write_index] = sample;
                preroll_write_index++;
                if(preroll_write_index >= PASSBAND_RX_SIGNAL_PREROLL_SAMPLES)
                {
                    preroll_write_index = 0u;
                }
                if(preroll_count < PASSBAND_RX_SIGNAL_PREROLL_SAMPLES)
                {
                    preroll_count++;
                }

                if(sample < sample_min)
                {
                    sample_min = sample;
                }
                if(sample > sample_max)
                {
                    sample_max = sample;
                }

                sample_count++;
            }

            spin_guard++;
        }

        if((sample_count > 0u) && ((sample_max - sample_min) >= g_passband_rx_signal_range_threshold))
        {
            stable_batches++;
            if(stable_batches >= g_passband_rx_signal_stable_batches)
            {
                passband_rx_copy_preroll_to_buffer(preroll_count, preroll_write_index);
                g_passband_rx_capture_length = preroll_count;
                passband_rx_configure_dma_mode();
                return preroll_count;
            }
        }
        else
        {
            stable_batches = 0u;
        }

        if((timeout_ms != 0u) && (waited_ms >= timeout_ms))
        {
            passband_rx_configure_dma_mode();
            g_passband_rx_capture_length = 0u;
            return 0u;
        }

        delay_ms(1u);
        waited_ms++;
    }
}

void passband_rx_stop(void)
{
    passband_rx_stop_capture();
    passband_rx_configure_dma_mode();
}

uint32_t passband_rx_get_captured_length(void)
{
    return g_passband_rx_capture_length;
}

uint32_t passband_rx_get_buffer_capacity(void)
{
    return PASSBAND_RX_MAX_BUFFER_LENGTH;
}

uint16_t passband_rx_get_sample(uint32_t index)
{
    if(index >= g_passband_rx_capture_length)
    {
        return 0u;
    }

    return g_passband_rx_buffer[index];
}

const uint16_t *passband_rx_get_buffer(void)
{
    return g_passband_rx_buffer;
}

void passband_rx_dma_irq_handler(void)
{
    if(dma_interrupt_flag_get(PASSBAND_RX_DMA_PERIPH, PASSBAND_RX_DMA_CHANNEL, DMA_INT_FLAG_FTF) != RESET)
    {
        passband_rx_stop_capture();
        g_passband_rx_capture_done = 1u;
    }
}
