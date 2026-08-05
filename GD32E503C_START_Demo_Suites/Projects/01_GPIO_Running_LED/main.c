#include "main.h"
#include <stdio.h>

typedef enum
{
    MODEM_NODE_ROLE_SINGLE_BOARD = 0,
    MODEM_NODE_ROLE_TX_ONLY = 1,
    MODEM_NODE_ROLE_RX_ONLY = 2,
    MODEM_NODE_ROLE_REQUESTER = 3,
    MODEM_NODE_ROLE_RESPONDER = 4,
    MODEM_NODE_ROLE_REQUESTER_NO_SYNC = 5,
    MODEM_NODE_ROLE_RESPONDER_NO_SYNC = 6,
    MODEM_NODE_ROLE_SLOT_A = 7,
    MODEM_NODE_ROLE_SLOT_B = 8
} modem_node_role_t;


static modem_node_role_t g_node_role = MODEM_NODE_ROLE_SINGLE_BOARD;

static const char *get_node_role_name(modem_node_role_t role)
{
    switch(role)
    {
    case MODEM_NODE_ROLE_TX_ONLY:
        return "tx_only";

    case MODEM_NODE_ROLE_RX_ONLY:
        return "rx_only";
    case MODEM_NODE_ROLE_REQUESTER:
        return "requester";
    case MODEM_NODE_ROLE_RESPONDER:
        return "responder";
    case MODEM_NODE_ROLE_REQUESTER_NO_SYNC:
        return "requester_no_sync";
    case MODEM_NODE_ROLE_RESPONDER_NO_SYNC:
        return "responder_no_sync";
    case MODEM_NODE_ROLE_SLOT_A:
        return "slot_a";
    case MODEM_NODE_ROLE_SLOT_B:
        return "slot_b";
    case MODEM_NODE_ROLE_SINGLE_BOARD:
    default:
        return "single_board";
    }
}

static modem_node_role_t wait_node_role_select(void)
{
    uint8_t role_key;

    for(;;)
    {
        role_key = usart_get_byte();

        if((role_key == 0x0D) || (role_key == 0x0A))
        {
            continue;
        }

        if(role_key == '1')
        {
            return MODEM_NODE_ROLE_SINGLE_BOARD;
        }

        if(role_key == '2')
        {
            return MODEM_NODE_ROLE_TX_ONLY;
        }

        if(role_key == '3')
        {
            return MODEM_NODE_ROLE_RX_ONLY;
        }
        if(role_key == '4')
        {
            return MODEM_NODE_ROLE_REQUESTER;
        }

        if(role_key == '5')
        {
            return MODEM_NODE_ROLE_RESPONDER;
        }

        if(role_key == '6')
        {
            return MODEM_NODE_ROLE_REQUESTER_NO_SYNC;
        }

        if(role_key == '7')
        {
            return MODEM_NODE_ROLE_RESPONDER_NO_SYNC;
        }

        if(role_key == '8')
        {
            return MODEM_NODE_ROLE_SLOT_A;
        }

        if(role_key == '9')
        {
            return MODEM_NODE_ROLE_SLOT_B;
        }

        printf("Invalid role key: %c\r\n", role_key);
        printf("Please input 1, 2, 3, 4, 5, 6, 7, 8 or 9.\r\n");
    }
}
//==================== 閸忋劌鐪崣鍌涙殶 ====================
static app_mode_t g_app_mode = APP_MODE_WORK;
static uint8_t g_error_percent = 0;//閸ｎ亜锛愬В鏂剧伐閿涘牏鏁ゆ禍搴濆敩閻椒璞㈤惇鐕傜礆
static uint16_t g_sync_offset = 10;//閸氬本顒為崑蹇曅╅柌蹇ョ礄閻劋绨禒锝囩垳娴犺法婀￠敍?
#define REQUESTER_REPLY_SYNC_TIMEOUT_MS    2000u
#define REQUESTER_REPLY_SIGNAL_TIMEOUT_MS  4000u
#define SLOT_STATS_REPORT_INTERVAL         50u
#define SLOT_USER_REPEAT_COUNT             5u
#define SLOT_VOTE_MAJORITY_COUNT           ((SLOT_USER_REPEAT_COUNT / 2u) + 1u)
#define SLOT_USER_GAP_IDLE_COUNT           1u
#define SLOT_WAKE_TONE_MS                  10u
#define SLOT_SIGNAL_THRESHOLD              800u
#define SLOT_SIGNAL_STABLE                 3u
#define NO_SYNC_REQUEST_WAKE_TONE_MS       5u
#define NO_SYNC_REPLY_WAKE_TONE_MS         10u
#define NO_SYNC_WAKE_GAP_MS                10u
#define NO_SYNC_REQUEST_WAKE_AMPLITUDE     DSSS_TX_SAMPLE_AMPLITUDE
#define NO_SYNC_REPLY_WAKE_AMPLITUDE       1536
#define NO_SYNC_REPLY_DELAY_MS             0u
#define NO_SYNC_REPLY_BURST_COUNT          1u
#define NO_SYNC_REPLY_BURST_GAP_MS         100u
#define NO_SYNC_REPLY_CAPTURE_DELAY_MS     0u
#define NO_SYNC_REQUEST_SIGNAL_THRESHOLD   600u
#define NO_SYNC_REQUEST_SIGNAL_STABLE      2u
#define NO_SYNC_REPLY_SIGNAL_THRESHOLD     300u
#define NO_SYNC_REPLY_SIGNAL_STABLE        1u
#define NO_SYNC_TARGET_SEARCH_RADIUS       (4u * DSSS_RX_SAMPLES_PER_CHIP)
#define SLOT_WAKE_SAMPLE_COUNT             ((DSSS_TX_SAMPLE_RATE_HZ * SLOT_WAKE_TONE_MS) / 1000u)
#define NO_SYNC_REQUEST_WAKE_SAMPLE_COUNT  ((DSSS_TX_SAMPLE_RATE_HZ * NO_SYNC_REQUEST_WAKE_TONE_MS) / 1000u)
#define NO_SYNC_REPLY_WAKE_SAMPLE_COUNT    ((DSSS_TX_SAMPLE_RATE_HZ * NO_SYNC_REPLY_WAKE_TONE_MS) / 1000u)
#define NO_SYNC_WAKE_GAP_SAMPLE_COUNT      ((DSSS_TX_SAMPLE_RATE_HZ * NO_SYNC_WAKE_GAP_MS) / 1000u)
#define TX_SAMPLES_TO_RX_SAMPLES(count)    ((uint32_t)(((uint64_t)(count) * DSSS_RX_SAMPLE_RATE_HZ) / DSSS_TX_SAMPLE_RATE_HZ))

static int16_t g_no_sync_request_wake_samples[NO_SYNC_REQUEST_WAKE_SAMPLE_COUNT];
static int16_t g_no_sync_reply_wake_samples[NO_SYNC_REPLY_WAKE_SAMPLE_COUNT];
static int16_t g_no_sync_gap_samples[NO_SYNC_WAKE_GAP_SAMPLE_COUNT];

typedef enum
{
    NO_SYNC_RX_STATUS_TIMEOUT = 0,
    NO_SYNC_RX_STATUS_OK = 1,
    NO_SYNC_RX_STATUS_FRAME_ERROR = 2
} no_sync_rx_status_t;

typedef struct
{
    uint32_t tx_burst_frames;
    uint32_t tx_repeat_frames;
    uint32_t tx_idle_frames;
    uint32_t rx_ok_frames;
    uint32_t rx_timeout_frames;
    uint32_t rx_frame_error_frames;
    uint32_t rx_idle_frames;
    uint32_t rx_data_frames;
    uint32_t rx_confirmed_frames;
    uint32_t rx_vote_fail_frames;
    uint32_t next_report_at;
} slot_runtime_stats_t;

typedef struct
{
    uint8_t tx_data;
    uint8_t repeat_remaining;
    uint8_t idle_gap_remaining;
    uint8_t queued_data_valid;
    uint8_t queued_data;
    uint8_t burst_start_pending;
} slot_tx_repeat_state_t;

typedef struct
{
    uint8_t active;
    uint8_t slot_count;
    uint8_t valid_count;
    uint8_t samples[SLOT_USER_REPEAT_COUNT];
} slot_rx_vote_state_t;

typedef struct
{
    uint8_t finalized;
    uint8_t success;
    uint8_t rx_data;
} slot_rx_vote_result_t;

static slot_runtime_stats_t g_slot_a_stats;
static slot_runtime_stats_t g_slot_b_stats;
static slot_tx_repeat_state_t g_slot_a_tx_state;
static slot_tx_repeat_state_t g_slot_b_tx_state;
static slot_rx_vote_state_t g_slot_a_rx_vote_state;
static slot_rx_vote_state_t g_slot_b_rx_vote_state;

//==================== 閹垫挸宓冪挧宄邦潗娣団剝浼?====================
static void print_welcome(void)
{
    printf("==== GD32E503 DSSS Underwater Acoustic Modem V3 ====\r\n");
    printf("Input 1 byte from USART, modem packs [LEN][DATA][CHK].\r\n");
    printf("Analog TX path: DAC_OUT0 (PA4), TIMER6 sample drive.\r\n");
    printf("Analog RX path: ADC0_IN0 (PA0), TIMER2 TRGO, DMA0 CH0.\r\n");
    printf("Sync trigger path: TX PB0 -> RX PB1 (used by roles 2/3/4/5).\r\n");
    printf("Half duplex state machine: %s\r\n", half_duplex_control_is_enabled() != 0u ? "GPIO control enabled" : "logic only");
    printf("Half duplex guards: RX->TX %u ms, TX->RX %u ms.\r\n",
           half_duplex_get_rx_to_tx_guard_ms(),
           half_duplex_get_tx_to_rx_guard_ms());
    printf("Role select: 1=single-board  2=tx-only  3=rx-only  4=requester  5=responder  6=requester-nosync  7=responder-nosync  8=slot-a  9=slot-b\r\n");
}
//==================== 閹垫挸宓冨銉ュ徔閿涘奔绱崠鏍ㄥⅵ閸楁澘鐡ч懞鍌氭姎 ====================
static void print_frame_bytes(const char *title, const uint8_t *frame_bytes, uint16_t frame_len)
{
    uint16_t i;

    printf("%s", title);
    for(i = 0; i < frame_len; i++)
    {
        printf("%02X ", frame_bytes[i]);
    }
    printf("\r\n");
}

static uint8_t frame_bytes_is_idle(const uint8_t *frame_bytes)
{
    if(frame_bytes == 0)
    {
        return 0u;
    }

    return (frame_bytes[DSSS_FRAME_LEN_INDEX] == DSSS_FRAME_IDLE_LENGTH) ? 1u : 0u;
}

static uint8_t real_result_is_idle_frame(const real_rx_result_t *result)
{
    if(result == 0)
    {
        return 0u;
    }

    if((result->valid == 0u) || (result->checksum_ok == 0u))
    {
        return 0u;
    }

    return frame_bytes_is_idle(result->rx_frame_bytes);
}

static uint8_t poll_pending_usart_data(uint8_t *byte_out)
{
    uint8_t rx_byte;
    uint8_t has_data;

    if(byte_out == 0)
    {
        return 0u;
    }

    has_data = 0u;

    while(usart_try_get_byte(&rx_byte) != 0u)
    {
        if((rx_byte == 0x0D) || (rx_byte == 0x0A))
        {
            continue;
        }

        *byte_out = rx_byte;
        has_data = 1u;
    }

    return has_data;
}

static uint8_t slot_get_next_tx_data(slot_tx_repeat_state_t *state,
                                     uint8_t *tx_data_out,
                                     uint8_t *burst_start_out)
{
    uint8_t latest_byte;

    if((state == 0) || (tx_data_out == 0))
    {
        return 0u;
    }

    if(burst_start_out != 0)
    {
        *burst_start_out = 0u;
    }

    latest_byte = 0u;
    if(poll_pending_usart_data(&latest_byte) != 0u)
    {
        if((state->repeat_remaining == 0u) &&
           (state->idle_gap_remaining == 0u))
        {
            state->tx_data = latest_byte;
            state->repeat_remaining = SLOT_USER_REPEAT_COUNT;
            state->burst_start_pending = 1u;
        }
        else
        {
            state->queued_data = latest_byte;
            state->queued_data_valid = 1u;
        }
    }

    if(state->repeat_remaining > 0u)
    {
        *tx_data_out = state->tx_data;
        state->repeat_remaining--;
        if(burst_start_out != 0)
        {
            *burst_start_out = state->burst_start_pending;
        }
        state->burst_start_pending = 0u;

        if(state->repeat_remaining == 0u)
        {
            state->idle_gap_remaining = SLOT_USER_GAP_IDLE_COUNT;
        }

        return 1u;
    }

    if(state->idle_gap_remaining > 0u)
    {
        state->idle_gap_remaining--;

        if((state->idle_gap_remaining == 0u) &&
           (state->queued_data_valid != 0u))
        {
            state->tx_data = state->queued_data;
            state->repeat_remaining = SLOT_USER_REPEAT_COUNT;
            state->queued_data_valid = 0u;
            state->burst_start_pending = 1u;
        }

        *tx_data_out = 0u;
        return 0u;
    }

    if(state->queued_data_valid != 0u)
    {
        state->tx_data = state->queued_data;
        state->repeat_remaining = SLOT_USER_REPEAT_COUNT;
        state->queued_data_valid = 0u;
        state->burst_start_pending = 1u;

        *tx_data_out = state->tx_data;
        state->repeat_remaining--;
        if(burst_start_out != 0)
        {
            *burst_start_out = state->burst_start_pending;
        }
        state->burst_start_pending = 0u;

        if(state->repeat_remaining == 0u)
        {
            state->idle_gap_remaining = SLOT_USER_GAP_IDLE_COUNT;
        }

        return 1u;
    }

    *tx_data_out = 0u;
    return 0u;
}

static void slot_rx_vote_reset(slot_rx_vote_state_t *state)
{
    uint8_t index;

    if(state == 0)
    {
        return;
    }

    state->active = 0u;
    state->slot_count = 0u;
    state->valid_count = 0u;
    for(index = 0u; index < SLOT_USER_REPEAT_COUNT; index++)
    {
        state->samples[index] = 0u;
    }
}

static uint8_t slot_pick_majority_byte(const slot_rx_vote_state_t *state, uint8_t *rx_data_out)
{
    uint8_t i;
    uint8_t j;

    if((state == 0) || (rx_data_out == 0))
    {
        return 0u;
    }

    for(i = 0u; i < state->valid_count; i++)
    {
        uint8_t match_count;

        match_count = 0u;
        for(j = 0u; j < state->valid_count; j++)
        {
            if(state->samples[j] == state->samples[i])
            {
                match_count++;
            }
        }

        if(match_count >= SLOT_VOTE_MAJORITY_COUNT)
        {
            *rx_data_out = state->samples[i];
            return 1u;
        }
    }

    return 0u;
}

static void slot_finalize_rx_vote(slot_rx_vote_state_t *state, slot_rx_vote_result_t *result)
{
    if((state == 0) || (result == 0))
    {
        return;
    }

    result->finalized = 1u;
    result->success = slot_pick_majority_byte(state, &result->rx_data);
    slot_rx_vote_reset(state);
}

static void slot_rx_vote_consume(slot_rx_vote_state_t *state,
                                 no_sync_rx_status_t rx_status,
                                 uint8_t rx_is_idle,
                                 uint8_t rx_data,
                                 slot_rx_vote_result_t *result)
{
    if(result == 0)
    {
        return;
    }

    result->finalized = 0u;
    result->success = 0u;
    result->rx_data = 0u;

    if(state == 0)
    {
        return;
    }

    if(state->active == 0u)
    {
        if((rx_status == NO_SYNC_RX_STATUS_OK) && (rx_is_idle == 0u))
        {
            state->active = 1u;
            state->slot_count = 1u;
            state->valid_count = 1u;
            state->samples[0] = rx_data;

            if(SLOT_USER_REPEAT_COUNT <= 1u)
            {
                slot_finalize_rx_vote(state, result);
            }
        }

        return;
    }

    if((rx_status == NO_SYNC_RX_STATUS_OK) && (rx_is_idle == 0u))
    {
        if(state->valid_count < SLOT_USER_REPEAT_COUNT)
        {
            state->samples[state->valid_count] = rx_data;
            state->valid_count++;
        }

        if(state->slot_count < SLOT_USER_REPEAT_COUNT)
        {
            state->slot_count++;
        }
    }
    else if((rx_status == NO_SYNC_RX_STATUS_OK) && (rx_is_idle != 0u))
    {
        slot_finalize_rx_vote(state, result);
        return;
    }
    else
    {
        if(state->slot_count < SLOT_USER_REPEAT_COUNT)
        {
            state->slot_count++;
        }
    }

    if(state->slot_count >= SLOT_USER_REPEAT_COUNT)
    {
        slot_finalize_rx_vote(state, result);
    }
}

static uint8_t should_print_slot_summary(uint8_t tx_burst_start,
                                         const slot_rx_vote_result_t *vote_result)
{
    if(tx_burst_start != 0u)
    {
        return 1u;
    }

    if((vote_result != 0) && (vote_result->finalized != 0u))
    {
        return 1u;
    }

    return 0u;
}

static void print_slot_summary(const char *slot_name,
                               uint8_t tx_burst_start,
                               uint8_t tx_data,
                               const slot_rx_vote_result_t *vote_result)
{
    printf("%s", slot_name);

    if(tx_burst_start != 0u)
    {
        printf(" tx=0x%02X", tx_data);
    }

    if((vote_result != 0) && (vote_result->finalized != 0u))
    {
        if(vote_result->success != 0u)
        {
            printf(" rx=0x%02X vote-OK", vote_result->rx_data);
        }
        else
        {
            printf(" rx=vote-fail");
        }
    }

    printf("\r\n");
}

static void slot_stats_record_tx(slot_runtime_stats_t *stats,
                                 uint8_t has_pending_tx_data,
                                 uint8_t burst_start)
{
    if(stats == 0)
    {
        return;
    }

    if(burst_start != 0u)
    {
        stats->tx_burst_frames++;
    }

    if(has_pending_tx_data != 0u)
    {
        stats->tx_repeat_frames++;
    }
    else
    {
        stats->tx_idle_frames++;
    }
}

static void slot_stats_record_rx(slot_runtime_stats_t *stats,
                                 no_sync_rx_status_t rx_status,
                                 uint8_t rx_is_idle)
{
    if(stats == 0)
    {
        return;
    }

    if(rx_status == NO_SYNC_RX_STATUS_OK)
    {
        stats->rx_ok_frames++;

        if(rx_is_idle != 0u)
        {
            stats->rx_idle_frames++;
        }
        else
        {
            stats->rx_data_frames++;
        }
    }
    else if(rx_status == NO_SYNC_RX_STATUS_FRAME_ERROR)
    {
        stats->rx_frame_error_frames++;
    }
    else
    {
        stats->rx_timeout_frames++;
    }
}

static void slot_stats_record_rx_vote(slot_runtime_stats_t *stats,
                                      const slot_rx_vote_result_t *vote_result)
{
    if((stats == 0) || (vote_result == 0) || (vote_result->finalized == 0u))
    {
        return;
    }

    if(vote_result->success != 0u)
    {
        stats->rx_confirmed_frames++;
    }
    else
    {
        stats->rx_vote_fail_frames++;
    }
}

static uint32_t slot_stats_get_rx_total(const slot_runtime_stats_t *stats)
{
    if(stats == 0)
    {
        return 0u;
    }

    return stats->rx_ok_frames +
           stats->rx_timeout_frames +
           stats->rx_frame_error_frames;
}

static void print_slot_stats(const char *slot_name, const slot_runtime_stats_t *stats)
{
    if(stats == 0)
    {
        return;
    }

    printf("%s stats: tx_burst=%lu tx_repeat=%lu tx_idle=%lu rx_ok=%lu rx_timeout=%lu rx_frame_error=%lu rx_idle=%lu rx_data=%lu rx_confirmed=%lu rx_vote_fail=%lu\r\n",
           slot_name,
           (unsigned long)stats->tx_burst_frames,
           (unsigned long)stats->tx_repeat_frames,
           (unsigned long)stats->tx_idle_frames,
           (unsigned long)stats->rx_ok_frames,
           (unsigned long)stats->rx_timeout_frames,
           (unsigned long)stats->rx_frame_error_frames,
           (unsigned long)stats->rx_idle_frames,
           (unsigned long)stats->rx_data_frames,
           (unsigned long)stats->rx_confirmed_frames,
           (unsigned long)stats->rx_vote_fail_frames);
}

static void maybe_print_slot_stats(const char *slot_name, slot_runtime_stats_t *stats)
{
    uint32_t rx_total;

    if(stats == 0)
    {
        return;
    }

    if(stats->next_report_at == 0u)
    {
        stats->next_report_at = SLOT_STATS_REPORT_INTERVAL;
    }

    rx_total = slot_stats_get_rx_total(stats);
    if(rx_total < stats->next_report_at)
    {
        return;
    }

    print_slot_stats(slot_name, stats);
    stats->next_report_at += SLOT_STATS_REPORT_INTERVAL;
}

static uint8_t is_slot_role(modem_node_role_t role)
{
    if((role == MODEM_NODE_ROLE_SLOT_A) || (role == MODEM_NODE_ROLE_SLOT_B))
    {
        return 1u;
    }

    return 0u;
}

static int16_t get_wake_carrier_sample(uint32_t index, int16_t amplitude)
{
    int16_t diagonal_amplitude;

    diagonal_amplitude = (int16_t)(((int32_t)amplitude * 181) / 256);

    switch(index % DSSS_TX_SAMPLES_PER_CYCLE)
    {
    case 0u:
        return amplitude;

    case 1u:
        return diagonal_amplitude;

    case 2u:
    case 6u:
        return 0;

    case 3u:
    case 5u:
        return (int16_t)-diagonal_amplitude;

    case 4u:
        return (int16_t)-amplitude;

    case 7u:
    default:
        return diagonal_amplitude;
    }
}

static void init_no_sync_waveform_buffers(void)
{
    uint32_t index;

    for(index = 0u; index < NO_SYNC_REQUEST_WAKE_SAMPLE_COUNT; index++)
    {
        g_no_sync_request_wake_samples[index] =
            get_wake_carrier_sample(index, NO_SYNC_REQUEST_WAKE_AMPLITUDE);
    }

    for(index = 0u; index < NO_SYNC_REPLY_WAKE_SAMPLE_COUNT; index++)
    {
        g_no_sync_reply_wake_samples[index] =
            get_wake_carrier_sample(index, NO_SYNC_REPLY_WAKE_AMPLITUDE);
    }

    for(index = 0u; index < NO_SYNC_WAKE_GAP_SAMPLE_COUNT; index++)
    {
        g_no_sync_gap_samples[index] = 0;
    }
}
//====================  ====================
static void print_frame_info(uint8_t tx_data)
{
    char tx_preview[17];
    uint8_t tx_frame_bytes[DSSS_FRAME_BYTE_COUNT];
    uint32_t i;

    dsss_modem_prepare_tx_samples(tx_data);//鐏忓棜绶崗銉ョ摟閼哄倹澧﹂崠鍛娑?娴ｅ秴澧犵€佃偐鐖?
    dsss_modem_get_tx_frame_bytes(tx_frame_bytes, DSSS_FRAME_BYTE_COUNT);
    dsss_modem_get_tx_preview(tx_preview, sizeof(tx_preview));

	  printf("Input data byte: 0x%02X\r\n", tx_data);//鏉堟挸鍙嗙€涙濡?
    printf("RX mode: %s\r\n", dsss_modem_get_rx_mode() == RX_MODE_SIMULATION ? "simulation" : "real");//RX濡€崇础閿涘澃imulation鏉╂ɑ妲竢eal閿?
    printf("APP mode: %s\r\n", g_app_mode == APP_MODE_TEST ? "test" : "work");//APP濡€崇础閿涘澅est or work)
    printf("Half duplex state: %s\r\n", half_duplex_get_state_name(half_duplex_get_state()));//閸楀﹤寮诲銉ョ秼閸撳秶濮搁幀?
    printf("Noise setting: %d%%\r\n", g_error_percent);//娴犺法婀℃穱鈥虫珨濮?
    printf("Frame bytes: %u\r\n", dsss_modem_get_frame_byte_count());//鐢冪摟閼哄倹鏆熼崪灞芥姎chip闂€鍨 鐢?鐎涙濡?閸撳秴顕遍惍?bit 閸?2bit閿涘本鐦it閹碘晛鍩?1chip閿涘本鈧鏆?92chip
    printf("Frame length: %d chips\r\n", dsss_modem_get_frame_length());//闁艾鐢弽椋庡仯閹粯鏆?48kHz 闁插洦鐗遍悳?1k chip/s閿涘本鐦?chip 48 娑擃亝鐗遍悙鐧哥礉閹粯鐗遍悙?992 * 48 = 47616
    printf("Passband sample length: %lu\r\n", (unsigned long)dsss_modem_get_tx_sample_length());//閸欐垿鈧礁鎶氱€涙濡崘鍛啇閵嗕恭hip 妫板嫯顫嶉妴浣稿閸戠姳閲滈柅姘敨閺嶉鍋?
    printf("Carrier/TX sample/RX sample/chip: %u Hz / %u Hz / %u Hz / %u chip/s\r\n",
           DSSS_CARRIER_FREQ_HZ,
           DSSS_TX_SAMPLE_RATE_HZ,
           DSSS_RX_SAMPLE_RATE_HZ,
           DSSS_CHIP_RATE_HZ);
    print_frame_bytes("TX frame bytes: ", tx_frame_bytes, dsss_modem_get_frame_byte_count());
    printf("TX preview: %s\r\n", tx_preview);
    printf("TX sample preview: ");
    for(i = 0; (i < 8u) && (i < dsss_modem_get_tx_sample_length()); i++)
    {
        printf("%d ", dsss_modem_get_tx_sample(i));
    }
    printf("\r\n");
}

//==================== 鏉╂稑鍙嗙紒鐔活吀濞村鐦Ο鈥崇础閿涘牆婀拋鍓х枂婵傜晫娈戦崳顏勶紣濮ｆ柧绗屾担宥囆╅柌蹇庣瑓鏉╂稖顢?00濞嗏€茶雹閻噦绱?====================
static void run_test_mode(uint8_t tx_data)
{
    test_result_t result;

    result = dsss_modem_run_test(tx_data, g_error_percent, g_sync_offset);

    printf("Frame test result: %d / %d\r\n", result.ok_count, TEST_ROUNDS);//鐢勭ゴ鐠囨洜绮ㄩ弸?
    printf("Sync offset set: %d\r\n", g_sync_offset);//鐠佸墽鐤嗛崥灞绢劄閸嬪繒些闁?
    printf("Best offset: %d\r\n", result.last_best_offset);//閺堚偓娴ｅ啿浜哥粔濠氬櫤
    printf("Sync success: %d / %d\r\n", result.sync_ok_count, TEST_ROUNDS);//閸氬本顒為幋鎰閹懎鍠?
    printf("Data success with correct sync: %d / %d\r\n", result.data_ok_when_sync_ok, result.sync_ok_count);//閸氬本顒炲锝団€樻稉鏃€鏆熼幑顔界墡妤犲本鍨氶崝鐔稿剰閸?
}
//==================== 閻喎鐤勯悳顖氭礀缂佺喕顓稿ù瀣槸 ====================
static void run_real_test_mode(uint8_t tx_data)
{
    uint16_t round;
    uint16_t sync_ok_count;
    uint16_t data_ok_count;
    uint16_t checksum_ok_count;
    uint8_t last_rx_byte;
    uint8_t last_checksum_ok;
    uint8_t last_rx_frame_bytes[DSSS_FRAME_BYTE_COUNT];
    uint32_t last_best_start;
    int32_t last_preamble_score;
    real_rx_result_t real_result;

    sync_ok_count = 0u;
    data_ok_count = 0u;
    checksum_ok_count = 0u;
    last_rx_byte = 0u;
    last_checksum_ok = 0u;
    last_best_start = 0u;
    last_preamble_score = 0;

    for(round = 0; round < DSSS_FRAME_BYTE_COUNT; round++)
    {
        last_rx_frame_bytes[round] = 0u;
    }

    dsss_modem_prepare_tx_samples(tx_data);

    printf("Real loopback test start: %u rounds\r\n", TEST_ROUNDS);

    for(round = 0; round < TEST_ROUNDS; round++)
    {
        uint16_t frame_index;

        passband_rx_start_dma(PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
        half_duplex_enter_tx();
        passband_tx_send_blocking(dsss_modem_get_tx_sample_buffer(),
                                  dsss_modem_get_tx_sample_length());
        half_duplex_enter_rx();
        passband_rx_wait_complete();

        real_result = dsss_modem_decode_real_samples(passband_rx_get_buffer(),
                                                     passband_rx_get_captured_length());

        if(real_result.valid != 0u)
        {
            sync_ok_count++;
            last_rx_byte = real_result.rx_data;
            last_checksum_ok = real_result.checksum_ok;
            last_best_start = real_result.best_start_index;
            last_preamble_score = real_result.best_preamble_score;

            for(frame_index = 0; frame_index < DSSS_FRAME_BYTE_COUNT; frame_index++)
            {
                last_rx_frame_bytes[frame_index] = real_result.rx_frame_bytes[frame_index];
            }

            if(real_result.checksum_ok != 0u)
            {
                checksum_ok_count++;
            }

            if((real_result.checksum_ok != 0u) && (real_result.rx_data == tx_data))
            {
                data_ok_count++;
            }
        }

        if(((round + 1u) % 20u) == 0u)
        {
            printf("Progress: %u / %u\r\n", round + 1u, TEST_ROUNDS);
        }

        delay_ms(5);
    }

    printf("Real frame test result: %u / %u\r\n", data_ok_count, TEST_ROUNDS);//鐎圭偤妾敮褎绁寸拠鏇犵波閺?
    printf("Real sync success: %u / %u\r\n", sync_ok_count, TEST_ROUNDS);//鐎圭偤妾崥灞绢劄閹存劕濮涚紒鎾寸亯
    printf("Real checksum success: %u / %u\r\n", checksum_ok_count, TEST_ROUNDS);//鐎圭偤妾弽锟犵崣閹存劕濮涚紒鎾寸亯
    print_frame_bytes("Last RX frame bytes: ", last_rx_frame_bytes, DSSS_FRAME_BYTE_COUNT);//閺堚偓缂佸牊甯撮弨璺烘姎鐎涙濡弫?
    printf("Last RX data byte: 0x%02X\r\n", last_rx_byte);//閺堚偓缂佸牊甯撮弨鑸垫殶閹?
    printf("Last checksum: %s\r\n", last_checksum_ok != 0u ? "OK" : "FAIL");//閺堚偓缂佸牊鐗庢灞芥嫲
    printf("Last best start index: %lu\r\n", (unsigned long)last_best_start);
    printf("Last preamble score: %ld\r\n", (long)last_preamble_score);
    half_duplex_enter_idle();
}
//==================== 瀹搞儰缍斿Ο鈥崇础 ====================
static void run_work_mode(uint8_t tx_data)
{
    frame_rx_result_t sim_result;
    uint32_t i;
    uint16_t rx_min;
    uint16_t rx_max;
    real_rx_result_t real_result;
//==================== 閻喎浼愭担婊勀佸蹇ョ礄閸氼垰濮╂稉鈧▎锛勬埂鐎圭偤鍣伴弽鍑ょ礉鐎瑰本鍨氭稉鈧▎锛勬埂鐎圭偛褰傜亸鍕剁礉閸愬秴顕瓵DC闁插洦鐗遍崑姘承掗惍渚婄礆 ====================
    if(dsss_modem_get_rx_mode() == RX_MODE_REAL)
    {
        printf("RX capture length: %lu samples\r\n", (unsigned long)PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);//閹恒儲鏁规穱鈥冲娇閹规洝骞忛梹鍨
        printf("Start RX+TX now...\r\n");
        passband_rx_start_dma(PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
        half_duplex_enter_tx();
        passband_tx_send_blocking(dsss_modem_get_tx_sample_buffer(), dsss_modem_get_tx_sample_length());
        half_duplex_enter_rx();
        passband_rx_wait_complete();
        printf("TX passband blocking send done.\r\n");
        printf("RX passband capture done.\r\n");
        rx_min = 4095u;
        rx_max = 0u;
        for(i = 0; i < passband_rx_get_captured_length(); i++)
        {
            uint16_t sample;

            sample = passband_rx_get_sample(i);
            if(sample < rx_min)
            {
                rx_min = sample;
            }
            if(sample > rx_max)
            {
                rx_max = sample;
            }
        }
        printf("RX sample min/max: %u / %u\r\n", rx_min, rx_max);
        real_result = dsss_modem_decode_real_samples(passband_rx_get_buffer(), passband_rx_get_captured_length());
        if(real_result.valid != 0u)
        {
            printf("RX active start index: %lu\r\n", (unsigned long)real_result.active_start_index);
            printf("RX best start index: %lu\r\n", (unsigned long)real_result.best_start_index);
            printf("RX preamble score: %ld\r\n", (long)real_result.best_preamble_score);
            printf("RX active preview: ");
            for(i = real_result.best_start_index;
                (i < real_result.best_start_index + 32u) && (i < passband_rx_get_captured_length());
                i++)
            {
                printf("%u ", passband_rx_get_sample(i));
            }
            printf("\r\n");
            print_frame_bytes("RX frame bytes: ", real_result.rx_frame_bytes, DSSS_FRAME_BYTE_COUNT);
            printf("RX data byte: 0x%02X\r\n", real_result.rx_data);
            printf("Checksum: %s\r\n", real_result.checksum_ok != 0u ? "OK" : "FAIL");
        }
        else
        {
            printf("RX active start index: not found\r\n");
        }

        printf("RX sample preview: ");
        for(i = 0; (i < 16u) && (i < passband_rx_get_captured_length()); i++)
        {
            printf("%u ", passband_rx_get_sample(i));
        }
        printf("\r\n");
        half_duplex_enter_idle();
        return;
    }

    printf("TX passband blocking send start...\r\n");
    half_duplex_enter_tx();
    passband_tx_send_blocking(dsss_modem_get_tx_sample_buffer(), dsss_modem_get_tx_sample_length());
    half_duplex_enter_rx();
    printf("TX passband blocking send done.\r\n");

    sim_result = dsss_modem_run_work_once(tx_data, g_error_percent, g_sync_offset);
    print_frame_bytes("RX frame bytes: ", sim_result.rx_frame_bytes, DSSS_FRAME_BYTE_COUNT);
    printf("RX data byte: 0x%02X\r\n", sim_result.rx_data);
    printf("Checksum: %s\r\n", sim_result.checksum_ok != 0u ? "OK" : "FAIL");
    printf("Best offset: %d\r\n", sim_result.best_offset);
    half_duplex_enter_idle();
}

static void send_one_frame_once(uint8_t tx_data)
{
    dsss_modem_set_random_seed((uint32_t)tx_data + 1u);
    dsss_modem_prepare_tx_samples(tx_data);

    half_duplex_sync_pulse_start();
    delay_ms(15);

    half_duplex_enter_tx();
    passband_tx_send_blocking(dsss_modem_get_tx_sample_buffer(),
                              dsss_modem_get_tx_sample_length());
    half_duplex_enter_idle();
}

static void send_one_frame_once_no_sync(const int16_t *wake_samples,
                                        uint32_t wake_sample_count,
                                        uint32_t gap_sample_count,
                                        uint8_t tx_data)
{
    dsss_modem_set_random_seed((uint32_t)tx_data + 1u);
    dsss_modem_prepare_tx_samples(tx_data);

    half_duplex_enter_tx();
    passband_tx_send_blocking(wake_samples, wake_sample_count);
    passband_tx_send_blocking(g_no_sync_gap_samples, gap_sample_count);
    passband_tx_send_blocking(dsss_modem_get_tx_sample_buffer(),
                              dsss_modem_get_tx_sample_length());
    half_duplex_enter_idle();
}

static void send_one_idle_frame_once_no_sync(const int16_t *wake_samples,
                                             uint32_t wake_sample_count,
                                             uint32_t gap_sample_count)
{
    dsss_modem_set_random_seed(1u);
    dsss_modem_prepare_idle_tx_samples();

    half_duplex_enter_tx();
    passband_tx_send_blocking(wake_samples, wake_sample_count);
    passband_tx_send_blocking(g_no_sync_gap_samples, gap_sample_count);
    passband_tx_send_blocking(dsss_modem_get_tx_sample_buffer(),
                              dsss_modem_get_tx_sample_length());
    half_duplex_enter_idle();
}

static void send_one_frame_once_no_sync_burst(const int16_t *wake_samples,
                                              uint32_t wake_sample_count,
                                              uint32_t gap_sample_count,
                                              uint8_t tx_data,
                                              uint8_t burst_count,
                                              uint32_t gap_ms,
                                              const char *prefix)
{
    uint8_t burst_index;

    for(burst_index = 0u; burst_index < burst_count; burst_index++)
    {
        if(prefix != 0)
        {
            printf("%s%u / %u\r\n",
                   prefix,
                   (unsigned int)(burst_index + 1u),
                   (unsigned int)burst_count);
        }

        send_one_frame_once_no_sync(wake_samples,
                                    wake_sample_count,
                                    gap_sample_count,
                                    tx_data);

        if(((burst_index + 1u) < burst_count) && (gap_ms > 0u))
        {
            delay_ms(gap_ms);
        }
    }
}

static uint8_t receive_one_frame_once(real_rx_result_t *result, uint32_t sync_timeout_ms)
{
    if(result == 0)
    {
        return 0u;
    }

    printf("\r\n[RX Window]\r\n");
    printf("Node role: %s\r\n", get_node_role_name(g_node_role));
    printf("Waiting sync pulse on PB1...\r\n");

    if(sync_timeout_ms == 0u)
    {
        half_duplex_sync_wait_start();
    }
    else
    {
        if(half_duplex_sync_wait_start_timeout(sync_timeout_ms) == 0u)
        {
            printf("Reply sync timeout: %lu ms\r\n", (unsigned long)sync_timeout_ms);
            half_duplex_enter_idle();
            return 0u;
        }
    }

    passband_rx_start_dma(PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
    half_duplex_enter_rx();
    passband_rx_wait_complete();

    printf("Sync pulse detected.\r\n");
    printf("RX capture length: %lu samples\r\n", (unsigned long)PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
    printf("RX passband capture done.\r\n");

    *result = dsss_modem_decode_real_samples(passband_rx_get_buffer(),
                                             passband_rx_get_captured_length());

    if(result->valid != 0u)
    {
        printf("RX active start index: %lu\r\n", (unsigned long)result->active_start_index);
        printf("RX best start index: %lu\r\n", (unsigned long)result->best_start_index);
        printf("RX preamble score: %ld\r\n", (long)result->best_preamble_score);
        print_frame_bytes("RX frame bytes: ", result->rx_frame_bytes, DSSS_FRAME_BYTE_COUNT);
        printf("RX data byte: 0x%02X\r\n", result->rx_data);
        printf("Checksum: %s\r\n", result->checksum_ok != 0u ? "OK" : "FAIL");
    }
    else
    {
        printf("No valid frame found.\r\n");
    }

    half_duplex_enter_idle();

    if((result->valid != 0u) && (result->checksum_ok != 0u))
    {
        return 1u;
    }

    return 0u;
}

static uint8_t decode_real_samples_no_sync_search(real_rx_result_t *result,
                                                  uint32_t preroll_count,
                                                  uint32_t wake_sample_count,
                                                  uint32_t *search_begin_out,
                                                  uint32_t *expected_start_out)
{
    const uint16_t *rx_buffer;
    uint32_t captured_length;
    uint32_t max_offset;
    uint32_t search_begin;
    uint32_t search_end;

    if((result == 0) || (search_begin_out == 0) || (expected_start_out == 0))
    {
        return 0u;
    }

    rx_buffer = passband_rx_get_buffer();
    captured_length = passband_rx_get_captured_length();

    result->valid = 0u;
    result->checksum_ok = 0u;
    result->rx_data = 0u;
    result->active_start_index = 0u;
    result->best_start_index = 0u;
    result->best_preamble_score = 0;
    *search_begin_out = 0u;
    *expected_start_out = 0u;

    if((rx_buffer == 0) || (captured_length < DSSS_RX_FRAME_SAMPLE_COUNT))
    {
        return 0u;
    }

    max_offset = captured_length - DSSS_RX_FRAME_SAMPLE_COUNT;
    *expected_start_out = preroll_count +
                          TX_SAMPLES_TO_RX_SAMPLES(wake_sample_count) +
                          TX_SAMPLES_TO_RX_SAMPLES(NO_SYNC_WAKE_GAP_SAMPLE_COUNT);
    if(*expected_start_out > max_offset)
    {
        *expected_start_out = max_offset;
    }

    if(*expected_start_out > NO_SYNC_TARGET_SEARCH_RADIUS)
    {
        search_begin = *expected_start_out - NO_SYNC_TARGET_SEARCH_RADIUS;
    }
    else
    {
        search_begin = 0u;
    }

    search_end = *expected_start_out + NO_SYNC_TARGET_SEARCH_RADIUS;
    if(search_end > max_offset)
    {
        search_end = max_offset;
    }

    *search_begin_out = search_begin;
    *result = dsss_modem_decode_real_samples_in_window(rx_buffer,
                                                       captured_length,
                                                       search_begin,
                                                       search_end);

    if(result->valid == 0u)
    {
        return 0u;
    }

    return (result->checksum_ok != 0u) ? 1u : 0u;
}

static uint8_t receive_one_frame_no_sync(real_rx_result_t *result,
                                         uint32_t signal_timeout_ms,
                                         uint8_t verbose,
                                         no_sync_rx_status_t *status_out)
{
    uint32_t i;
    uint32_t decode_offset;
    uint32_t expected_start;
    uint32_t preroll_count;
    uint32_t wake_sample_count;
    uint16_t rx_min;
    uint16_t rx_max;

    if(result == 0)
    {
        return 0u;
    }

    result->valid = 0u;
    result->checksum_ok = 0u;
    result->rx_data = 0u;

    if(status_out != 0)
    {
        *status_out = NO_SYNC_RX_STATUS_FRAME_ERROR;
    }

    if(verbose != 0u)
    {
        printf("\r\n[RX Window]\r\n");
        printf("Node role: %s\r\n", get_node_role_name(g_node_role));
        printf("Waiting signal on PA0...\r\n");
    }

    if(is_slot_role(g_node_role) != 0u)
    {
        wake_sample_count = SLOT_WAKE_SAMPLE_COUNT;
        passband_rx_set_signal_wait_profile(SLOT_SIGNAL_THRESHOLD,
                                            SLOT_SIGNAL_STABLE);
        if(verbose != 0u)
        {
            printf("Signal wait profile: threshold=%u stable=%u\r\n",
                   (unsigned int)SLOT_SIGNAL_THRESHOLD,
                   (unsigned int)SLOT_SIGNAL_STABLE);
        }
    }
    else if((g_node_role == MODEM_NODE_ROLE_REQUESTER_NO_SYNC) && (signal_timeout_ms != 0u))
    {
        wake_sample_count = NO_SYNC_REPLY_WAKE_SAMPLE_COUNT;
        passband_rx_set_signal_wait_profile(NO_SYNC_REPLY_SIGNAL_THRESHOLD,
                                            NO_SYNC_REPLY_SIGNAL_STABLE);
        if(verbose != 0u)
        {
            printf("Signal wait profile: threshold=%u stable=%u\r\n",
                   (unsigned int)NO_SYNC_REPLY_SIGNAL_THRESHOLD,
                   (unsigned int)NO_SYNC_REPLY_SIGNAL_STABLE);
        }
    }
    else
    {
        wake_sample_count = NO_SYNC_REQUEST_WAKE_SAMPLE_COUNT;
        passband_rx_set_signal_wait_profile(NO_SYNC_REQUEST_SIGNAL_THRESHOLD,
                                            NO_SYNC_REQUEST_SIGNAL_STABLE);
        if(verbose != 0u)
        {
            printf("Signal wait profile: threshold=%u stable=%u\r\n",
                   (unsigned int)NO_SYNC_REQUEST_SIGNAL_THRESHOLD,
                   (unsigned int)NO_SYNC_REQUEST_SIGNAL_STABLE);
        }
    }

    half_duplex_enter_rx();

    preroll_count = passband_rx_wait_signal(signal_timeout_ms);
    if(preroll_count == 0u)
    {
        if((signal_timeout_ms != 0u) && (verbose != 0u))
        {
            printf("RX signal timeout: %lu ms\r\n", (unsigned long)signal_timeout_ms);
        }

        passband_rx_stop();
        passband_rx_restore_default_signal_wait_profile();
        half_duplex_enter_idle();
        if(status_out != 0)
        {
            *status_out = NO_SYNC_RX_STATUS_TIMEOUT;
        }
        return 0u;
    }

    if(preroll_count >= PASSBAND_RX_DEFAULT_CAPTURE_LENGTH)
    {
        preroll_count = PASSBAND_RX_DEFAULT_CAPTURE_LENGTH - 1u;
    }

    passband_rx_start_dma_append(preroll_count, PASSBAND_RX_DEFAULT_CAPTURE_LENGTH - preroll_count);
    if(verbose != 0u)
    {
        printf("RX signal detected on PA0.\r\n");
        printf("No-sync preroll: %lu samples\r\n", (unsigned long)preroll_count);
    }
    passband_rx_wait_complete();

    if(verbose != 0u)
    {
        printf("RX capture length: %lu samples\r\n", (unsigned long)PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
        printf("RX passband capture done.\r\n");
    }

    rx_min = 4095u;
    rx_max = 0u;
    if(verbose != 0u)
    {
        for(i = 0u; i < passband_rx_get_captured_length(); i++)
        {
            uint16_t sample;

            sample = passband_rx_get_sample(i);
            if(sample < rx_min)
            {
                rx_min = sample;
            }
            if(sample > rx_max)
            {
                rx_max = sample;
            }
        }
    }
    if(verbose != 0u)
    {
        printf("RX sample min/max: %u / %u\r\n", rx_min, rx_max);
    }

    decode_offset = 0u;
    expected_start = 0u;
    decode_real_samples_no_sync_search(result,
                                       preroll_count,
                                       wake_sample_count,
                                       &decode_offset,
                                       &expected_start);

    if(verbose != 0u)
    {
        printf("No-sync expected frame start: %lu samples\r\n", (unsigned long)expected_start);
        printf("No-sync search begin: %lu samples\r\n", (unsigned long)decode_offset);
    }

    if((result->valid != 0u) && (verbose != 0u))
    {
        printf("RX active start index: %lu\r\n", (unsigned long)result->active_start_index);
        printf("RX best start index: %lu\r\n", (unsigned long)result->best_start_index);
        printf("RX preamble score: %ld\r\n", (long)result->best_preamble_score);
        print_frame_bytes("RX frame bytes: ", result->rx_frame_bytes, DSSS_FRAME_BYTE_COUNT);
        printf("RX data byte: 0x%02X\r\n", result->rx_data);
        printf("Checksum: %s\r\n", result->checksum_ok != 0u ? "OK" : "FAIL");
    }
    else if(verbose != 0u)
    {
        printf("No valid frame found.\r\n");
    }

    passband_rx_restore_default_signal_wait_profile();
    half_duplex_enter_idle();

    if((result->valid != 0u) && (result->checksum_ok != 0u))
    {
        if(status_out != 0)
        {
            *status_out = NO_SYNC_RX_STATUS_OK;
        }
        return 1u;
    }

    if(status_out != 0)
    {
        *status_out = NO_SYNC_RX_STATUS_FRAME_ERROR;
    }
    return 0u;
}

static uint8_t receive_one_frame_no_sync_scheduled(real_rx_result_t *result,
                                                   uint32_t capture_delay_ms)
{
    uint32_t i;
    uint32_t max_offset;
    uint32_t search_begin;
    uint32_t search_end;
    uint16_t rx_min;
    uint16_t rx_max;
    real_rx_result_t rough_result;

    if(result == 0)
    {
        return 0u;
    }

    printf("\r\n[RX Window]\r\n");
    printf("Node role: %s\r\n", get_node_role_name(g_node_role));
    printf("Waiting fixed reply window on PA0...\r\n");
    printf("Scheduled reply capture delay: %lu ms\r\n", (unsigned long)capture_delay_ms);

    delay_ms(capture_delay_ms);

    passband_rx_start_dma(PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
    half_duplex_enter_rx();
    passband_rx_wait_complete();

    printf("RX capture length: %lu samples\r\n", (unsigned long)PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
    printf("RX passband capture done.\r\n");

    rx_min = 4095u;
    rx_max = 0u;
    for(i = 0u; i < passband_rx_get_captured_length(); i++)
    {
        uint16_t sample;

        sample = passband_rx_get_sample(i);
        if(sample < rx_min)
        {
            rx_min = sample;
        }
        if(sample > rx_max)
        {
            rx_max = sample;
        }
    }
    printf("RX sample min/max: %u / %u\r\n", rx_min, rx_max);

    max_offset = passband_rx_get_captured_length() - DSSS_RX_FRAME_SAMPLE_COUNT;
    search_end = passband_rx_get_captured_length() - DSSS_RX_FRAME_SAMPLE_COUNT;
    rough_result = dsss_modem_decode_real_samples(passband_rx_get_buffer(),
                                                  passband_rx_get_captured_length());
    *result = rough_result;

    printf("Scheduled search begin: 0 samples\r\n");
    printf("Scheduled search end: %lu samples\r\n", (unsigned long)search_end);
    printf("Scheduled active start estimate: %lu samples\r\n",
           (unsigned long)rough_result.active_start_index);
    printf("Capture fit max offset: %lu samples\r\n", (unsigned long)max_offset);

    if((rough_result.valid == 0u) &&
       (rough_result.active_start_index < passband_rx_get_captured_length()) &&
       (rough_result.active_start_index <= max_offset))
    {
        if(rough_result.active_start_index > (NO_SYNC_TARGET_SEARCH_RADIUS * 2u))
        {
            search_begin = rough_result.active_start_index - (NO_SYNC_TARGET_SEARCH_RADIUS * 2u);
        }
        else
        {
            search_begin = 0u;
        }

        search_end = rough_result.active_start_index + (NO_SYNC_TARGET_SEARCH_RADIUS * 2u);
        if(search_end > max_offset)
        {
            search_end = max_offset;
        }

        *result = dsss_modem_decode_real_samples_in_window(passband_rx_get_buffer(),
                                                           passband_rx_get_captured_length(),
                                                           search_begin,
                                                           search_end);

        printf("Scheduled retry search begin: %lu samples\r\n", (unsigned long)search_begin);
        printf("Scheduled retry search end: %lu samples\r\n", (unsigned long)search_end);
    }
    else if((rough_result.valid == 0u) &&
            (rough_result.active_start_index > max_offset))
    {
        printf("Reply start is beyond fit range by: %lu samples\r\n",
               (unsigned long)(rough_result.active_start_index - max_offset));
    }

    if(result->valid != 0u)
    {
        printf("RX active start index: %lu\r\n", (unsigned long)result->active_start_index);
        printf("RX best start index: %lu\r\n", (unsigned long)result->best_start_index);
        printf("RX preamble score: %ld\r\n", (long)result->best_preamble_score);
        print_frame_bytes("RX frame bytes: ", result->rx_frame_bytes, DSSS_FRAME_BYTE_COUNT);
        printf("RX data byte: 0x%02X\r\n", result->rx_data);
        printf("Checksum: %s\r\n", result->checksum_ok != 0u ? "OK" : "FAIL");
    }
    else
    {
        printf("No valid frame found.\r\n");
    }

    half_duplex_enter_idle();

    if((result->valid != 0u) && (result->checksum_ok != 0u))
    {
        return 1u;
    }

    return 0u;
}

static void run_requester_mode(uint8_t tx_data)
{
    real_rx_result_t reply_result;

    printf("\r\n[Request]\r\n");
    printf("Requester send byte: 0x%02X\r\n", tx_data);
    print_frame_info(tx_data);

    send_one_frame_once(tx_data);

    printf("Requester send done, waiting reply...\r\n");

    if(receive_one_frame_once(&reply_result, REQUESTER_REPLY_SYNC_TIMEOUT_MS) != 0u)
    {
        printf("Reply received: 0x%02X\r\n", reply_result.rx_data);

        if(reply_result.rx_data == tx_data)
        {
            printf("Request-response result: OK\r\n");
        }
        else
        {
            printf("Request-response result: DATA MISMATCH\r\n");
        }
    }
    else
    {
        printf("Reply receive failed or timeout.\r\n");
    }

    printf("Waiting for next requester data...\r\n");
}

static void run_requester_no_sync_mode(uint8_t tx_data)
{
    real_rx_result_t reply_result;

    printf("\r\n[Request]\r\n");
    printf("Requester(no-sync) send byte: 0x%02X\r\n", tx_data);
    print_frame_info(tx_data);
    printf("Wake tone: %u ms, wake gap: %u ms\r\n",
           (unsigned int)NO_SYNC_REQUEST_WAKE_TONE_MS,
           (unsigned int)NO_SYNC_WAKE_GAP_MS);

    send_one_frame_once_no_sync(g_no_sync_reply_wake_samples,
                                SLOT_WAKE_SAMPLE_COUNT,
                                NO_SYNC_WAKE_GAP_SAMPLE_COUNT,
                                tx_data);

    printf("Requester(no-sync) send done, waiting reply...\r\n");

    if(receive_one_frame_no_sync_scheduled(&reply_result, NO_SYNC_REPLY_CAPTURE_DELAY_MS) != 0u)
    {
        printf("Reply received: 0x%02X\r\n", reply_result.rx_data);

        if(reply_result.rx_data == tx_data)
        {
            printf("Request-response result: OK\r\n");
        }
        else
        {
            printf("Request-response result: DATA MISMATCH\r\n");
        }
    }
    else
    {
        printf("Reply receive failed or timeout.\r\n");
    }

    printf("Waiting for next requester data...\r\n");
}

static void run_responder_mode(void)
{
    real_rx_result_t request_result;
    uint8_t request_data;

    if(receive_one_frame_once(&request_result, 0u) == 0u)
    {
        return;
    }

    request_data = request_result.rx_data;

    printf("Responder got request: 0x%02X\r\n", request_data);
    printf("Responder will echo reply.\r\n");

    delay_ms(50);
    send_one_frame_once(request_data);

    printf("Responder reply done.\r\n");
}

static void run_responder_no_sync_mode(void)
{
    real_rx_result_t request_result;
    uint8_t request_data;

    if(receive_one_frame_no_sync(&request_result, 0u, 0u, 0) == 0u)
    {
        return;
    }

    request_data = request_result.rx_data;

    if(NO_SYNC_REPLY_DELAY_MS > 0u)
    {
        delay_ms(NO_SYNC_REPLY_DELAY_MS);
    }
    send_one_frame_once_no_sync_burst(0,
                                      0u,
                                      0u,
                                      request_data,
                                      NO_SYNC_REPLY_BURST_COUNT,
                                      NO_SYNC_REPLY_BURST_GAP_MS,
                                      0);

    printf("Responder(no-sync) got request: 0x%02X\r\n", request_data);
    printf("Responder(no-sync) reply done.\r\n");
}

static void run_slot_a_mode(void)
{
    real_rx_result_t slot_result;
    uint8_t tx_data;
    uint8_t tx_is_user_frame;
    uint8_t tx_burst_start;
    no_sync_rx_status_t rx_status;
    uint8_t rx_is_idle;
    slot_rx_vote_result_t rx_vote_result;

    slot_result.rx_data = 0u;
    tx_data = 0u;
    tx_burst_start = 0u;
    tx_is_user_frame = slot_get_next_tx_data(&g_slot_a_tx_state, &tx_data, &tx_burst_start);
    slot_stats_record_tx(&g_slot_a_stats, tx_is_user_frame, tx_burst_start);

    if(tx_is_user_frame != 0u)
    {
        send_one_frame_once_no_sync(g_no_sync_reply_wake_samples,
                                    SLOT_WAKE_SAMPLE_COUNT,
                                    NO_SYNC_WAKE_GAP_SAMPLE_COUNT,
                                    tx_data);
    }
    else
    {
        send_one_idle_frame_once_no_sync(g_no_sync_reply_wake_samples,
                                         SLOT_WAKE_SAMPLE_COUNT,
                                         NO_SYNC_WAKE_GAP_SAMPLE_COUNT);
    }

    receive_one_frame_no_sync(&slot_result,
                              REQUESTER_REPLY_SIGNAL_TIMEOUT_MS,
                              0u,
                              &rx_status);
    rx_is_idle = real_result_is_idle_frame(&slot_result);
    slot_stats_record_rx(&g_slot_a_stats, rx_status, rx_is_idle);
    slot_rx_vote_consume(&g_slot_a_rx_vote_state,
                         rx_status,
                         rx_is_idle,
                         slot_result.rx_data,
                         &rx_vote_result);
    slot_stats_record_rx_vote(&g_slot_a_stats, &rx_vote_result);

    if(should_print_slot_summary(tx_burst_start, &rx_vote_result) != 0u)
    {
        print_slot_summary("Slot A",
                           tx_burst_start,
                           tx_data,
                           &rx_vote_result);
    }

    maybe_print_slot_stats("Slot A", &g_slot_a_stats);
}

static void run_slot_b_mode(void)
{
    real_rx_result_t slot_result;
    uint8_t tx_data;
    uint8_t tx_is_user_frame;
    uint8_t tx_burst_start;
    no_sync_rx_status_t rx_status;
    uint8_t rx_is_idle;
    slot_rx_vote_result_t rx_vote_result;

    slot_result.rx_data = 0u;
    tx_burst_start = 0u;

    receive_one_frame_no_sync(&slot_result, 0u, 0u, &rx_status);
    rx_is_idle = real_result_is_idle_frame(&slot_result);
    slot_stats_record_rx(&g_slot_b_stats, rx_status, rx_is_idle);
    slot_rx_vote_consume(&g_slot_b_rx_vote_state,
                         rx_status,
                         rx_is_idle,
                         slot_result.rx_data,
                         &rx_vote_result);
    slot_stats_record_rx_vote(&g_slot_b_stats, &rx_vote_result);
    tx_data = 0u;
    tx_is_user_frame = slot_get_next_tx_data(&g_slot_b_tx_state, &tx_data, &tx_burst_start);
    slot_stats_record_tx(&g_slot_b_stats, tx_is_user_frame, tx_burst_start);

    if(tx_is_user_frame != 0u)
    {
        send_one_frame_once_no_sync(g_no_sync_reply_wake_samples,
                                    SLOT_WAKE_SAMPLE_COUNT,
                                    NO_SYNC_WAKE_GAP_SAMPLE_COUNT,
                                    tx_data);
    }
    else
    {
        send_one_idle_frame_once_no_sync(g_no_sync_reply_wake_samples,
                                         SLOT_WAKE_SAMPLE_COUNT,
                                         NO_SYNC_WAKE_GAP_SAMPLE_COUNT);
    }

    if(should_print_slot_summary(tx_burst_start, &rx_vote_result) != 0u)
    {
        print_slot_summary("Slot B",
                           tx_burst_start,
                           tx_data,
                           &rx_vote_result);
    }

    maybe_print_slot_stats("Slot B", &g_slot_b_stats);
}


static void run_tx_only_mode(uint8_t tx_data)
{
    uint8_t repeat_index;
    const uint8_t repeat_count = 20u;

    dsss_modem_set_random_seed((uint32_t)tx_data + 1u);

    printf("\r\n[TX Frame]\r\n");
    printf("Node role: %s\r\n", get_node_role_name(g_node_role));
    print_frame_info(tx_data);
    printf("TX burst count: %u\r\n", repeat_count);
    printf("TX gap: 50 ms\r\n");

    for(repeat_index = 0u; repeat_index < repeat_count; repeat_index++)
    {
        half_duplex_sync_pulse_start();
        delay_ms(15);
        half_duplex_enter_tx();
        passband_tx_send_blocking(dsss_modem_get_tx_sample_buffer(),
                                  dsss_modem_get_tx_sample_length());
        half_duplex_enter_idle();

        printf("TX burst progress: %u / %u\r\n",
               (unsigned int)(repeat_index + 1u),
               (unsigned int)repeat_count);

        if((repeat_index + 1u) < repeat_count)
        {
            delay_ms(50);
        }
    }

    printf("TX burst send done.\r\n");
    printf("Waiting for next TX data...\r\n");
}

static void run_rx_only_mode(void)
{
    uint32_t i;
    uint16_t rx_min;
    uint16_t rx_max;
    real_rx_result_t real_result;

    printf("\r\n[RX Window]\r\n");
    printf("Node role: %s\r\n", get_node_role_name(g_node_role));
    printf("Waiting sync pulse on PB1...\r\n");
    half_duplex_sync_wait_start();
    passband_rx_start_dma(PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
    half_duplex_enter_rx();
    passband_rx_wait_complete();

    printf("Sync pulse detected.\r\n");
    printf("RX capture length: %lu samples\r\n", (unsigned long)PASSBAND_RX_DEFAULT_CAPTURE_LENGTH);
    printf("RX passband capture done.\r\n");

    rx_min = 4095u;
    rx_max = 0u;
    for(i = 0; i < passband_rx_get_captured_length(); i++)
    {
        uint16_t sample;

        sample = passband_rx_get_sample(i);
        if(sample < rx_min)
        {
            rx_min = sample;
        }
        if(sample > rx_max)
        {
            rx_max = sample;
        }
    }
    printf("RX sample min/max: %u / %u\r\n", rx_min, rx_max);

    real_result = dsss_modem_decode_real_samples(passband_rx_get_buffer(),
                                                 passband_rx_get_captured_length());
    if(real_result.valid != 0u)
    {
        printf("RX active start index: %lu\r\n", (unsigned long)real_result.active_start_index);
        printf("RX best start index: %lu\r\n", (unsigned long)real_result.best_start_index);
        printf("RX preamble score: %ld\r\n", (long)real_result.best_preamble_score);
        print_frame_bytes("RX frame bytes: ", real_result.rx_frame_bytes, DSSS_FRAME_BYTE_COUNT);
        printf("RX data byte: 0x%02X\r\n", real_result.rx_data);
        printf("Checksum: %s\r\n", real_result.checksum_ok != 0u ? "OK" : "FAIL");
    }
    else
    {
        printf("No valid frame found.\r\n");
    }

    half_duplex_enter_idle();
}

int main(void)
{
    uint8_t tx_data;

    system_init();
    usart0_init();//娑撴彃褰?閸掓繂顫愰崠?
    passband_tx_init();//闁板秶鐤咲AC閸滃IMER6閸欐垿鈧線鎽肩捄?
    passband_rx_init();//闁板秶鐤咥DC0閿涘IMER2閿涘瓕MA0闁岸浜?閸滃苯鍙炬稉顓熸焽
	half_duplex_init();//閸掓繂顫愰崠鏍у磹閸欏苯浼愰悩鑸碘偓浣规簚閿涘矂绮拋銈堢箻閸忋儱绶熼張铏瑰Ц閹?
    dsss_modem_init();//閸掓繂顫愰崠鏈燦閻胶鐡戠拫鍐ㄥ煑鐟欙綀鐨熼崘鍛村劥閻樿埖鈧?
    dsss_modem_set_rx_mode(RX_MODE_REAL);//鐠佸墽鐤嗛幒銉︽暪濡€崇础閿涘牏婀＄€圭偤鍣伴弽鍑ょ礆
    init_no_sync_waveform_buffers();
    delay_ms(100);

    print_welcome();
    g_node_role = wait_node_role_select();
    printf("Selected node role: %s\r\n", get_node_role_name(g_node_role));
    if(g_node_role == MODEM_NODE_ROLE_TX_ONLY)
    {
        half_duplex_sync_init_tx();
    }
    else if(g_node_role == MODEM_NODE_ROLE_RX_ONLY)
    {
        half_duplex_sync_init_rx();
    }
    else if((g_node_role == MODEM_NODE_ROLE_REQUESTER) ||
            (g_node_role == MODEM_NODE_ROLE_RESPONDER))
    {
        half_duplex_sync_init_tx();
        half_duplex_sync_init_rx();
    }
    if(g_node_role == MODEM_NODE_ROLE_RX_ONLY)
    {
        printf("RX node is listening for external frames.\r\n");
    }
    else if(g_node_role == MODEM_NODE_ROLE_RESPONDER)
    {
        printf("Responder node is listening for external requests.\r\n");
    }
    else if(g_node_role == MODEM_NODE_ROLE_REQUESTER)
    {
        printf("Requester node is waiting for USART data.\r\n");
    }
    else if(g_node_role == MODEM_NODE_ROLE_RESPONDER_NO_SYNC)
    {
        printf("Responder(no-sync) is listening on PA0 without PB0/PB1 sync wire.\r\n");
    }
    else if(g_node_role == MODEM_NODE_ROLE_REQUESTER_NO_SYNC)
    {
        printf("Requester(no-sync) is waiting for USART data.\r\n");
    }
    else if(g_node_role == MODEM_NODE_ROLE_SLOT_A)
    {
        printf("Slot-A node is driving no-sync half-duplex cycles on PA4/PA0.\r\n");
        printf("Input a byte on USART anytime. Each new byte repeats for %u slot transmissions.\r\n",
               (unsigned int)SLOT_USER_REPEAT_COUNT);
        printf("After each repeated byte burst, Slot-A inserts %u idle slot.\r\n",
               (unsigned int)SLOT_USER_GAP_IDLE_COUNT);
        printf("When no repeated byte is pending, Slot-A sends an idle frame.\r\n");
        printf("Idle slot cycles are hidden. TX prints once per new byte burst.\r\n");
        printf("RX prints once after %u-slot majority vote confirmation.\r\n",
               (unsigned int)SLOT_USER_REPEAT_COUNT);
        printf("Vote rule: need %u matching copies to confirm one byte.\r\n",
               (unsigned int)SLOT_VOTE_MAJORITY_COUNT);
        printf("Slot wake profile: %u ms strong tone, RX threshold=%u stable=%u.\r\n",
               (unsigned int)SLOT_WAKE_TONE_MS,
               (unsigned int)SLOT_SIGNAL_THRESHOLD,
               (unsigned int)SLOT_SIGNAL_STABLE);
        printf("Slot stats are printed every %u receive events.\r\n",
               (unsigned int)SLOT_STATS_REPORT_INTERVAL);
        printf("Stats meaning: tx_burst=logical bytes, tx_repeat=repeated TX slots.\r\n");
    }
    else if(g_node_role == MODEM_NODE_ROLE_SLOT_B)
    {
        printf("Slot-B node is following Slot-A cycles without PB0/PB1 sync wire.\r\n");
        printf("Input a byte on USART anytime. Each new byte repeats for %u slot transmissions.\r\n",
               (unsigned int)SLOT_USER_REPEAT_COUNT);
        printf("After each repeated byte burst, Slot-B inserts %u idle slot.\r\n",
               (unsigned int)SLOT_USER_GAP_IDLE_COUNT);
        printf("When no repeated byte is pending, Slot-B sends an idle frame.\r\n");
        printf("Idle slot cycles are hidden. TX prints once per new byte burst.\r\n");
        printf("RX prints once after %u-slot majority vote confirmation.\r\n",
               (unsigned int)SLOT_USER_REPEAT_COUNT);
        printf("Vote rule: need %u matching copies to confirm one byte.\r\n",
               (unsigned int)SLOT_VOTE_MAJORITY_COUNT);
        printf("Slot wake profile: %u ms strong tone, RX threshold=%u stable=%u.\r\n",
               (unsigned int)SLOT_WAKE_TONE_MS,
               (unsigned int)SLOT_SIGNAL_THRESHOLD,
               (unsigned int)SLOT_SIGNAL_STABLE);
        printf("Slot stats are printed every %u receive events.\r\n",
               (unsigned int)SLOT_STATS_REPORT_INTERVAL);
        printf("Stats meaning: tx_burst=logical bytes, tx_repeat=repeated TX slots.\r\n");
    }
    else
    {
        printf("Waiting for data...\r\n");
    }

    while(1)
    {
    if(g_node_role == MODEM_NODE_ROLE_RX_ONLY)
    {
        run_rx_only_mode();
        continue;
    }

    if(g_node_role == MODEM_NODE_ROLE_RESPONDER)
    {
        run_responder_mode();
        continue;
    }

    if(g_node_role == MODEM_NODE_ROLE_RESPONDER_NO_SYNC)
    {
        run_responder_no_sync_mode();
        continue;
    }

    if(g_node_role == MODEM_NODE_ROLE_SLOT_A)
    {
        run_slot_a_mode();
        continue;
    }

    if(g_node_role == MODEM_NODE_ROLE_SLOT_B)
    {
        run_slot_b_mode();
        continue;
    }

    tx_data = usart_get_byte();
    if((tx_data == 0x0D) || (tx_data == 0x0A))
    {
        continue;
    }

    if(g_node_role == MODEM_NODE_ROLE_TX_ONLY)
    {
        run_tx_only_mode(tx_data);
        continue;
    }

    if(g_node_role == MODEM_NODE_ROLE_REQUESTER)
    {
        run_requester_mode(tx_data);
        continue;
    }

    if(g_node_role == MODEM_NODE_ROLE_REQUESTER_NO_SYNC)
    {
        run_requester_no_sync_mode(tx_data);
        continue;
    }

    dsss_modem_set_random_seed((uint32_t)tx_data + 1u);

    printf("\r\n[New Frame]\r\n");
    print_frame_info(tx_data);

    if(g_app_mode == APP_MODE_TEST)
    {
        if(dsss_modem_get_rx_mode() == RX_MODE_REAL)
        {
            run_real_test_mode(tx_data);
        }
        else
        {
            run_test_mode(tx_data);
        }
    }
    else
    {
        run_work_mode(tx_data);
    }

        printf("Waiting for next data...\r\n");
    }

}
/*閺佺繝缍嬪銉ょ稊閹繆鐭鹃敍?
	1.娴犲簼瑕嗛崣锝呭絺闁?鐎涙濡?
	2.缁嬪绨幎濠傜暊閹垫挸瀵橀幋鎬?1][DATA][CHK]閿涘牓鏆辨惔锕€鐡ч懞?閺佺増宓佺€涙濡?閺嶏繝鐛欑€涙濡敍?
	3.閸旂姴鍙?娴ｅ秴澧犵€佃偐鐖滈崥搴′粵DSSS閹碘晠顣?
	4.閻㈢喐鍨?2Hz鏉炶姤灏濋敍?8Hz闁插洦鐗遍惃鍕偓姘敨閸欐垿鈧焦灏濊ぐ?
	5.閸忓牆绱慉DC DMA閹恒儲鏁归敍鍫滅箽鐠囦線鍣伴弽鐤箾缂侇叏绱濋梽宥勭秵CPU鐠愮喐濯撮敍宀冾唨閹恒儲鏁归弮璺虹碍閺囧菙鐎规熬绱氶敍灞藉晙闁俺绻僁AC閸欐垿鈧焦鏆ｇ敮?
	6.闁插洦鐗辩€瑰本鍨氶崥搴℃躬閹恒儲鏁归弽椋庡仯闁插本澹樺ú璇插З鐠ч鍋ｉ敍灞惧閸撳秴顕遍惄绋垮彠瀹勬澘鈧》绱濈憴锝呭毉娑撳﹤鐡ч懞鍌氭姎楠炶泛浠涢弽锟犵崣
	7.娑撴彃褰涢幍鎾冲祪鐟欙絿鐖滄穱鈩冧紖*/
#if 0
#include "gd32e50x.h"
#include "systick.h"
#include <stdio.h>
#include <string.h>

/* 閺佺繝缍嬬紒鎾寸€敍姘崇箹娴犳垝鍞惍浣瑰Ω娑撯偓娑?8 娴ｅ秵鏆熼幑顔藉閹?8 娑?bit閵?
	 濮ｅ繋閲?bit 閸愬秶鏁ら梹鍨娑?31 閻?PN 閻焦澧挎０鎴礉閹碘偓娴?1 娑?bit 娴兼艾褰夐幋?31 娑?chip閵?
   閻喐顒滈崣鎴︹偓浣烘畱鐢傜瑝閺勵垰褰ч張澶嬫殶閹诡噯绱濇潻妯烘躬閸撳秹娼伴崝鐘辩啊 4 娴ｅ秴澧犵€佃偐鐖?1010閿涘瞼鏁ゆ禍搴㈠复閺€鍓侇伂閸嬫艾鎮撳銉ｂ偓?
   閹碘偓娴犮儲鏆ｇ敮褔鏆辨惔锔芥Ц閿涙瓍REAMBLE_LEN + PAYLOAD_BITS = 4 + 8 = 12 娑?bit閵?
   濮?bit 31 娑?chip閿涘本澧嶆禒銉︹偓濠氭毐鎼达附妲?16 * 31 = 496 chip*/
	 
	 
#define PN_CODE_LEN      31    // 鐎规矮绠烶N閻線鏆辨惔?1
#define TEST_ROUNDS 200				//閹鍙″ù瀣槸 200 鏉烆喓鈧?
#define PAYLOAD_BITS 8				//閺堝鏅ラ弫鐗堝祦闂€鍨 8 bit閿涘奔绡冪亸杈ㄦЦ 1 鐎涙濡妴?
#define PREAMBLE_LEN 8				//閸撳秴顕遍惍渚€鏆辨惔?8 bit閵?
#define FRAME_BITS (PREAMBLE_LEN + PAYLOAD_BITS)		//閺佹潙鎶氭稉鈧崗?16 bit閵?



uint8_t PN_Code[PN_CODE_LEN];		// 娣囨繂鐡?PN 鎼村繐鍨張顒冮煩閿涘苯鍘撶槐鐘虫Ц 0/1
int8_t  PN_BPSK[PN_CODE_LEN];		//娣囨繂鐡?PN 鎼村繐鍨弰鐘茬殸閹?BPSK 閸氬海娈戣ぐ銏犵础閿涘苯鍘撶槐鐘虫Ц +1/-1閿涘本鏌熸笟鍨粵閻╃鍙ф潻鎰暬閵?
static uint32_t rng_state = 1;	//娴碱亪娈㈤張鐑樻殶缁夊秴鐡欓敍宀€鏁ら弶銉δ侀幏鐔锋珨婢硅埇鈧?

const uint8_t PREAMBLE_BITS[PREAMBLE_LEN] = {1, 0, 1, 0, 1, 0, 1, 0}; //閸ュ搫鐣鹃崜宥咁嚤閻緤绱濋悽銊ょ艾閸氬本顒炵€规矮缍呴妴?
static uint8_t tx_stream[FRAME_BITS * PN_CODE_LEN];
static uint8_t rx_stream[FRAME_BITS * PN_CODE_LEN + PN_CODE_LEN];
static uint8_t *tx_active_stream = NULL;									//瑜版挸澧犻垾婊冨絺闁焦绁﹂垾婵堟畱閹稿洭鎷￠妴?
static uint16_t tx_chip_index = 0;												//瑜版挸澧犲鑼病閸欐垿鈧礁鍩岀粭顒€鍤戞稉?chip閵?
static uint16_t tx_chip_length = 0;												//瑜版挸澧犻崣鎴︹偓浣圭ウ閹鏆辨惔锔衡偓?
typedef struct
{
    uint16_t ok_count;
    uint16_t sync_ok_count;
    uint16_t data_ok_when_sync_ok;
    uint16_t last_best_offset;
} test_result_t;

typedef enum
{
    RX_MODE_SIMULATION = 0,
    RX_MODE_REAL = 1
} rx_mode_t;

static rx_mode_t g_rx_mode = RX_MODE_SIMULATION;

#define APP_MODE_TEST 0
#define APP_MODE_WORK 1

static uint8_t g_app_mode = APP_MODE_WORK;


//==================== 閹?printf 闁插秴鐣鹃崥鎴濆煂娑撴彃褰?====================
int fputc(int ch, FILE *f)
{
    usart_data_transmit(USART0, (uint8_t)ch);
    while(usart_flag_get(USART0, USART_FLAG_TC) == RESET);
    return ch;
}

//==================== 缁崵绮洪崚婵嗩潗閸栨牕宕版担宥呭毐閺?====================
void system_init(void)
{
    // 缁?
}

//==================== USART0 閸掓繂顫愰崠?===================
void usart0_init(void)
{
    rcu_periph_clock_enable(RCU_GPIOA);
    rcu_periph_clock_enable(RCU_USART0);

    // TX PA9
    gpio_init(GPIOA, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_9);

    // RX PA10
    gpio_init(GPIOA, GPIO_MODE_IPU, GPIO_OSPEED_50MHZ, GPIO_PIN_10);

    usart_baudrate_set(USART0, 9600);
    usart_word_length_set(USART0, USART_WL_8BIT);
    usart_stop_bit_set(USART0, USART_STB_1BIT);
    usart_parity_config(USART0, USART_PM_NONE);
    usart_receive_config(USART0, USART_RECEIVE_ENABLE);
    usart_transmit_config(USART0, USART_TRANSMIT_ENABLE);

    usart_enable(USART0);
}
//==================== 瀵よ埖妞傞崙鑺ユ殶 ====================
void delay_ms(uint32_t ms)
{
    volatile uint32_t i, j;
    for(i = 0; i < ms; i++)
        for(j = 0; j < 3000; j++);
}

//==================== 閻㈢喐鍨歅N閻礁绨崚?====================
void PN_generate(void)
{
    uint8_t reg = 0x1F;
    for(int i=0; i<PN_CODE_LEN; i++)
    {
        PN_Code[i] = reg & 1;
        uint8_t fb = ((reg >> 4) & 1) ^ ((reg >> 1) & 1);
        reg = (reg << 1) | fb;
    }

    for(int i=0; i<PN_CODE_LEN; i++)
        PN_BPSK[i] = PN_Code[i] ? 1 : -1;
}

//==================== 闁圭鏅犻。?====================
void DSSS_encode(uint8_t bit, uint8_t *chip_out)
{
    if(bit)
        for(int i=0; i<PN_CODE_LEN; i++) chip_out[i] = PN_Code[i];
    else
        for(int i=0; i<PN_CODE_LEN; i++) chip_out[i] = 1 - PN_Code[i];
}

//==================== 闁烩晝顭堥崣褎娼婚幇顔炬毈 ====================
int32_t correlate(int8_t *a, int8_t *b, uint16_t len)
{
    int32_t sum = 0;
    for(int i=0; i<len; i++)
        sum += a[i] * b[i];
    return sum;
}

int32_t DSSS_score(uint8_t *chip_in)
{
    int8_t rx[PN_CODE_LEN];
    uint16_t i;

    for(i = 0; i < PN_CODE_LEN; i++)
    {
        rx[i] = chip_in[i] ? 1 : -1;
    }

    return correlate(rx, PN_BPSK, PN_CODE_LEN);
}

//==================== 閻熸瑱绲炬晶?====================
uint8_t DSSS_decode(uint8_t *chip_in)
{
    int32_t corr = DSSS_score(chip_in);
    return corr > 0 ? 1 : 0;
}

// ===================== 闁靛棙鍔栭弻濠冩櫠閻愵亖鍋撻幋婊呯煠濞戞挻褰冭ぐ娑氭嫚?閻庢稒顨夋俊?=====================
uint8_t usart_get_byte(void)
{
    while(usart_flag_get(USART0, USART_FLAG_RBNE) == RESET);
    return usart_data_receive(USART0);
}

void inject_chip_errors(uint8_t *chips, uint16_t len, uint8_t error_count)
{
    uint16_t i;

    for(i = 0; i < error_count && i < len; i++)
    {
        chips[i] ^= 1;
    }
}

uint32_t pseudo_rand(void)
{
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state;
}

void inject_noise_by_rate(uint8_t *chips, uint16_t len, uint8_t error_percent)
{
    uint16_t i;

    for(i = 0; i < len; i++)
    {
        if((pseudo_rand() % 100) < error_percent)
        {
            chips[i] ^= 1;
        }
    }
}


uint16_t find_preamble_offset(uint8_t *chips, uint16_t search_len)
{
    uint16_t offset;
    uint16_t best_offset = 0;
    int32_t best_score = -1000000;

    for(offset = 0; offset < search_len; offset++)
    {
        int32_t total_score = 0;
        uint16_t p;

        for(p = 0; p < PREAMBLE_LEN; p++)
        {
            int32_t score = DSSS_score(&chips[offset + p * PN_CODE_LEN]);

            if(PREAMBLE_BITS[p] == 1)
            {
                total_score += score;
            }
            else
            {
                total_score -= score;
            }
        }

        if(total_score > best_score)
        {
            best_score = total_score;
            best_offset = offset;
        }
    }

    return best_offset;
}
//==================== 閻熸瑱绲炬晶?====================
void build_tx_frame(uint8_t tx_data, uint8_t *tx_stream)
{
    uint8_t chip_buf[PN_CODE_LEN];
    uint16_t p;
    int b;

    for(p = 0; p < PREAMBLE_LEN; p++)
    {
        DSSS_encode(PREAMBLE_BITS[p], chip_buf);
        memcpy(&tx_stream[p * PN_CODE_LEN], chip_buf, PN_CODE_LEN);
    }

    for(b = 0; b < PAYLOAD_BITS; b++)
    {
        uint8_t bit = (tx_data >> b) & 1;
        DSSS_encode(bit, chip_buf);
        memcpy(&tx_stream[(PREAMBLE_LEN + b) * PN_CODE_LEN], chip_buf, PN_CODE_LEN);
    }
}

uint16_t get_tx_frame_length(void)
{
    return FRAME_BITS * PN_CODE_LEN;
}

uint8_t get_tx_chip(uint8_t *tx_stream, uint16_t index)
{
    if(index >= get_tx_frame_length())
    {
        return 0;
    }

    return tx_stream[index];
}

void tx_start(uint8_t tx_data, uint8_t *tx_stream)
{
    build_tx_frame(tx_data, tx_stream);
    tx_active_stream = tx_stream;
    tx_chip_index = 0;
    tx_chip_length = get_tx_frame_length();
}

uint8_t tx_has_next_chip(void)
{
    if(tx_active_stream == NULL)
    {
        return 0;
    }

    return tx_chip_index < tx_chip_length;
}

uint8_t tx_get_next_chip(void)
{
    if(!tx_has_next_chip())
    {
        return 0;
    }

    return tx_active_stream[tx_chip_index++];
}

void send_one_frame(uint8_t tx_data)
{
    tx_start(tx_data, tx_stream);
}


uint8_t receive_one_frame(uint8_t *rx_stream, uint16_t *best_offset_out)
{
    uint8_t rx_data = 0;
    uint16_t best_offset;

    best_offset = find_preamble_offset(rx_stream, PN_CODE_LEN);

    for(int b = 0; b < PAYLOAD_BITS; b++)
    {
        uint8_t bit = DSSS_decode(&rx_stream[best_offset + (PREAMBLE_LEN + b) * PN_CODE_LEN]);
        rx_data |= (bit << b);
    }

    *best_offset_out = best_offset;
    return rx_data;
}

void prepare_simulated_rx_stream(uint16_t sync_offset, uint8_t error_percent)
{
    memset(rx_stream, 0, sizeof(rx_stream));
    memcpy(&rx_stream[sync_offset], tx_stream, FRAME_BITS * PN_CODE_LEN);
    inject_noise_by_rate(rx_stream, FRAME_BITS * PN_CODE_LEN + sync_offset, error_percent);
}

void prepare_real_rx_stream(void)
{
		//鏉╂瑩鍣锋禒銉ユ倵鐟曚焦甯撮垾婊呮埂濮濓絿娈戦幒銉︽暪鐠侯垰绶為垾?
    memset(rx_stream, 0, sizeof(rx_stream));
}


void prepare_rx_stream(uint16_t sync_offset, uint8_t error_percent)
{
    if(g_rx_mode == RX_MODE_SIMULATION)
    {
        prepare_simulated_rx_stream(sync_offset, error_percent);
    }
    else
    {
        prepare_real_rx_stream();
    }
}




test_result_t run_dsss_test(uint8_t tx_data, uint8_t error_percent, uint16_t sync_offset)
{
    test_result_t result;
    uint16_t round;
    uint16_t best_offset;
    uint8_t rx_data;

    result.ok_count = 0;
    result.sync_ok_count = 0;
    result.data_ok_when_sync_ok = 0;
    result.last_best_offset = 0;

    for(round = 0; round < TEST_ROUNDS; round++)
    {
        rx_data = 0;
        send_one_frame(tx_data);

        prepare_rx_stream(sync_offset, error_percent);


        rx_data = receive_one_frame(rx_stream, &best_offset);

        if(best_offset == sync_offset)
        {
            result.sync_ok_count++;
        }

        if(tx_data == rx_data)
        {
            result.ok_count++;

            if(best_offset == sync_offset)
            {
                result.data_ok_when_sync_ok++;
            }
        }

        result.last_best_offset = best_offset;
    }

    return result;
}


int main(void)
{
		uint8_t tx_data;
		uint8_t error_percent = 30;
		uint16_t sync_offset = 10;
		test_result_t result;

		uint8_t rx_data;
		uint16_t best_offset;

    // 闁告帗绻傞～鎰板礌?
    system_init();
    usart0_init();
    PN_generate();
    delay_ms(100);

    printf("==== GD32E503 DSSS Modem V1 ====\r\n");
		printf("Input 1 byte from USART.\r\n");
		printf("Waiting for data...\r\n");

    // ==========================================
    // Read one byte from USART, for example 0xAB or 0xFF.
    // ==========================================
   
		
    while(1)
		{
		tx_data = usart_get_byte();
			if(tx_data == 0x0D || tx_data == 0x0A)
			{
				continue;
			}

		rng_state = tx_data + 1;
		send_one_frame(tx_data);

    printf("\r\n[New Frame]\r\n");
		printf("TX byte: 0x%02X\r\n", tx_data);
		if(g_rx_mode == RX_MODE_SIMULATION)
		{
			printf("RX mode: simulation\r\n");
		}
			else
		{
			printf("RX mode: real\r\n");
		}

		if(g_app_mode == APP_MODE_TEST)
		{
			printf("APP mode: test\r\n");
		}
		else
		{
			printf("APP mode: work\r\n");
		}

		
		printf("Noise setting: %d%%\r\n", error_percent);
		printf("Frame length: %d chips\r\n", get_tx_frame_length());

		printf("TX preview: ");
		for(uint16_t i = 0; i < 16 && tx_has_next_chip(); i++)
		{
			printf("%d", tx_get_next_chip());
		}
		printf("\r\n");
		if(g_app_mode == APP_MODE_TEST)
		{
			result = run_dsss_test(tx_data, error_percent, sync_offset);

			printf("Frame test result: %d / %d\r\n", result.ok_count, TEST_ROUNDS);
			printf("Sync offset set: %d\r\n", sync_offset);
			printf("Best offset: %d\r\n", result.last_best_offset);
			printf("Sync success: %d / %d\r\n", result.sync_ok_count, TEST_ROUNDS);
			printf("Data success with correct sync: %d / %d\r\n", result.data_ok_when_sync_ok, result.sync_ok_count);
		}
		else
		{
				if(g_rx_mode == RX_MODE_REAL)
				{
						printf("Work mode real RX is not implemented yet.\r\n");
						printf("Waiting for next data...\r\n");
						continue;
				}

				prepare_rx_stream(sync_offset, error_percent);
				rx_data = receive_one_frame(rx_stream, &best_offset);

				printf("RX byte: 0x%02X\r\n", rx_data);
				printf("Best offset: %d\r\n", best_offset);
		}

		printf("Waiting for next data...\r\n");



}
   
}
#endif
