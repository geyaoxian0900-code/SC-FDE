/* test_cck.c - Chapter-5 CCK modem loopback through the firmware API:
 * prepare_tx -> 48 kHz decimated samples -> decode with each of the 7
 * receivers (MFB/Rake/DFE/BiDFE/BiDFE2/TR-diversity/FDE). */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "scfde_cck.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

#define LOOPBACK_LEN (SCFDE_CCK_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)

static uint16_t g_loopback[LOOPBACK_LEN];

static void prepare_loopback(const uint8_t *payload, uint8_t length, uint8_t seq)
{
    uint32_t index;
    scfde_cck_prepare_tx(payload, length, seq);
    for (index = 0; index < LOOPBACK_LEN; index++)
    {
        int32_t adc = 2048 + (int32_t)scfde_cck_get_tx_sample(index * 2u);
        if (adc < 0) adc = 0;
        else if (adc > 4095) adc = 4095;
        g_loopback[index] = (uint16_t)adc;
    }
}

int main(void)
{
    const uint8_t payload[] = {'C', 'C', 'K', '-', 'O', 'K'};
    unsigned r;

    scfde_fft_init();
    scfde_cck_init();
    for (r = 0; r < 7; r++)
    {
        scfde_rx_result_t result;
        prepare_loopback(payload, (uint8_t)sizeof(payload), 0x21u);
        result = scfde_cck_decode(g_loopback, LOOPBACK_LEN, (scfde_cck_receiver_t)r);
        printf("mode=%-12s: valid=%u sync=%.3f len=%u crc=%u\n",
               scfde_cck_receiver_name((scfde_cck_receiver_t)r),
               result.valid, result.sync_metric, result.payload_length,
               result.crc_ok);
        CHECK(result.valid == 1u, "loopback decode must pass");
        CHECK(result.payload_length == (uint8_t)sizeof(payload),
              "payload length mismatch");
        CHECK(result.sequence == 0x21u, "sequence mismatch");
        CHECK(memcmp(result.payload, payload, sizeof(payload)) == 0,
              "payload bytes mismatch");
    }
    printf("PASS\n");
    return 0;
}
