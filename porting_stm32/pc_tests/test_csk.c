/* test_csk.c - Chapter-6 CSK modem loopback through the firmware API:
 * prepare_tx -> 48 kHz decimated samples -> decode with each of the 3
 * receivers (matched filter / soft SIC / ESE). */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "scfde_csk.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

#define LOOPBACK_LEN (SCFDE_CSK_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)

static uint16_t g_loopback[LOOPBACK_LEN];

static void prepare_loopback(const uint8_t *payload, uint8_t length, uint8_t seq)
{
    uint32_t index;
    scfde_csk_prepare_tx(payload, length, seq);
    for (index = 0; index < LOOPBACK_LEN; index++)
    {
        int32_t adc = 2048 + (int32_t)scfde_csk_get_tx_sample(index * 2u);
        if (adc < 0) adc = 0;
        else if (adc > 4095) adc = 4095;
        g_loopback[index] = (uint16_t)adc;
    }
}

int main(void)
{
    const uint8_t payload[] = {'C', 'S', 'K'};
    unsigned r;

    scfde_fft_init();
    scfde_csk_init();
    for (r = 0; r < 3; r++)
    {
        scfde_rx_result_t result;
        prepare_loopback(payload, (uint8_t)sizeof(payload), 0x31u);
        result = scfde_csk_decode(g_loopback, LOOPBACK_LEN, (scfde_csk_receiver_t)r);
        printf("mode=%-12s: valid=%u sync=%.3f len=%u crc=%u\n",
               scfde_csk_receiver_name((scfde_csk_receiver_t)r),
               result.valid, result.sync_metric, result.payload_length,
               result.crc_ok);
        CHECK(result.valid == 1u, "loopback decode must pass");
        CHECK(result.payload_length == (uint8_t)sizeof(payload),
              "payload length mismatch");
        CHECK(result.sequence == 0x31u, "sequence mismatch");
        CHECK(memcmp(result.payload, payload, sizeof(payload)) == 0,
              "payload bytes mismatch");
    }
    printf("PASS\n");
    return 0;
}
