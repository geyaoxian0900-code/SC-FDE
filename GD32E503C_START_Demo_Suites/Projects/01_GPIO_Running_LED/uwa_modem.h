#ifndef UWA_MODEM_H
#define UWA_MODEM_H

#include <stdint.h>

#define PN_CODE_LEN               31
#define TEST_ROUNDS               200
#define PREAMBLE_LEN              8
#define DSSS_FRAME_BYTE_COUNT     3u
#define DSSS_FRAME_LEN_INDEX      0u
#define DSSS_FRAME_DATA_INDEX     1u
#define DSSS_FRAME_CHECK_INDEX    2u
#define DSSS_FRAME_IDLE_LENGTH    0u
#define DSSS_FRAME_DATA_LENGTH    1u
#define PAYLOAD_BITS              (DSSS_FRAME_BYTE_COUNT * 8u)
#define FRAME_BITS                (PREAMBLE_LEN + PAYLOAD_BITS)
#define FRAME_CHIPS               (FRAME_BITS * PN_CODE_LEN)

#define DSSS_CARRIER_FREQ_HZ              12000u
#define DSSS_TX_SAMPLE_RATE_HZ             96000u
#define DSSS_RX_SAMPLE_RATE_HZ             48000u
#define DSSS_CHIP_RATE_HZ                   1000u
#define DSSS_TX_SAMPLES_PER_CYCLE          (DSSS_TX_SAMPLE_RATE_HZ / DSSS_CARRIER_FREQ_HZ)
#define DSSS_RX_SAMPLES_PER_CYCLE          (DSSS_RX_SAMPLE_RATE_HZ / DSSS_CARRIER_FREQ_HZ)
#define DSSS_TX_SAMPLES_PER_CHIP           (DSSS_TX_SAMPLE_RATE_HZ / DSSS_CHIP_RATE_HZ)
#define DSSS_RX_SAMPLES_PER_CHIP           (DSSS_RX_SAMPLE_RATE_HZ / DSSS_CHIP_RATE_HZ)
#define DSSS_CARRIER_CYCLES_PER_CHIP       (DSSS_CARRIER_FREQ_HZ / DSSS_CHIP_RATE_HZ)
#define DSSS_TX_FRAME_SAMPLE_COUNT         (FRAME_CHIPS * DSSS_TX_SAMPLES_PER_CHIP)
#define DSSS_RX_FRAME_SAMPLE_COUNT         (FRAME_CHIPS * DSSS_RX_SAMPLES_PER_CHIP)
#define DSSS_TX_SAMPLE_AMPLITUDE       1024
#define DSSS_ANALOG_MIDPOINT           2048u

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

typedef struct
{
    uint8_t valid;
    uint8_t rx_data;
    uint8_t rx_frame_bytes[DSSS_FRAME_BYTE_COUNT];
    uint8_t checksum_ok;
    uint16_t best_offset;
} frame_rx_result_t;

typedef struct
{
    uint8_t valid;
    uint8_t rx_data;
    uint8_t rx_frame_bytes[DSSS_FRAME_BYTE_COUNT];
    uint8_t checksum_ok;
    uint32_t active_start_index;
    uint32_t best_start_index;
    int32_t best_preamble_score;
} real_rx_result_t;

void dsss_modem_init(void);
void dsss_modem_set_rx_mode(rx_mode_t mode);
rx_mode_t dsss_modem_get_rx_mode(void);
void dsss_modem_set_random_seed(uint32_t seed);

void dsss_modem_prepare_tx_frame(uint8_t tx_data);
void dsss_modem_prepare_idle_tx_frame(void);
uint16_t dsss_modem_get_frame_length(void);
uint16_t dsss_modem_get_frame_byte_count(void);
void dsss_modem_get_tx_frame_bytes(uint8_t *frame_bytes, uint16_t frame_len);
void dsss_modem_get_tx_preview(char *preview, uint16_t preview_len);
uint8_t dsss_modem_has_next_tx_chip(void);
uint8_t dsss_modem_get_next_tx_chip(void);

void dsss_modem_prepare_tx_samples(uint8_t tx_data);
void dsss_modem_prepare_idle_tx_samples(void);
uint32_t dsss_modem_get_tx_sample_length(void);
const int16_t *dsss_modem_get_tx_sample_buffer(void);
int16_t dsss_modem_get_tx_sample(uint32_t index);
uint8_t dsss_modem_has_next_tx_sample(void);
int16_t dsss_modem_get_next_tx_sample(void);

test_result_t dsss_modem_run_test(uint8_t tx_data, uint8_t error_percent, uint16_t sync_offset);
frame_rx_result_t dsss_modem_run_work_once(uint8_t tx_data, uint8_t error_percent, uint16_t sync_offset);
real_rx_result_t dsss_modem_decode_real_samples(const uint16_t *samples, uint32_t sample_length);
real_rx_result_t dsss_modem_decode_real_samples_in_window(const uint16_t *samples,
                                                          uint32_t sample_length,
                                                          uint32_t search_begin,
                                                          uint32_t search_end);

#endif
