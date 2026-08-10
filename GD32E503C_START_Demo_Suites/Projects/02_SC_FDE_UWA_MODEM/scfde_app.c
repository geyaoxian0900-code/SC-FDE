#include "scfde_app.h"
#include "main.h"
#include <stdio.h>
#include <string.h>

/**
 * @file scfde_app.c
 * @brief Foreground node-role state machine and serial user interface.
 *
 * This layer coordinates BSP and modem APIs but contains no DSP. Roles only
 * restrict visible commands; each command number keeps one meaning in every
 * role. Command 0 returns to role selection without resetting the MCU.
 */

#define APP_RX_SIGNAL_TIMEOUT_MS 5000u

typedef enum
{
    APP_ROLE_DIAGNOSTIC = 1,
    APP_ROLE_TX_ONLY,
    APP_ROLE_RX_ONLY,
    APP_ROLE_TRANSCEIVER
} app_role_t;

static uint8_t g_sequence;
static uint16_t g_loopback_samples[SCFDE_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL];

static const char *app_role_name(app_role_t role)
{
    switch(role)
    {
    case APP_ROLE_TX_ONLY: return "TX only";
    case APP_ROLE_RX_ONLY: return "RX only";
    case APP_ROLE_TRANSCEIVER: return "manual transceiver";
    case APP_ROLE_DIAGNOSTIC:
    default: return "local diagnostic";
    }
}

static uint8_t app_read_command(void)
{
    uint8_t command;
    do
    {
        command = usart_get_byte();
    } while((command == '\r') || (command == '\n'));
    printf("%c\r\n",command);
    return command;
}

static uint8_t app_read_line(uint8_t *data,uint8_t capacity)
{
    uint8_t length=0u;
    while(1)
    {
        uint8_t value=usart_get_byte();
        if((value=='\r') || (value=='\n'))
        {
            printf("\r\n"); return length;
        }
        if((value==0x08u) || (value==0x7Fu))
        {
            if(length>0u){length--;printf("\b \b");}
            continue;
        }
        if(length<capacity){data[length++]=value;printf("%c",value);}
    }
}

static void app_print_banner(void)
{
    printf("\r\n========================================\r\n");
    printf(" GD32E508VE SC-FDE Underwater Modem\r\n");
    printf("========================================\r\n");
    printf("PHY : QPSK, 4 ksym/s, 12 kHz carrier\r\n");
#if SCFDE_LDPC_ENABLED
    printf("FEC : LDPC(192,128), payload <= %u bytes\r\n",SCFDE_MAX_PAYLOAD);
#else
    printf("FEC : none (baseline), payload <= %u bytes\r\n",SCFDE_MAX_PAYLOAD);
#endif
    printf("EQ  : MMSE-FDE (baseline)\r\n");
}

static app_role_t app_select_role(void)
{
    while(1)
    {
        uint8_t command;
        printf("\r\nSelect node role:\r\n");
        printf("  1: local diagnostic (no external wiring)\r\n");
        printf("  2: transmitter node\r\n");
        printf("  3: receiver node\r\n");
        printf("  4: manual transceiver\r\n");
        printf("role> "); command=app_read_command();
        if((command>='1') && (command<='4'))
        {
            app_role_t role=(app_role_t)(command-'0');
            printf("Role selected: %s\r\n",app_role_name(role)); return role;
        }
        printf("Invalid role. Input 1, 2, 3 or 4.\r\n");
    }
}

static void app_print_result(const scfde_rx_result_t *result)
{
    uint8_t i; uint32_t metric_milli=(uint32_t)(result->sync_metric*1000.0f);
    printf("sync=%lu.%03lu start=%lu CFO=%ld Hz EQ=%s\r\n",
           (unsigned long)(metric_milli/1000u),(unsigned long)(metric_milli%1000u),
           (unsigned long)result->frame_start_sample,(long)result->frequency_offset_hz,
           scfde_equalizer_name(result->equalizer_used));
    if(result->valid==0u){printf("RX FAIL: synchronization, LDPC, header or CRC.\r\n");return;}
    printf("RX OK: seq=%u len=%u hex=",result->sequence,result->payload_length);
    for(i=0u;i<result->payload_length;i++){printf("%02X ",result->payload[i]);}
    printf(" text=");
    for(i=0u;i<result->payload_length;i++)
    {
        uint8_t value=result->payload[i]; printf("%c",((value>=32u)&&(value<=126u))?value:'.');
    }
    printf("\r\n");
}

static void app_prepare_loopback(const uint8_t *payload,uint8_t length,uint8_t sequence)
{
    uint32_t index;
    /* Decimate the internally generated 96 kHz DAC stream by two to emulate
       the 48 kHz ADC, then add the same 2048-code hardware midpoint. */
    scfde_modem_prepare_tx(payload,length,sequence);
    for(index=0u;index<(SCFDE_FRAME_SYMBOLS*SCFDE_RX_SAMPLES_PER_SYMBOL);index++)
    {
        int32_t adc=2048+(int32_t)scfde_modem_get_tx_sample(index*2u);
        if(adc<0){adc=0;}else if(adc>4095){adc=4095;}
        g_loopback_samples[index]=(uint16_t)adc;
    }
}

static void app_transmit(void)
{
    uint8_t payload[SCFDE_MAX_PAYLOAD]; uint8_t length;
    uint8_t turbo=app_is_turbo_mode();
    uint8_t max_len=turbo?SCFDE_TURBO_MAX_PAYLOAD:SCFDE_MAX_PAYLOAD;
    printf("Text (max %u bytes): ",max_len);
    length=app_read_line(payload,max_len);
    if(turbo)
    {
        if(scfde_modem_prepare_tx_turbo(payload,length,g_sequence)==0u){printf("TX packet rejected.\r\n");return;}
    }
    else if(scfde_modem_prepare_tx(payload,length,g_sequence)==0u){printf("TX packet rejected.\r\n");return;}
    printf("TX start: seq=%u len=%u, PA4 DAC active for 48 ms...\r\n",g_sequence,length);
    half_duplex_enter_tx();
    passband_tx_send_blocking(0,scfde_modem_get_tx_sample_length());
    half_duplex_enter_idle();
    printf("TX OK: samples=%lu\r\n",(unsigned long)scfde_modem_get_tx_sample_length());
    g_sequence++;
}

static void app_receive(void)
{
    uint32_t preroll; uint32_t remaining; scfde_rx_result_t result;
    printf("RX armed: waiting up to %u ms for acoustic signal...\r\n",APP_RX_SIGNAL_TIMEOUT_MS);
    /* Signal wait preserves samples before threshold crossing; DMA append
       completes one contiguous synchronization search window. */
    half_duplex_enter_rx(); preroll=passband_rx_wait_signal(APP_RX_SIGNAL_TIMEOUT_MS);
    if(preroll==0u){half_duplex_enter_idle();printf("RX timeout: no signal above threshold.\r\n");return;}
    remaining=SCFDE_RX_CAPTURE_LENGTH-preroll;
    passband_rx_start_dma_append(preroll,remaining); passband_rx_wait_complete();
    half_duplex_enter_idle();
    printf("RX captured: %lu samples, decoding...\r\n",(unsigned long)passband_rx_get_captured_length());
    if(app_is_turbo_mode())
    {
        result=scfde_modem_decode_turbo_mode(scfde_modem_get_equalizer(),
            passband_rx_get_buffer(),passband_rx_get_captured_length());
    }
    else
    {
        result=scfde_modem_decode(passband_rx_get_buffer(),passband_rx_get_captured_length());
    }
    app_print_result(&result);
}

static void app_digital_loopback(void)
{
    static const uint8_t payload[]={'S','C','-','F','D','E'}; scfde_rx_result_t result;
    printf("Digital loopback with %s...\r\n",scfde_equalizer_name(scfde_modem_get_equalizer()));
    if(app_is_turbo_mode())
    {
        static const uint8_t tp[]={'S','C','-','F','D','E'};
        app_prepare_loopback_turbo(tp,(uint8_t)sizeof(tp),0x55u);
        result=scfde_modem_decode_turbo_mode(scfde_modem_get_equalizer(),
            g_loopback_samples,SCFDE_FRAME_SYMBOLS*SCFDE_RX_SAMPLES_PER_SYMBOL);
    }
    else
    {
        app_prepare_loopback(payload,(uint8_t)sizeof(payload),0x55u);
        result=scfde_modem_decode(g_loopback_samples,SCFDE_FRAME_SYMBOLS*SCFDE_RX_SAMPLES_PER_SYMBOL);
    }
    app_print_result(&result);
}

#define APP_ANALOG_PREROLL_SAMPLES  256u
#define APP_ANALOG_TAIL_SAMPLES     256u

static void app_analog_loopback(void)
{
    /* DAC-ADC analog self-loopback: capture a silent preroll first, then
       transmit through PA4->PA0 (series resistor optional) while the DMA
       capture continues. The frame start is therefore expected around the
       preroll boundary. Text is read from the console (<=18 bytes); an
       empty line falls back to "SC-FDE1234" for automated testing. */
    uint8_t payload[SCFDE_MAX_PAYLOAD];
    uint8_t payload_length;
    const uint32_t frame_tx_samples=scfde_modem_get_tx_sample_length();
    const uint32_t frame_rx_samples=frame_tx_samples/2u;
    const uint32_t capture_length=
        APP_ANALOG_PREROLL_SAMPLES+frame_rx_samples+APP_ANALOG_TAIL_SAMPLES;
    uint32_t i;
    uint32_t sum=0u;
    uint16_t adc_min;
    uint16_t adc_max;
    uint16_t clipped=0u;
    scfde_rx_result_t result;

    printf("Analog self-loopback with %s...\r\n",
           scfde_equalizer_name(scfde_modem_get_equalizer()));
    printf("Text (max %u bytes): ",SCFDE_MAX_PAYLOAD);
    payload_length=app_read_line(payload,SCFDE_MAX_PAYLOAD);
    if(payload_length==0u)
    {
        static const uint8_t fallback[]={'S','C','-','F','D','E','1','2','3','4'};
        memcpy(payload,fallback,sizeof(fallback));
        payload_length=(uint8_t)sizeof(fallback);
        printf("(empty line: using fallback \"SC-FDE1234\")\r\n");
    }
    if(scfde_modem_prepare_tx(payload,payload_length,0xAAu)==0u)
    {
        printf("TX packet rejected.\r\n");
        return;
    }
    half_duplex_enter_rx();
    /* phase 1: preroll silence with the DAC idle */
    passband_rx_start_dma(APP_ANALOG_PREROLL_SAMPLES);
    passband_rx_wait_complete();
    /* phase 2: keep capturing while the DAC transmits the frame */
    passband_rx_start_dma_append(APP_ANALOG_PREROLL_SAMPLES,
                                 frame_rx_samples+APP_ANALOG_TAIL_SAMPLES);
    passband_tx_send_blocking(0,frame_tx_samples);
    passband_rx_wait_complete();
    passband_rx_stop();
    half_duplex_enter_idle();

    {
        const uint16_t *buf=passband_rx_get_buffer();
        const uint32_t n=passband_rx_get_captured_length();
        adc_min=4095u;
        adc_max=0u;
        for(i=0u;i<n;i++)
        {
            uint16_t v=buf[i];
            if(v<adc_min){adc_min=v;}
            if(v>adc_max){adc_max=v;}
            if((v==0u)||(v==4095u)){clipped++;}
            sum+=v;
        }
        printf("ADC min=%u max=%u mean=%lu clipped=%u samples=%lu\r\n",
               adc_min,adc_max,(unsigned long)(sum/n),clipped,(unsigned long)n);
        result=scfde_modem_decode(buf,n);
    }
    app_print_result(&result);
}

static void app_select_equalizer(void)
{
    scfde_equalizer_mode_t mode=scfde_modem_get_equalizer();
    mode=(scfde_equalizer_mode_t)(((uint8_t)mode+1u)%(uint8_t)SCFDE_EQUALIZER_COUNT);
    scfde_modem_set_equalizer(mode); printf("Equalizer selected: %s\r\n",scfde_equalizer_name(mode));
}


static void app_print_role_menu(app_role_t role)
{
    printf("\r\n[%s] equalizer=%s\r\n",app_role_name(role),scfde_equalizer_name(scfde_modem_get_equalizer()));
    if((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_TRANSCEIVER)){printf("  1: transmit text\r\n");}
    if((role==APP_ROLE_RX_ONLY)||(role==APP_ROLE_TRANSCEIVER)){printf("  2: receive one frame\r\n");}
    if(role==APP_ROLE_DIAGNOSTIC){printf("  3: digital loopback with selected equalizer\r\n");}
    printf("  4: select next equalizer\r\n");
    if(role==APP_ROLE_DIAGNOSTIC){printf("  5: DAC-ADC analog self-loopback\r\n");}
    printf("  0: change node role\r\n");
    printf("cmd> ");
}

static uint8_t app_command_allowed(app_role_t role,uint8_t command)
{
    if((command=='0')||(command=='4')||(command=='5')){return 1u;}
    if((command=='1')&&((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_TRANSCEIVER))){return 1u;}
    if((command=='2')&&((role==APP_ROLE_RX_ONLY)||(role==APP_ROLE_TRANSCEIVER))){return 1u;}
    if((command=='3')&&(role==APP_ROLE_DIAGNOSTIC)){return 1u;}
    return 0u;
}

void scfde_app_run(void)
{
    app_role_t role; app_print_banner(); role=app_select_role();
    while(1)
    {
        uint8_t command; app_print_role_menu(role); command=app_read_command();
        if(app_command_allowed(role,command)==0u){printf("Command is not available for this role.\r\n");continue;}
        if(command=='0'){role=app_select_role();}
        else if(command=='1'){app_transmit();}
        else if(command=='2'){app_receive();}
        else if(command=='3'){app_digital_loopback();}
        else if(command=='4'){app_select_equalizer();}
        else if(command=='5'){app_analog_loopback();}
    }
}
