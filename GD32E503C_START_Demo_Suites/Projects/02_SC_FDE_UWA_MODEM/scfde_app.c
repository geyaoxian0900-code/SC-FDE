#include "scfde_app.h"
#include "scfde_cck.h"
#include "scfde_csk.h"
#include "scfde_protocol.h"
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
 * Roles 5-8 implement the 01-DSSS MAC protocol (request-response handshake,
 * time-slot burst with 3/5 majority voting) on top of the SC-FDE PHY.
 */

#define APP_RX_SIGNAL_TIMEOUT_MS 5000u
#define APP_PROTO_REPLY_TIMEOUT_MS 4000u
#define APP_PROTO_SLOT_BURST_GAP_MS 50u
#define APP_PROTO_SLOT_RX_TIMEOUT_MS 4000u
#define APP_AUTO_TEST_ROUNDS      200u
#define APP_BURST_FRAME_COUNT     20u
#define APP_BURST_GAP_MS          50u
#define APP_NO_SYNC_WAKE_TONE_MS  200u
#define APP_NO_SYNC_WAKE_GAP_MS   50u
#define APP_NO_SYNC_REPLY_BURST   3u

typedef enum
{
    APP_ROLE_DIAGNOSTIC = 1,
    APP_ROLE_TX_ONLY,
    APP_ROLE_RX_ONLY,
    APP_ROLE_TRANSCEIVER,
    APP_ROLE_REQUESTER,
    APP_ROLE_RESPONDER,
    APP_ROLE_SLOT_A,
    APP_ROLE_SLOT_B,
    APP_ROLE_REQUESTER_NO_SYNC,
    APP_ROLE_RESPONDER_NO_SYNC
} app_role_t;

static uint8_t g_sequence;
static uint8_t g_error_percent;
static uint32_t g_prng = 0x9E3779B9u;
#define APP_LOOPBACK_LEN (SCFDE_CSK_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)
static uint16_t g_loopback_samples[APP_LOOPBACK_LEN];
static int16_t g_wake_tone[APP_NO_SYNC_WAKE_TONE_MS * 96u]; /* 96 kHz */

static const char *app_role_name(app_role_t role)
{
    switch(role)
    {
    case APP_ROLE_TX_ONLY: return "TX only";
    case APP_ROLE_RX_ONLY: return "RX only";
    case APP_ROLE_TRANSCEIVER: return "manual transceiver";
    case APP_ROLE_REQUESTER: return "requester";
    case APP_ROLE_RESPONDER: return "responder";
    case APP_ROLE_SLOT_A: return "slot A";
    case APP_ROLE_SLOT_B: return "slot B";
    case APP_ROLE_REQUESTER_NO_SYNC: return "requester no-sync";
    case APP_ROLE_RESPONDER_NO_SYNC: return "responder no-sync";
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
        printf("  5: requester (request-reply handshake)\r\n");
        printf("  6: responder (echo replies)\r\n");
        printf("  7: slot A (burst tx + 3/5 vote)\r\n");
        printf("  8: slot B (3/5 vote + echo burst)\r\n");
        printf("  9: requester no-sync (wake tone)\r\n");
        printf("  A: responder no-sync (wake-tone listen)\r\n");
        printf("role> "); command=app_read_command();
        if((command>='1') && (command<='9'))
        {
            app_role_t role=(app_role_t)(command-'0');
            printf("Role selected: %s\r\n",app_role_name(role)); return role;
        }
        if((command=='A') || (command=='a'))
        {
            printf("Role selected: %s\r\n",app_role_name(APP_ROLE_RESPONDER_NO_SYNC));
            return APP_ROLE_RESPONDER_NO_SYNC;
        }
        printf("Invalid role. Input 1..9 or A.\r\n");
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

static uint8_t app_is_turbo_mode(void)
{
    scfde_equalizer_mode_t m=scfde_modem_get_equalizer();
    return (m>=SCFDE_EQUALIZER_FD_TURBO)&&(m<=SCFDE_EQUALIZER_TD_TURBO)?1u:0u;
}

static uint8_t app_is_cck_mode(void)
{
    scfde_equalizer_mode_t m=scfde_modem_get_equalizer();
    return (m>=SCFDE_EQUALIZER_CCK_MFB)&&(m<=SCFDE_EQUALIZER_CCK_FDE)?1u:0u;
}

static uint8_t app_is_csk_mode(void)
{
    scfde_equalizer_mode_t m=scfde_modem_get_equalizer();
    return (m>=SCFDE_EQUALIZER_CSK_MF)&&(m<=SCFDE_EQUALIZER_CSK_ESE)?1u:0u;
}

static scfde_cck_receiver_t app_cck_receiver(void)
{
    return (scfde_cck_receiver_t)((uint8_t)scfde_modem_get_equalizer()-
                                  (uint8_t)SCFDE_EQUALIZER_CCK_MFB);
}

static scfde_csk_receiver_t app_csk_receiver(void)
{
    return (scfde_csk_receiver_t)((uint8_t)scfde_modem_get_equalizer()-
                                  (uint8_t)SCFDE_EQUALIZER_CSK_MF);
}

/* Shared transmit-frame dispatch: CCK/CSK frame vs baseline/turbo frame. */
static uint8_t app_prepare_frame(const uint8_t *payload,uint8_t length,uint8_t seq)
{
    if(app_is_cck_mode()){return scfde_cck_prepare_tx(payload,length,seq);}
    if(app_is_csk_mode()){return scfde_csk_prepare_tx(payload,length,seq);}
    if(app_is_turbo_mode()){return scfde_modem_prepare_tx_turbo(payload,length,seq);}
    return scfde_modem_prepare_tx(payload,length,seq);
}

static uint32_t app_frame_tx_samples(void)
{
    if(app_is_cck_mode()){return scfde_cck_get_tx_sample_length();}
    if(app_is_csk_mode()){return scfde_csk_get_tx_sample_length();}
    return scfde_modem_get_tx_sample_length();
}

static int16_t app_frame_tx_sample(uint32_t index)
{
    if(app_is_cck_mode()){return scfde_cck_get_tx_sample(index);}
    if(app_is_csk_mode()){return scfde_csk_get_tx_sample(index);}
    return scfde_modem_get_tx_sample(index);
}

static scfde_rx_result_t app_decode_frame(const uint16_t *samples,uint32_t sample_count)
{
    if(app_is_cck_mode())
    {
        return scfde_cck_decode(samples,sample_count,app_cck_receiver());
    }
    if(app_is_csk_mode())
    {
        return scfde_csk_decode(samples,sample_count,app_csk_receiver());
    }
    if(app_is_turbo_mode())
    {
        return scfde_modem_decode_turbo_mode(scfde_modem_get_equalizer(),samples,sample_count);
    }
    return scfde_modem_decode(samples,sample_count);
}

static void app_transmit(void)
{
    uint8_t payload[SCFDE_MAX_PAYLOAD]; uint8_t length;
    uint8_t turbo=app_is_turbo_mode();
    uint8_t cck=app_is_cck_mode();
    uint8_t csk=app_is_csk_mode();
    uint8_t max_len=turbo?SCFDE_TURBO_MAX_PAYLOAD:
                 (cck?SCFDE_CCK_MAX_PAYLOAD:(csk?SCFDE_CSK_MAX_PAYLOAD:SCFDE_MAX_PAYLOAD));
    printf("Text (max %u bytes): ",max_len);
    length=app_read_line(payload,max_len);
    if(app_prepare_frame(payload,length,g_sequence)==0u){printf("TX packet rejected.\r\n");return;}
    {
        uint8_t i;
        printf("TX preview: seq=%u len=%u hex=",g_sequence,length);
        for(i=0u;i<length;i++){printf("%02X ",payload[i]);}
        printf(" samples=%lu\r\n",(unsigned long)app_frame_tx_samples());
    }
    printf("TX start: seq=%u len=%u, PA4 DAC active for %lu ms...\r\n",
           g_sequence,length,(unsigned long)(app_frame_tx_samples()*2u/96000u));
    half_duplex_enter_tx();
    passband_tx_send_blocking(0,app_frame_tx_samples());
    half_duplex_enter_idle();
    printf("TX OK: samples=%lu\r\n",(unsigned long)app_frame_tx_samples());
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
    result=app_decode_frame(passband_rx_get_buffer(),passband_rx_get_captured_length());
    app_print_result(&result);
}

static void app_digital_loopback(void)
{
    static const uint8_t payload[]={'S','C','-','F','D','E'}; scfde_rx_result_t result;
    printf("Digital loopback with %s...\r\n",scfde_equalizer_name(scfde_modem_get_equalizer()));
    app_prepare_loopback(payload,(uint8_t)sizeof(payload),0x55u);
    result=app_decode_frame(g_loopback_samples,APP_LOOPBACK_LEN);
    app_print_result(&result);
}

/* ------------------------------------------------------------------ */
/* MAC protocol roles (ported from the 01 DSSS demo)                   */
/* ------------------------------------------------------------------ */

static uint8_t app_protocol_tx_frame(uint8_t seq,const uint8_t *payload,uint8_t length)
{
    if(app_prepare_frame(payload,length,seq)==0u){return 0u;}
    half_duplex_enter_tx();
    passband_tx_send_blocking(0,app_frame_tx_samples());
    half_duplex_enter_idle();
    return 1u;
}

/* Receive one frame with a signal-wait timeout; returns the decoded result. */
static scfde_rx_result_t app_protocol_rx_frame(uint32_t timeout_ms)
{
    uint32_t preroll;
    uint32_t remaining;
    scfde_rx_result_t result;
    half_duplex_enter_rx();
    preroll=passband_rx_wait_signal(timeout_ms);
    if(preroll==0u)
    {
        half_duplex_enter_idle();
        memset(&result,0,sizeof(result));
        return result;
    }
    remaining=SCFDE_RX_CAPTURE_LENGTH-preroll;
    passband_rx_start_dma_append(preroll,remaining);
    passband_rx_wait_complete();
    half_duplex_enter_idle();
    result=app_decode_frame(passband_rx_get_buffer(),passband_rx_get_captured_length());
    return result;
}

static void app_run_requester(void)
{
    uint8_t data;
    uint8_t seq;
    uint8_t payload;
    scfde_rx_result_t reply;

    printf("\r\n[Requester] type one byte, then the modem sends a request "
           "frame and waits for the reply.\r\n");
    while(1)
    {
        uint8_t line[2];
        uint8_t length;
        printf("req byte (empty line returns)> ");
        length=app_read_line(line,1u);
        if(length==0u){break;}
        data=line[0];
        scfde_proto_make_request(data,&seq,&payload);
        printf("Request 0x%02X seq=0x%02X...\r\n",data,seq);
        if(app_protocol_tx_frame(seq,&payload,1u)==0u)
        {
            printf("TX packet rejected.\r\n");
            continue;
        }
        reply=app_protocol_rx_frame(APP_PROTO_REPLY_TIMEOUT_MS);
        if(reply.valid==0u)
        {
            printf("Reply timeout (no signal within %u ms).\r\n",APP_PROTO_REPLY_TIMEOUT_MS);
        }
        else if(scfde_proto_is_reply(&reply)!=0u)
        {
            printf("Reply 0x%02X -> %s\r\n",reply.payload[0],
                   (reply.payload[0]==data)?"MATCH":"DATA MISMATCH");
        }
        else
        {
            printf("Unexpected frame (seq=0x%02X len=%u).\r\n",
                   reply.sequence,reply.payload_length);
        }
    }
}

static void app_run_responder(void)
{
    printf("\r\n[Responder] listening for request frames; every request is "
           "echoed back as a reply. Press any key to return.\r\n");
    while(1)
    {
        uint8_t seq;
        uint8_t payload;
        scfde_rx_result_t request;
        uint8_t exit_key;
        if(usart_try_get_byte(&exit_key)!=0u)
        {
            printf("(exit key received)\r\n");
            break;
        }
        request=app_protocol_rx_frame(APP_RX_SIGNAL_TIMEOUT_MS);
        if(request.valid==0u)
        {
            printf("RX window timeout.\r\n");
            continue;
        }
        if(scfde_proto_is_request(&request)!=0u)
        {
            scfde_proto_make_reply(request.payload[0],&seq,&payload);
            printf("Request 0x%02X -> reply 0x%02X\r\n",request.payload[0],payload);
            if(app_protocol_tx_frame(seq,&payload,1u)==0u)
            {
                printf("TX packet rejected.\r\n");
            }
        }
        else
        {
            printf("Ignored frame: seq=0x%02X len=%u%s\r\n",
                   request.sequence,request.payload_length,
                   scfde_proto_is_idle(&request)!=0u?" (idle)":"");
        }
    }
}

static void app_run_slot_a(void)
{
    scfde_proto_vote_t vote;
    printf("\r\n[Slot A] each round: input one byte (empty = idle), send a "
           "5-frame burst, then listen for the peer burst and vote 3/5.\r\n");
    scfde_proto_vote_reset(&vote);
    while(1)
    {
        uint8_t line[2];
        uint8_t length;
        uint8_t tx_data;
        uint8_t seq;
        uint8_t payload;
        uint8_t repeat;
        scfde_proto_vote_result_t result;
        uint8_t tx_count=0u;
        uint8_t idle_count=0u;
        uint8_t rx_ok=0u;
        uint8_t rx_timeout=0u;

        printf("slot byte (empty line returns)> ");
        length=app_read_line(line,1u);
        if(length==0u){break;}
        tx_data=line[0];
        scfde_proto_make_request(tx_data,&seq,&payload);
        printf("TX burst x5: ");
        for(repeat=0u;repeat<SCFDE_PROTO_REPEAT_COUNT;repeat++)
        {
            if(app_protocol_tx_frame(seq,&payload,1u)==0u)
            {
                printf("TX reject!\r\n");
                break;
            }
            tx_count++;
            if((repeat+1u)<SCFDE_PROTO_REPEAT_COUNT)
            {
                delay_ms(APP_PROTO_SLOT_BURST_GAP_MS);
            }
        }
        printf("%u frames sent, waiting peer burst...\r\n",tx_count);
        while(rx_ok<SCFDE_PROTO_REPEAT_COUNT)
        {
            scfde_rx_result_t frame;
            frame=app_protocol_rx_frame(APP_PROTO_SLOT_RX_TIMEOUT_MS);
            if(frame.valid==0u)
            {
                rx_timeout++;
                break;
            }
            if(scfde_proto_is_idle(&frame)!=0u){idle_count++;}
            scfde_proto_vote_consume(&vote,frame.valid,
                                     scfde_proto_is_idle(&frame),
                                     (frame.payload_length>0u)?frame.payload[0]:0u,
                                     &result);
            rx_ok++;
            if(result.finalized!=0u)
            {
                printf("Vote: %s 0x%02X\r\n",
                       result.success!=0u?"majority":"NO MAJORITY",
                       result.rx_data);
                break;
            }
        }
        printf("Slot A round: tx=%u rx_ok=%u timeout=%u idle=%u\r\n",
               tx_count,rx_ok,rx_timeout,idle_count);
    }
}

static void app_run_slot_b(void)
{
    scfde_proto_vote_t vote;
    printf("\r\n[Slot B] each round: listen for the peer burst, vote 3/5, "
           "then echo the majority byte back as a 5-frame burst.\r\n");
    scfde_proto_vote_reset(&vote);
    while(1)
    {
        scfde_proto_vote_result_t result;
        uint8_t rx_ok=0u;
        uint8_t rx_timeout=0u;
        uint8_t tx_data=0u;
        uint8_t repeat;
        uint8_t seq;
        uint8_t payload;
        uint8_t tx_frames=0u;

        printf("Listening for slot A burst...\r\n");
        while(rx_ok<SCFDE_PROTO_REPEAT_COUNT)
        {
            scfde_rx_result_t frame;
            frame=app_protocol_rx_frame(APP_PROTO_SLOT_RX_TIMEOUT_MS);
            if(frame.valid==0u)
            {
                rx_timeout++;
                break;
            }
            scfde_proto_vote_consume(&vote,frame.valid,
                                     scfde_proto_is_idle(&frame),
                                     (frame.payload_length>0u)?frame.payload[0]:0u,
                                     &result);
            rx_ok++;
            if(result.finalized!=0u)
            {
                printf("Vote: %s 0x%02X\r\n",
                       result.success!=0u?"majority":"NO MAJORITY",
                       result.rx_data);
                break;
            }
        }
        if(result.finalized!=0u && result.success!=0u)
        {
            tx_data=result.rx_data;
        }
        printf("Echo burst x5: ");
        for(repeat=0u;repeat<SCFDE_PROTO_REPEAT_COUNT;repeat++)
        {
            uint8_t len;
            if(result.finalized!=0u && result.success!=0u)
            {
                scfde_proto_make_reply(tx_data,&seq,&payload);
                len=1u;
            }
            else
            {
                scfde_proto_make_idle(&seq,&payload,&len);
            }
            if(app_protocol_tx_frame(seq,&payload,len)==0u)
            {
                printf("TX reject!\r\n");
                break;
            }
            tx_frames++;
            if((repeat+1u)<SCFDE_PROTO_REPEAT_COUNT)
            {
                delay_ms(APP_PROTO_SLOT_BURST_GAP_MS);
            }
        }
        printf("%u frames sent.\r\n",tx_frames);
        printf("Slot B round: rx_ok=%u timeout=%u\r\n",rx_ok,rx_timeout);
    }
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
    uint8_t cck=app_is_cck_mode();
    uint8_t csk=app_is_csk_mode();
    uint8_t max_len=cck?SCFDE_CCK_MAX_PAYLOAD:(csk?SCFDE_CSK_MAX_PAYLOAD:SCFDE_MAX_PAYLOAD);
    const uint32_t frame_tx_samples=app_frame_tx_samples();
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
    printf("Text (max %u bytes): ",max_len);
    payload_length=app_read_line(payload,max_len);
    if(payload_length==0u)
    {
        static const uint8_t fallback[]={'S','C','-','F','D','E','1','2','3','4'};
        memcpy(payload,fallback,sizeof(fallback));
        payload_length=(uint8_t)sizeof(fallback);
        printf("(empty line: using fallback \"SC-FDE1234\")\r\n");
    }
    if(app_prepare_frame(payload,payload_length,0xAAu)==0u)
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
        result=app_decode_frame(buf,n);
    }
    app_print_result(&result);
}

static void app_select_equalizer(void)
{
    scfde_equalizer_mode_t mode=scfde_modem_get_equalizer();
    mode=(scfde_equalizer_mode_t)(((uint8_t)mode+1u)%(uint8_t)SCFDE_EQUALIZER_COUNT);
    scfde_modem_set_equalizer(mode); printf("Equalizer selected: %s\r\n",scfde_equalizer_name(mode));
}

/* ------------------------------------------------------------------ */
/* 01-DSSS ported features: error injection, wake tone, auto test,     */
/* burst TX, sync-line RX, no-sync roles, TX preview.                  */
/* ------------------------------------------------------------------ */

static uint32_t app_prng_next(void)
{
    g_prng ^= g_prng << 13u;
    g_prng ^= g_prng >> 17u;
    g_prng ^= g_prng << 5u;
    return g_prng;
}

/* Symbol-block 180-degree phase flips at g_error_percent probability. */
static void app_inject_errors(uint16_t *samples,uint32_t count)
{
    uint32_t i;
    if(g_error_percent==0u){return;}
    for(i=0u;(i+SCFDE_RX_SAMPLES_PER_SYMBOL)<=count;i+=SCFDE_RX_SAMPLES_PER_SYMBOL)
    {
        if((app_prng_next()%100u)<(uint32_t)g_error_percent)
        {
            uint32_t k;
            for(k=0u;k<SCFDE_RX_SAMPLES_PER_SYMBOL;k++)
            {
                int32_t v=(int32_t)samples[i+k]-2048;
                v=2048-v;
                if(v<0){v=0;}else if(v>4095){v=4095;}
                samples[i+k]=(uint16_t)v;
            }
        }
    }
}

static void app_set_error_percent(void)
{
    uint8_t line[4];
    uint8_t length;
    printf("Error percent (0-100, 0=off)> ");
    length=app_read_line(line,sizeof(line));
    if(length==0u)
    {
        g_error_percent=0u;
        printf("Error injection: off.\r\n");
        return;
    }
    g_error_percent=0u;
    {
        uint8_t i;
        for(i=0u;i<length;i++)
        {
            if((line[i]<'0')||(line[i]>'9')){break;}
            g_error_percent=(uint8_t)(g_error_percent*10u+(uint8_t)(line[i]-'0'));
        }
    }
    if(g_error_percent>100u){g_error_percent=100u;}
    printf("Error injection: %u%% symbol blocks flipped.\r\n",g_error_percent);
}

static void app_wake_tone_init(void)
{
    uint32_t i;
    static const int16_t tone_cycle[8]={700,495,0,-495,-700,-495,0,495};
    for(i=0u;i<(uint32_t)(APP_NO_SYNC_WAKE_TONE_MS*96u);i++)
    {
        g_wake_tone[i]=tone_cycle[i&7u];
    }
}

/* 200-round digital loopback stress test with per-round statistics. */
static void app_run_auto_test(void)
{
    static const uint8_t payload[]={'S','C','-','F','D','E'};
    uint16_t round;
    uint16_t ok_count=0u;
    uint16_t sync_ok_count=0u;
    uint16_t data_ok_count=0u;
    uint16_t crc_ok_count=0u;
    printf("Auto test: %u rounds, %s, error=%u%%...\r\n",
           (unsigned int)APP_AUTO_TEST_ROUNDS,
           scfde_equalizer_name(scfde_modem_get_equalizer()),
           g_error_percent);
    for(round=0u;round<APP_AUTO_TEST_ROUNDS;round++)
    {
        scfde_rx_result_t result;
        app_prepare_loopback(payload,(uint8_t)sizeof(payload),0x55u);
        app_inject_errors(g_loopback_samples,APP_LOOPBACK_LEN);
        result=app_decode_frame(g_loopback_samples,APP_LOOPBACK_LEN);
        if(result.sync_metric>=0.18f){sync_ok_count++;}
        if(result.valid!=0u)
        {
            crc_ok_count++;
            if((result.payload_length==(uint8_t)sizeof(payload))&&
               (memcmp(result.payload,payload,sizeof(payload))==0))
            {
                ok_count++;
                data_ok_count++;
            }
        }
        if(((round+1u)%50u)==0u)
        {
            printf("  round %u/%u: ok=%u\r\n",(unsigned int)(round+1u),
                   (unsigned int)APP_AUTO_TEST_ROUNDS,ok_count);
        }
    }
    printf("Auto test done: ok=%u/%u sync=%u crc=%u data_match=%u\r\n",
           ok_count,(unsigned int)APP_AUTO_TEST_ROUNDS,
           sync_ok_count,crc_ok_count,data_ok_count);
}

/* Burst TX: repeat the current frame N times with a gap (optionally with a
   PB0 sync pulse ahead of the burst). */
static void app_run_burst_tx(uint8_t use_sync_pulse)
{
    uint8_t payload[SCFDE_MAX_PAYLOAD];
    uint8_t length;
    uint16_t repeat;
    printf("Text (max %u bytes): ",SCFDE_MAX_PAYLOAD);
    length=app_read_line(payload,SCFDE_MAX_PAYLOAD);
    if(app_prepare_frame(payload,length,g_sequence)==0u){printf("TX packet rejected.\r\n");return;}
    printf("Burst TX: %u frames, %u ms gap%s\r\n",
           (unsigned int)APP_BURST_FRAME_COUNT,(unsigned int)APP_BURST_GAP_MS,
           use_sync_pulse!=0u?", PB0 sync pulse first":"");
    for(repeat=0u;repeat<APP_BURST_FRAME_COUNT;repeat++)
    {
        if(use_sync_pulse!=0u)
        {
            half_duplex_sync_pulse_start();
            delay_ms(15);
        }
        half_duplex_enter_tx();
        passband_tx_send_blocking(0,app_frame_tx_samples());
        half_duplex_enter_idle();
        if(((repeat+1u)%5u)==0u)
        {
            printf("  burst %u/%u\r\n",(unsigned int)(repeat+1u),
                   (unsigned int)APP_BURST_FRAME_COUNT);
        }
        if((repeat+1u)<APP_BURST_FRAME_COUNT){delay_ms(APP_BURST_GAP_MS);}
    }
    printf("Burst TX done (seq=%u).\r\n",g_sequence);
    g_sequence++;
}

/* RX window triggered by the PB1 sync line instead of signal energy. */
static void app_run_sync_line_rx(void)
{
    scfde_rx_result_t result;
    printf("RX armed: waiting PB1 sync pulse...\r\n");
    half_duplex_enter_rx();
    if(half_duplex_sync_wait_start_timeout(APP_RX_SIGNAL_TIMEOUT_MS)==0u)
    {
        half_duplex_enter_idle();
        printf("RX timeout: no sync pulse within %u ms.\r\n",APP_RX_SIGNAL_TIMEOUT_MS);
        return;
    }
    passband_rx_start_dma(SCFDE_RX_CAPTURE_LENGTH);
    passband_rx_wait_complete();
    half_duplex_enter_idle();
    printf("RX captured: %lu samples, decoding...\r\n",
           (unsigned long)passband_rx_get_captured_length());
    result=app_decode_frame(passband_rx_get_buffer(),passband_rx_get_captured_length());
    app_print_result(&result);
}

/* Wake tone + request burst (no PB0/PB1 sync line), then wait for reply. */
static void app_run_requester_no_sync(void)
{
    uint8_t data;
    uint8_t seq;
    uint8_t payload;
    uint8_t repeat;
    scfde_rx_result_t reply;
    printf("\r\n[Requester no-sync] wake tone %u ms, then request burst x%u.\r\n",
           (unsigned int)APP_NO_SYNC_WAKE_TONE_MS,
           (unsigned int)APP_NO_SYNC_REPLY_BURST);
    while(1)
    {
        uint8_t line[2];
        uint8_t length;
        printf("req byte (empty line returns)> ");
        length=app_read_line(line,1u);
        if(length==0u){break;}
        data=line[0];
        scfde_proto_make_request(data,&seq,&payload);
        printf("Wake + request 0x%02X...\r\n",data);
        half_duplex_enter_tx();
        passband_tx_send_blocking(g_wake_tone,sizeof(g_wake_tone));
        half_duplex_enter_idle();
        delay_ms(APP_NO_SYNC_WAKE_GAP_MS);
        for(repeat=0u;repeat<APP_NO_SYNC_REPLY_BURST;repeat++)
        {
            if(app_protocol_tx_frame(seq,&payload,1u)==0u){printf("TX reject.\r\n");break;}
            if((repeat+1u)<APP_NO_SYNC_REPLY_BURST){delay_ms(APP_PROTO_SLOT_BURST_GAP_MS);}
        }
        reply=app_protocol_rx_frame(APP_PROTO_REPLY_TIMEOUT_MS);
        if(reply.valid==0u)
        {
            printf("Reply timeout.\r\n");
        }
        else if(scfde_proto_is_reply(&reply)!=0u)
        {
            printf("Reply 0x%02X -> %s\r\n",reply.payload[0],
                   (reply.payload[0]==data)?"MATCH":"DATA MISMATCH");
        }
        else
        {
            printf("Unexpected frame (seq=0x%02X len=%u).\r\n",
                   reply.sequence,reply.payload_length);
        }
    }
}

/* Wake-tone listener: energy-detect the wake tone, then decode the request
   burst and answer with a reply burst. */
static void app_run_responder_no_sync(void)
{
    uint8_t seq;
    uint8_t payload;
    uint8_t repeat;
    printf("\r\n[Responder no-sync] listening on energy threshold...\r\n");
    while(1)
    {
        scfde_rx_result_t request;
        uint8_t exit_key;
        if(usart_try_get_byte(&exit_key)!=0u)
        {
            printf("(exit key received)\r\n");
            break;
        }
        request=app_protocol_rx_frame(APP_RX_SIGNAL_TIMEOUT_MS);
        if(request.valid==0u){printf("RX window timeout.\r\n");continue;}
        if(scfde_proto_is_request(&request)!=0u)
        {
            scfde_proto_make_reply(request.payload[0],&seq,&payload);
            printf("Request 0x%02X -> reply burst x%u\r\n",request.payload[0],
                   (unsigned int)APP_NO_SYNC_REPLY_BURST);
            for(repeat=0u;repeat<APP_NO_SYNC_REPLY_BURST;repeat++)
            {
                if(app_protocol_tx_frame(seq,&payload,1u)==0u){printf("TX reject.\r\n");break;}
                if((repeat+1u)<APP_NO_SYNC_REPLY_BURST){delay_ms(APP_PROTO_SLOT_BURST_GAP_MS);}
            }
        }
        else
        {
            printf("Ignored frame: seq=0x%02X len=%u%s\r\n",
                   request.sequence,request.payload_length,
                   scfde_proto_is_idle(&request)!=0u?" (idle)":"");
        }
    }
}


static void app_print_role_menu(app_role_t role)
{
    printf("\r\n[%s] equalizer=%s error=%u%%\r\n",app_role_name(role),
           scfde_equalizer_name(scfde_modem_get_equalizer()),g_error_percent);
    if((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_TRANSCEIVER)){printf("  1: transmit text\r\n");}
    if((role==APP_ROLE_RX_ONLY)||(role==APP_ROLE_TRANSCEIVER)){printf("  2: receive one frame\r\n");}
    if(role==APP_ROLE_DIAGNOSTIC){printf("  3: digital loopback with selected equalizer\r\n");}
    printf("  4: select next equalizer\r\n");
    if(role==APP_ROLE_DIAGNOSTIC){printf("  5: DAC-ADC analog self-loopback\r\n");}
    if(role==APP_ROLE_DIAGNOSTIC){printf("  6: %u-round auto test\r\n",(unsigned int)APP_AUTO_TEST_ROUNDS);}
    if(role==APP_ROLE_DIAGNOSTIC){printf("  7: set error injection percent\r\n");}
    if((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_TRANSCEIVER))
    {
        printf("  6: burst TX x%u\r\n",(unsigned int)APP_BURST_FRAME_COUNT);
        printf("  7: burst TX with PB0 sync pulse\r\n");
    }
    if((role==APP_ROLE_RX_ONLY)||(role==APP_ROLE_TRANSCEIVER))
    {
        printf("  6: receive with PB1 sync line trigger\r\n");
    }
    if(role==APP_ROLE_REQUESTER){printf("  1: request-reply round (one byte)\r\n");}
    if(role==APP_ROLE_RESPONDER){printf("  1: listen and echo replies\r\n");}
    if(role==APP_ROLE_SLOT_A){printf("  1: slot A round (burst + vote)\r\n");}
    if(role==APP_ROLE_SLOT_B){printf("  1: slot B round (vote + echo)\r\n");}
    if(role==APP_ROLE_REQUESTER_NO_SYNC){printf("  1: wake-tone request round\r\n");}
    if(role==APP_ROLE_RESPONDER_NO_SYNC){printf("  1: wake-tone listen + echo\r\n");}
    printf("  0: change node role\r\n");
    printf("cmd> ");
}

static uint8_t app_command_allowed(app_role_t role,uint8_t command)
{
    if(command=='0'){return 1u;}
    if((command=='4')||(command=='5')){return 1u;}
    if((command=='6')||(command=='7'))
    {
        if(role==APP_ROLE_DIAGNOSTIC){return 1u;}
        if((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_RX_ONLY)||
           (role==APP_ROLE_TRANSCEIVER)){return 1u;}
        return 0u;
    }
    if((command=='1')&&((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_TRANSCEIVER)||
        (role==APP_ROLE_REQUESTER)||(role==APP_ROLE_RESPONDER)||
        (role==APP_ROLE_SLOT_A)||(role==APP_ROLE_SLOT_B)||
        (role==APP_ROLE_REQUESTER_NO_SYNC)||(role==APP_ROLE_RESPONDER_NO_SYNC))){return 1u;}
    if((command=='2')&&((role==APP_ROLE_RX_ONLY)||(role==APP_ROLE_TRANSCEIVER))){return 1u;}
    if((command=='3')&&(role==APP_ROLE_DIAGNOSTIC)){return 1u;}
    return 0u;
}

void scfde_app_run(void)
{
    app_role_t role; app_print_banner(); role=app_select_role();
    app_wake_tone_init();
    while(1)
    {
        uint8_t command; app_print_role_menu(role); command=app_read_command();
        if(app_command_allowed(role,command)==0u){printf("Command is not available for this role.\r\n");continue;}
        if(command=='0'){role=app_select_role();}
        else if(command=='1')
        {
            switch(role)
            {
            case APP_ROLE_REQUESTER: app_run_requester(); break;
            case APP_ROLE_RESPONDER: app_run_responder(); break;
            case APP_ROLE_SLOT_A: app_run_slot_a(); break;
            case APP_ROLE_SLOT_B: app_run_slot_b(); break;
            case APP_ROLE_REQUESTER_NO_SYNC: app_run_requester_no_sync(); break;
            case APP_ROLE_RESPONDER_NO_SYNC: app_run_responder_no_sync(); break;
            default: app_transmit(); break;
            }
        }
        else if(command=='2'){app_receive();}
        else if(command=='3'){app_digital_loopback();}
        else if(command=='4'){app_select_equalizer();}
        else if(command=='5'){app_analog_loopback();}
        else if(command=='6')
        {
            if(role==APP_ROLE_DIAGNOSTIC){app_run_auto_test();}
            else if((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_TRANSCEIVER))
            {
                app_run_burst_tx(0u);
            }
            else if((role==APP_ROLE_RX_ONLY)||(role==APP_ROLE_TRANSCEIVER))
            {
                app_run_sync_line_rx();
            }
        }
        else if(command=='7')
        {
            if(role==APP_ROLE_DIAGNOSTIC){app_set_error_percent();}
            else if((role==APP_ROLE_TX_ONLY)||(role==APP_ROLE_TRANSCEIVER))
            {
                app_run_burst_tx(1u);
            }
        }
    }
}
