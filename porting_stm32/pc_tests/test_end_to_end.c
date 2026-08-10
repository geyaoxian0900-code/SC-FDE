/* test_end_to_end.c - Baseline scheme full digital loopback through the real
 * firmware API (scfde_modem_prepare_tx + get_tx_sample + decode).
 *
 * Baseline = MMSE-FDE only, LDPC off (SCFDE_LDPC_ENABLED 0). The decoder is
 * fixed to MMSE regardless of the configured equalizer mode, so every mode
 * setting must report MMSE-FDE and pass. Mirrors scfde_app.c
 * app_prepare_loopback(). */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "scfde_modem.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

#define LOOPBACK_LEN (SCFDE_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)

static uint16_t g_loopback[LOOPBACK_LEN];

static void prepare_loopback(const uint8_t *payload, uint8_t length, uint8_t seq)
{
    uint32_t index;
    scfde_modem_prepare_tx(payload, length, seq);
    for (index = 0; index < LOOPBACK_LEN; index++)
    {
        int32_t adc = 2048 + (int32_t)scfde_modem_get_tx_sample(index * 2u);
        if (adc < 0) adc = 0;
        else if (adc > 4095) adc = 4095;
        g_loopback[index] = (uint16_t)adc;
    }
}

int main(void)
{
    const uint8_t payload10[] = {'S', 'C', '-', 'F', 'D', 'E', '1', '2', '3', '4'};
    const uint8_t payload18[] = {'0','1','2','3','4','5','6','7','8','9',
                                 'A','B','C','D','E','F','G','H'};
    scfde_equalizer_mode_t mode;

    scfde_modem_init();   /* builds the Chu UW and FFT tables */

    /* 1) Every equalizer mode must decode the digital loopback cleanly
     * and report itself as the equalizer that ran. */
    for (mode = SCFDE_EQUALIZER_AUTO; mode < SCFDE_EQUALIZER_COUNT;
         mode = (scfde_equalizer_mode_t)((uint8_t)mode + 1u))
    {
        scfde_rx_result_t result;
        prepare_loopback(payload10, (uint8_t)sizeof(payload10), 0x77u);
        scfde_modem_set_equalizer(mode);
        result = scfde_modem_decode(g_loopback, LOOPBACK_LEN);
        printf("mode=%-12s: valid=%u sync=%.3f start=%lu eq=%s len=%u\n",
               scfde_equalizer_name(mode), result.valid, result.sync_metric,
               (unsigned long)result.frame_start_sample,
               scfde_equalizer_name(result.equalizer_used), result.payload_length);
        CHECK(result.valid == 1u, "loopback decode must pass");
        CHECK(result.equalizer_used == mode,
              "reported equalizer must match the selected mode");
        CHECK(result.payload_length == (uint8_t)sizeof(payload10),
              "payload length mismatch");
        CHECK(result.sequence == 0x77u, "sequence mismatch");
        CHECK(memcmp(result.payload, payload10, sizeof(payload10)) == 0,
              "payload bytes mismatch");
    }

    /* 2) Full 18-byte payload (baseline maximum). */
    {
        scfde_rx_result_t result;
        prepare_loopback(payload18, (uint8_t)sizeof(payload18), 0x01u);
        result = scfde_modem_decode(g_loopback, LOOPBACK_LEN);
        printf("payload18: valid=%u len=%u\n", result.valid, result.payload_length);
        CHECK(result.valid == 1u, "18-byte payload loopback must pass");
        CHECK(result.payload_length == (uint8_t)sizeof(payload18),
              "18-byte payload length mismatch");
        CHECK(memcmp(result.payload, payload18, sizeof(payload18)) == 0,
              "18-byte payload bytes mismatch");
    }

    printf("PASS\n");
    return 0;
}
