/* test_turbo.c - Chapter-4 turbo core: conv code, interleaver, BCJR
 * Log-MAP, and the full turbo-mode digital loopback. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "scfde_modem.h"
#include "scfde_turbo.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

#define LOOPBACK_LEN (SCFDE_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL)

static uint16_t g_loopback[LOOPBACK_LEN];

static void prepare_loopback(const uint8_t *payload, uint8_t length, uint8_t seq)
{
    uint32_t index;
    scfde_modem_prepare_tx_turbo(payload, length, seq);
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
    uint8_t info[SCFDE_TURBO_INFO_BITS];
    uint8_t coded[SCFDE_TURBO_CODE_BITS];
    uint8_t inter[SCFDE_TURBO_CODE_BITS];
    uint8_t info_out[SCFDE_TURBO_INFO_BITS];
    float llr[SCFDE_TURBO_CODE_BITS];
    float info_llr[SCFDE_TURBO_INFO_BITS];
    uint16_t i;

    scfde_modem_init();

    /* 1) Conv encode + interleave round trip through BCJR (clean LLRs). */
    for (i = 0; i < SCFDE_TURBO_INFO_BITS; i++) info[i] = (uint8_t)(i % 7u == 0u);
    scfde_turbo_conv_encode(info, coded);
    scfde_turbo_interleave(coded, inter);
    for (i = 0; i < SCFDE_TURBO_CODE_BITS; i++) llr[i] = inter[i] ? 8.0f : -8.0f;
    scfde_turbo_deinterleave(llr, llr);
    scfde_turbo_bcjr(llr, info_llr, info_out, 0u);
    CHECK(memcmp(info, info_out, SCFDE_TURBO_INFO_BITS) == 0,
          "clean BCJR decode must recover the info bits");
    printf("conv+interleave+BCJR clean round trip: PASS\n");

    /* 2) Two coded-bit flips must be corrected (dfree=5). */
    for (i = 0; i < SCFDE_TURBO_CODE_BITS; i++) llr[i] = inter[i] ? 8.0f : -8.0f;
    llr[5] = -llr[5];
    llr[137] = -llr[137];
    scfde_turbo_deinterleave(llr, llr);
    scfde_turbo_bcjr(llr, info_llr, info_out, 0u);
    CHECK(memcmp(info, info_out, SCFDE_TURBO_INFO_BITS) == 0,
          "two coded-bit flips must be corrected");
    printf("2-bit-flip BCJR correction: PASS\n");

    /* 3) Max-Log-MAP variant on clean LLRs. */
    for (i = 0; i < SCFDE_TURBO_CODE_BITS; i++) llr[i] = inter[i] ? 8.0f : -8.0f;
    scfde_turbo_deinterleave(llr, llr);
    scfde_turbo_bcjr(llr, info_llr, info_out, 1u);
    CHECK(memcmp(info, info_out, SCFDE_TURBO_INFO_BITS) == 0,
          "Max-Log-MAP clean decode must recover the info bits");
    printf("Max-Log-MAP clean round trip: PASS\n");

    /* 4) Full turbo-mode digital loopback. */
    {
        const uint8_t payload[] = {'T', 'U', 'R', 'B', 'O', '1'};
        scfde_rx_result_t result;
        prepare_loopback(payload, (uint8_t)sizeof(payload), 0x42u);
        result = scfde_modem_decode_turbo(g_loopback, LOOPBACK_LEN);
        printf("turbo loopback: valid=%u sync=%.3f len=%u seq=%u\n",
               result.valid, result.sync_metric, result.payload_length,
               result.sequence);
        CHECK(result.valid == 1u, "turbo loopback must decode");
        CHECK(result.payload_length == (uint8_t)sizeof(payload),
              "turbo payload length mismatch");
        CHECK(result.sequence == 0x42u, "turbo sequence mismatch");
        CHECK(memcmp(result.payload, payload, sizeof(payload)) == 0,
              "turbo payload bytes mismatch");
    }

    printf("PASS\n");
    return 0;
}
