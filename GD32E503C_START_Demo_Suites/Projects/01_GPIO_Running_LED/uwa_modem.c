#include "uwa_modem.h"
#include <string.h>
//==================== 负责DSSS组帧，扩频，同步，解码，校验 ====================
#define DSSS_REAL_RX_ACTIVE_THRESHOLD    200u
#define DSSS_REAL_RX_MIN_PREAMBLE_SCORE  50000
#define DSSS_REAL_RX_SEARCH_SPAN         12u
#define DSSS_REAL_RX_PHASE_COUNT         DSSS_RX_SAMPLES_PER_CYCLE
#define DSSS_REAL_RX_INVALID_SCORE       (-2147483647)

static uint8_t PN_Code[PN_CODE_LEN];
static int8_t PN_BPSK[PN_CODE_LEN];
static uint32_t rng_state = 1u;

static const uint8_t PREAMBLE_BITS[PREAMBLE_LEN] = {1, 0, 1, 0, 1, 0, 1, 0};
static const int16_t tx_carrier_cycle[DSSS_TX_SAMPLES_PER_CYCLE] =
{
    DSSS_TX_SAMPLE_AMPLITUDE,
    724,
    0,
    -724,
    -DSSS_TX_SAMPLE_AMPLITUDE,
    -724,
    0,
    724
};

static uint8_t tx_frame_bytes[DSSS_FRAME_BYTE_COUNT];
static uint8_t tx_stream[FRAME_CHIPS];
static uint8_t rx_stream[FRAME_CHIPS + PN_CODE_LEN];
static uint8_t *tx_active_stream = 0;
static uint16_t tx_chip_index = 0;
static uint16_t tx_chip_length = 0;
static uint32_t tx_sample_index = 0;
static rx_mode_t g_rx_mode = RX_MODE_SIMULATION;

static void pn_generate(void)
{
    uint8_t reg;
    uint8_t fb;
    uint16_t i;

    reg = 0x1F;
    for(i = 0; i < PN_CODE_LEN; i++)
    {
        PN_Code[i] = reg & 1u;
        fb = (uint8_t)(((reg >> 4) & 1u) ^ ((reg >> 1) & 1u));
        reg = (uint8_t)((reg << 1) | fb);
    }

    for(i = 0; i < PN_CODE_LEN; i++)
    {
        PN_BPSK[i] = PN_Code[i] ? 1 : -1;
    }
}

static void dsss_encode(uint8_t bit, uint8_t *chip_out)
{
    uint16_t i;

    if(bit != 0u)
    {
        for(i = 0; i < PN_CODE_LEN; i++)
        {
            chip_out[i] = PN_Code[i];
        }
    }
    else
    {
        for(i = 0; i < PN_CODE_LEN; i++)
        {
            chip_out[i] = (uint8_t)(1u - PN_Code[i]);
        }
    }
}

static int32_t correlate(const int8_t *a, const int8_t *b, uint16_t len)
{
    int32_t sum;
    uint16_t i;

    sum = 0;
    for(i = 0; i < len; i++)
    {
        sum += a[i] * b[i];
    }
    return sum;
}

static int32_t dsss_score(uint8_t *chip_in)
{
    int8_t rx[PN_CODE_LEN];
    uint16_t i;

    for(i = 0; i < PN_CODE_LEN; i++)
    {
        rx[i] = chip_in[i] ? 1 : -1;
    }

    return correlate(rx, PN_BPSK, PN_CODE_LEN);
}

static uint8_t dsss_decode(uint8_t *chip_in)
{
    int32_t corr;

    corr = dsss_score(chip_in);
    return (corr > 0) ? 1u : 0u;
}

static uint32_t pseudo_rand(void)
{
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state;
}

static void inject_noise_by_rate(uint8_t *chips, uint16_t len, uint8_t error_percent)
{
    uint16_t i;

    for(i = 0; i < len; i++)
    {
        if((pseudo_rand() % 100u) < error_percent)
        {
            chips[i] ^= 1u;
        }
    }
}

static uint16_t find_preamble_offset(uint8_t *chips, uint16_t search_len)
{
    uint16_t offset;
    uint16_t best_offset;
    int32_t best_score;

    best_offset = 0;
    best_score = -1000000;

    for(offset = 0; offset < search_len; offset++)
    {
        int32_t total_score;
        uint16_t p;

        total_score = 0;
        for(p = 0; p < PREAMBLE_LEN; p++)
        {
            int32_t score;

            score = dsss_score(&chips[offset + p * PN_CODE_LEN]);
            if(PREAMBLE_BITS[p] == 1u)
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

static uint8_t build_frame_checksum(const uint8_t *frame_bytes)
{
    return (uint8_t)(frame_bytes[DSSS_FRAME_LEN_INDEX] ^ frame_bytes[DSSS_FRAME_DATA_INDEX]);
}

static uint8_t frame_checksum_is_ok(const uint8_t *frame_bytes)
{
    if((frame_bytes[DSSS_FRAME_LEN_INDEX] != DSSS_FRAME_DATA_LENGTH) &&
       (frame_bytes[DSSS_FRAME_LEN_INDEX] != DSSS_FRAME_IDLE_LENGTH))
    {
        return 0u;
    }

    return (frame_bytes[DSSS_FRAME_CHECK_INDEX] == build_frame_checksum(frame_bytes)) ? 1u : 0u;
}

static void build_frame_bytes(uint8_t tx_data, uint8_t *frame_bytes)
{
    frame_bytes[DSSS_FRAME_LEN_INDEX] = DSSS_FRAME_DATA_LENGTH;
    frame_bytes[DSSS_FRAME_DATA_INDEX] = tx_data;
    frame_bytes[DSSS_FRAME_CHECK_INDEX] = build_frame_checksum(frame_bytes);
}

static void build_idle_frame_bytes(uint8_t *frame_bytes)
{
    frame_bytes[DSSS_FRAME_LEN_INDEX] = DSSS_FRAME_IDLE_LENGTH;
    frame_bytes[DSSS_FRAME_DATA_INDEX] = 0u;
    frame_bytes[DSSS_FRAME_CHECK_INDEX] = build_frame_checksum(frame_bytes);
}

static void build_tx_frame(const uint8_t *frame_bytes, uint8_t *stream)
{
    uint8_t chip_buf[PN_CODE_LEN];
    uint16_t p;
    uint16_t byte_index;
    uint16_t bit_index;

    for(p = 0; p < PREAMBLE_LEN; p++)
    {
        dsss_encode(PREAMBLE_BITS[p], chip_buf);
        memcpy(&stream[p * PN_CODE_LEN], chip_buf, PN_CODE_LEN);
    }

    for(byte_index = 0; byte_index < DSSS_FRAME_BYTE_COUNT; byte_index++)
    {
        for(bit_index = 0; bit_index < 8u; bit_index++)
        {
            uint8_t bit;
            uint16_t bit_position;

            bit = (uint8_t)((frame_bytes[byte_index] >> bit_index) & 1u);
            bit_position = (uint16_t)(PREAMBLE_LEN + (byte_index * 8u) + bit_index);
            dsss_encode(bit, chip_buf);
            memcpy(&stream[bit_position * PN_CODE_LEN], chip_buf, PN_CODE_LEN);
        }
    }
}

static int16_t get_tx_passband_sample_by_index(uint32_t index)
{
    uint32_t chip_index;
    uint32_t sample_in_chip;
    uint32_t cycle_index;
    int16_t chip_polarity;

    if(index >= DSSS_TX_FRAME_SAMPLE_COUNT)
    {
        return 0;
    }

    chip_index = index / DSSS_TX_SAMPLES_PER_CHIP;
    sample_in_chip = index % DSSS_TX_SAMPLES_PER_CHIP;
    cycle_index = sample_in_chip % DSSS_TX_SAMPLES_PER_CYCLE;
    chip_polarity = tx_stream[chip_index] ? 1 : -1;

    return (int16_t)(chip_polarity * tx_carrier_cycle[cycle_index]);
}

static uint16_t estimate_real_rx_midpoint(const uint16_t *samples, uint32_t sample_length)
{
    uint64_t sum;
    uint32_t i;

    if((samples == 0) || (sample_length == 0u))
    {
        return DSSS_ANALOG_MIDPOINT;
    }

    sum = 0u;
    for(i = 0; i < sample_length; i++)
    {
        sum += samples[i];
    }

    return (uint16_t)(sum / sample_length);
}

static uint32_t find_real_active_start(const uint16_t *samples, uint32_t sample_length, uint16_t midpoint)
{
    uint32_t i;

    for(i = 0; i < sample_length; i++)
    {
        uint16_t sample;
        uint16_t diff;

        sample = samples[i];
        if(sample >= midpoint)
        {
            diff = (uint16_t)(sample - midpoint);
        }
        else
        {
            diff = (uint16_t)(midpoint - sample);
        }

        if(diff > DSSS_REAL_RX_ACTIVE_THRESHOLD)
        {
            return i;
        }
    }

    return sample_length;
}

static int32_t get_real_chip_score_with_phase(const uint16_t *samples,
                                              uint32_t sample_length,
                                              uint32_t chip_start_index,
                                              uint16_t midpoint,
                                              uint8_t phase_offset)
{
    uint32_t cycle_base;
    int32_t sum;
    uint8_t positive_phase;
    uint8_t negative_phase;

    if((samples == 0) || ((chip_start_index + DSSS_RX_SAMPLES_PER_CHIP) > sample_length))
    {
        return 0;
    }

    sum = 0;
    positive_phase = (uint8_t)(phase_offset % DSSS_RX_SAMPLES_PER_CYCLE);
    negative_phase = (uint8_t)((positive_phase + (DSSS_RX_SAMPLES_PER_CYCLE / 2u)) % DSSS_RX_SAMPLES_PER_CYCLE);

    for(cycle_base = 0; cycle_base < DSSS_RX_SAMPLES_PER_CHIP; cycle_base += DSSS_RX_SAMPLES_PER_CYCLE)
    {
        int32_t positive_sample;
        int32_t negative_sample;

        positive_sample = (int32_t)samples[chip_start_index + cycle_base + positive_phase] - (int32_t)midpoint;
        negative_sample = (int32_t)samples[chip_start_index + cycle_base + negative_phase] - (int32_t)midpoint;
        sum += positive_sample;
        sum -= negative_sample;
    }

    return sum;
}

static int32_t get_real_bit_score_with_phase(const uint16_t *samples,
                                             uint32_t sample_length,
                                             uint32_t bit_start_index,
                                             uint16_t midpoint,
                                             uint8_t phase_offset)
{
    uint32_t chip_index;
    int32_t bit_score;

    if((samples == 0) || ((bit_start_index + (PN_CODE_LEN * DSSS_RX_SAMPLES_PER_CHIP)) > sample_length))
    {
        return 0;
    }

    bit_score = 0;

    for(chip_index = 0; chip_index < PN_CODE_LEN; chip_index++)
    {
        int32_t chip_score;

        chip_score = get_real_chip_score_with_phase(samples,
                                                    sample_length,
                                                    bit_start_index + (chip_index * DSSS_RX_SAMPLES_PER_CHIP),
                                                    midpoint,
                                                    phase_offset);
        bit_score += chip_score * PN_BPSK[chip_index];
    }

    return bit_score;
}

static int32_t get_real_preamble_score_with_phase(const uint16_t *samples,
                                                  uint32_t sample_length,
                                                  uint32_t frame_start_index,
                                                  uint16_t midpoint,
                                                  uint8_t phase_offset)
{
    uint32_t p;
    int32_t total_score;

    if((samples == 0) || ((frame_start_index + DSSS_RX_FRAME_SAMPLE_COUNT) > sample_length))
    {
        return DSSS_REAL_RX_INVALID_SCORE;
    }

    total_score = 0;

    for(p = 0; p < PREAMBLE_LEN; p++)
    {
        int32_t bit_score;

        bit_score = get_real_bit_score_with_phase(samples,
                                                  sample_length,
                                                  frame_start_index + (p * PN_CODE_LEN * DSSS_RX_SAMPLES_PER_CHIP),
                                                  midpoint,
                                                  phase_offset);
        if(PREAMBLE_BITS[p] == 1u)
        {
            total_score += bit_score;
        }
        else
        {
            total_score -= bit_score;
        }
    }

    return total_score;
}

static void decode_real_frame_bytes_with_phase(const uint16_t *samples,
                                               uint32_t sample_length,
                                               uint32_t frame_start_index,
                                               uint16_t midpoint,
                                               uint8_t phase_offset,
                                               int8_t phase_polarity,
                                               uint8_t *frame_bytes_out)
{
    uint16_t byte_index;
    uint16_t bit_index;

    if(frame_bytes_out == 0)
    {
        return;
    }

    memset(frame_bytes_out, 0, DSSS_FRAME_BYTE_COUNT);

    for(byte_index = 0; byte_index < DSSS_FRAME_BYTE_COUNT; byte_index++)
    {
        for(bit_index = 0; bit_index < 8u; bit_index++)
        {
            int32_t bit_score;
            uint32_t bit_position;

            bit_position = PREAMBLE_LEN + (byte_index * 8u) + bit_index;
            bit_score = get_real_bit_score_with_phase(samples,
                                                      sample_length,
                                                      frame_start_index + (bit_position * PN_CODE_LEN * DSSS_RX_SAMPLES_PER_CHIP),
                                                      midpoint,
                                                      phase_offset);
            bit_score *= phase_polarity;
            if(bit_score > 0)
            {
                frame_bytes_out[byte_index] |= (uint8_t)(1u << bit_index);
            }
        }
    }
}

static frame_rx_result_t receive_one_frame(uint8_t *stream)
{
    frame_rx_result_t result;
    uint16_t best_offset;
    uint16_t byte_index;
    uint16_t bit_index;

    memset(&result, 0, sizeof(result));
    best_offset = find_preamble_offset(stream, PN_CODE_LEN);
    result.valid = 1u;
    result.best_offset = best_offset;

    for(byte_index = 0; byte_index < DSSS_FRAME_BYTE_COUNT; byte_index++)
    {
        for(bit_index = 0; bit_index < 8u; bit_index++)
        {
            uint8_t bit;
            uint16_t bit_position;

            bit_position = (uint16_t)(PREAMBLE_LEN + (byte_index * 8u) + bit_index);
            bit = dsss_decode(&stream[best_offset + (bit_position * PN_CODE_LEN)]);
            result.rx_frame_bytes[byte_index] |= (uint8_t)(bit << bit_index);
        }
    }

    result.rx_data = result.rx_frame_bytes[DSSS_FRAME_DATA_INDEX];
    result.checksum_ok = frame_checksum_is_ok(result.rx_frame_bytes);
    return result;
}

static void prepare_simulated_rx_stream(uint16_t sync_offset, uint8_t error_percent)
{
    memset(rx_stream, 0, sizeof(rx_stream));
    memcpy(&rx_stream[sync_offset], tx_stream, FRAME_CHIPS);
    inject_noise_by_rate(rx_stream, (uint16_t)(FRAME_CHIPS + sync_offset), error_percent);
}

static void prepare_real_rx_stream(void)
{
    memset(rx_stream, 0, sizeof(rx_stream));
}

static void prepare_rx_stream(uint16_t sync_offset, uint8_t error_percent)
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

void dsss_modem_init(void)
{
    pn_generate();
}

void dsss_modem_set_rx_mode(rx_mode_t mode)
{
    g_rx_mode = mode;
}

rx_mode_t dsss_modem_get_rx_mode(void)
{
    return g_rx_mode;
}

void dsss_modem_set_random_seed(uint32_t seed)
{
    rng_state = seed;
}

void dsss_modem_prepare_tx_frame(uint8_t tx_data)
{
    build_frame_bytes(tx_data, tx_frame_bytes);
    build_tx_frame(tx_frame_bytes, tx_stream);
    tx_active_stream = tx_stream;
    tx_chip_index = 0;
    tx_chip_length = dsss_modem_get_frame_length();
}

void dsss_modem_prepare_idle_tx_frame(void)
{
    build_idle_frame_bytes(tx_frame_bytes);
    build_tx_frame(tx_frame_bytes, tx_stream);
    tx_active_stream = tx_stream;
    tx_chip_index = 0;
    tx_chip_length = dsss_modem_get_frame_length();
}

void dsss_modem_prepare_tx_samples(uint8_t tx_data)
{
    dsss_modem_prepare_tx_frame(tx_data);
    tx_sample_index = 0u;
}

void dsss_modem_prepare_idle_tx_samples(void)
{
    dsss_modem_prepare_idle_tx_frame();
    tx_sample_index = 0u;
}

uint16_t dsss_modem_get_frame_length(void)
{
    return FRAME_CHIPS;
}

uint16_t dsss_modem_get_frame_byte_count(void)
{
    return DSSS_FRAME_BYTE_COUNT;
}

void dsss_modem_get_tx_frame_bytes(uint8_t *frame_bytes, uint16_t frame_len)
{
    uint16_t copy_len;

    if((frame_bytes == 0) || (frame_len == 0u))
    {
        return;
    }

    copy_len = frame_len;
    if(copy_len > DSSS_FRAME_BYTE_COUNT)
    {
        copy_len = DSSS_FRAME_BYTE_COUNT;
    }

    memcpy(frame_bytes, tx_frame_bytes, copy_len);
}

void dsss_modem_get_tx_preview(char *preview, uint16_t preview_len)
{
    uint16_t count;
    uint16_t i;

    if((preview == 0) || (preview_len == 0u))
    {
        return;
    }

    count = (uint16_t)(preview_len - 1u);
    if(count > dsss_modem_get_frame_length())
    {
        count = dsss_modem_get_frame_length();
    }

    for(i = 0; i < count; i++)
    {
        preview[i] = tx_stream[i] ? '1' : '0';
    }
    preview[count] = '\0';
}

uint8_t dsss_modem_has_next_tx_chip(void)
{
    if(tx_active_stream == 0)
    {
        return 0u;
    }

    return (tx_chip_index < tx_chip_length) ? 1u : 0u;
}

uint8_t dsss_modem_get_next_tx_chip(void)
{
    if(dsss_modem_has_next_tx_chip() == 0u)
    {
        return 0u;
    }

    return tx_active_stream[tx_chip_index++];
}

uint32_t dsss_modem_get_tx_sample_length(void)
{
    return DSSS_TX_FRAME_SAMPLE_COUNT;
}

const int16_t *dsss_modem_get_tx_sample_buffer(void)
{
    return 0;
}

int16_t dsss_modem_get_tx_sample(uint32_t index)
{
    return get_tx_passband_sample_by_index(index);
}

uint8_t dsss_modem_has_next_tx_sample(void)
{
    return (tx_sample_index < DSSS_TX_FRAME_SAMPLE_COUNT) ? 1u : 0u;
}

int16_t dsss_modem_get_next_tx_sample(void)
{
    if(dsss_modem_has_next_tx_sample() == 0u)
    {
        return 0;
    }

    return get_tx_passband_sample_by_index(tx_sample_index++);
}

test_result_t dsss_modem_run_test(uint8_t tx_data, uint8_t error_percent, uint16_t sync_offset)
{
    test_result_t result;
    uint16_t round;

    result.ok_count = 0;
    result.sync_ok_count = 0;
    result.data_ok_when_sync_ok = 0;
    result.last_best_offset = 0;

    for(round = 0; round < TEST_ROUNDS; round++)
    {
        frame_rx_result_t frame_result;

        dsss_modem_prepare_tx_frame(tx_data);
        prepare_rx_stream(sync_offset, error_percent);
        frame_result = receive_one_frame(rx_stream);

        if(frame_result.best_offset == sync_offset)
        {
            result.sync_ok_count++;
        }

        if((frame_result.checksum_ok != 0u) && (tx_data == frame_result.rx_data))
        {
            result.ok_count++;
            if(frame_result.best_offset == sync_offset)
            {
                result.data_ok_when_sync_ok++;
            }
        }

        result.last_best_offset = frame_result.best_offset;
    }

    return result;
}

frame_rx_result_t dsss_modem_run_work_once(uint8_t tx_data, uint8_t error_percent, uint16_t sync_offset)
{
    dsss_modem_prepare_tx_frame(tx_data);
    prepare_rx_stream(sync_offset, error_percent);
    return receive_one_frame(rx_stream);
}

static real_rx_result_t dsss_modem_decode_real_samples_internal(const uint16_t *samples,
                                                                uint32_t sample_length,
                                                                uint8_t use_forced_window,
                                                                uint32_t forced_search_begin,
                                                                uint32_t forced_search_end)
{
    real_rx_result_t result;
    real_rx_result_t checksum_result;
    uint32_t active_start;
    uint32_t search_begin;
    uint32_t search_end;
    uint32_t candidate;
    uint8_t phase_offset;
    uint16_t midpoint;
    uint8_t best_phase_offset;
    int8_t best_phase_polarity;

    memset(&result, 0, sizeof(result));
    memset(&checksum_result, 0, sizeof(checksum_result));
    result.valid = 0u;
    result.rx_data = 0u;
    result.active_start_index = 0u;
    result.best_start_index = 0u;
    result.best_preamble_score = DSSS_REAL_RX_INVALID_SCORE;
    checksum_result.best_preamble_score = DSSS_REAL_RX_INVALID_SCORE;
    best_phase_offset = 0u;
    best_phase_polarity = 1;

    if((samples == 0) || (sample_length < DSSS_RX_FRAME_SAMPLE_COUNT))
    {
        return result;
    }

    midpoint = estimate_real_rx_midpoint(samples, sample_length);
    active_start = find_real_active_start(samples, sample_length, midpoint);
    result.active_start_index = active_start;
    checksum_result.active_start_index = active_start;

    if(use_forced_window == 0u)
    {
        if(active_start >= sample_length)
        {
            return result;
        }

        if(active_start > DSSS_REAL_RX_SEARCH_SPAN)
        {
            search_begin = active_start - DSSS_REAL_RX_SEARCH_SPAN;
        }
        else
        {
            search_begin = 0u;
        }

        search_end = active_start + DSSS_REAL_RX_SEARCH_SPAN;
    }
    else
    {
        if(forced_search_begin > (sample_length - DSSS_RX_FRAME_SAMPLE_COUNT))
        {
            return result;
        }

        search_begin = forced_search_begin;
        search_end = forced_search_end;
        if(search_end < search_begin)
        {
            return result;
        }
    }

    if((search_end + DSSS_RX_FRAME_SAMPLE_COUNT) > sample_length)
    {
        search_end = sample_length - DSSS_RX_FRAME_SAMPLE_COUNT;
    }

    for(candidate = search_begin; candidate <= search_end; candidate++)
    {
        for(phase_offset = 0u; phase_offset < DSSS_REAL_RX_PHASE_COUNT; phase_offset++)
        {
            int32_t preamble_score;
            int32_t score_magnitude;

            preamble_score = get_real_preamble_score_with_phase(samples,
                                                                sample_length,
                                                                candidate,
                                                                midpoint,
                                                                phase_offset);
            score_magnitude = preamble_score;
            if(score_magnitude < 0)
            {
                score_magnitude = -score_magnitude;
            }

            if(score_magnitude > result.best_preamble_score)
            {
                result.best_preamble_score = score_magnitude;
                result.best_start_index = candidate;
                best_phase_offset = phase_offset;
                best_phase_polarity = (preamble_score >= 0) ? 1 : -1;
                result.valid = 1u;
            }

            if(score_magnitude >= DSSS_REAL_RX_MIN_PREAMBLE_SCORE)
            {
                uint8_t candidate_frame_bytes[DSSS_FRAME_BYTE_COUNT];
                int8_t candidate_phase_polarity;

                candidate_phase_polarity = (preamble_score >= 0) ? 1 : -1;
                decode_real_frame_bytes_with_phase(samples,
                                                   sample_length,
                                                   candidate,
                                                   midpoint,
                                                   phase_offset,
                                                   candidate_phase_polarity,
                                                   candidate_frame_bytes);
                if(frame_checksum_is_ok(candidate_frame_bytes) != 0u)
                {
                    if((checksum_result.valid == 0u) || (score_magnitude > checksum_result.best_preamble_score))
                    {
                        checksum_result.valid = 1u;
                        checksum_result.checksum_ok = 1u;
                        checksum_result.best_start_index = candidate;
                        checksum_result.best_preamble_score = score_magnitude;
                        memcpy(checksum_result.rx_frame_bytes,
                               candidate_frame_bytes,
                               DSSS_FRAME_BYTE_COUNT);
                        checksum_result.rx_data = candidate_frame_bytes[DSSS_FRAME_DATA_INDEX];
                    }
                }
            }
        }
    }

    if(checksum_result.valid != 0u)
    {
        return checksum_result;
    }

    if((result.valid == 0u) || (result.best_preamble_score < DSSS_REAL_RX_MIN_PREAMBLE_SCORE))
    {
        result.valid = 0u;
        return result;
    }

    decode_real_frame_bytes_with_phase(samples,
                                       sample_length,
                                       result.best_start_index,
                                       midpoint,
                                       best_phase_offset,
                                       best_phase_polarity,
                                       result.rx_frame_bytes);

    result.rx_data = result.rx_frame_bytes[DSSS_FRAME_DATA_INDEX];
    result.checksum_ok = frame_checksum_is_ok(result.rx_frame_bytes);
    return result;
}

real_rx_result_t dsss_modem_decode_real_samples(const uint16_t *samples, uint32_t sample_length)
{
    return dsss_modem_decode_real_samples_internal(samples, sample_length, 0u, 0u, 0u);
}

real_rx_result_t dsss_modem_decode_real_samples_in_window(const uint16_t *samples,
                                                          uint32_t sample_length,
                                                          uint32_t search_begin,
                                                          uint32_t search_end)
{
    return dsss_modem_decode_real_samples_internal(samples,
                                                   sample_length,
                                                   1u,
                                                   search_begin,
                                                   search_end);
}
