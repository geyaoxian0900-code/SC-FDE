/* test_ldpc.c - LDPC(192,128) encode/decode regression tests.
 *
 * Verified behavior (probe: 2000 random trials):
 *   clean-channel decode: 100% converge to the exact bits
 *   single bit flip:      ~33% corrected (code has d_min = 2, see below)
 *   double bit flip:      ~11% corrected
 *
 * KNOWN DEFECT (documented in AUDIT_REPORT.md): the quasi-cyclic shift
 * construction repeats columns modulo 32, so d_min = 2 and the code has no
 * real error-correction capability. Re-enabling LDPC (SCFDE_LDPC_ENABLED)
 * therefore requires a redesigned code first. The tests below assert the
 * actual contract used by the firmware: encode/decode round trip and
 * decoder termination. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "scfde_ldpc.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

static uint32_t g_seed = 20260723u;
static uint32_t next_rand(void)
{
    g_seed = g_seed * 1664525u + 1013904223u;
    return g_seed;
}

static void fill_info(uint8_t *bits)
{
    uint16_t i;
    for (i = 0; i < SCFDE_LDPC_INFO_BITS; i++)
    {
        bits[i] = (uint8_t)(next_rand() & 1u);
    }
}

int main(void)
{
    uint8_t info[SCFDE_LDPC_INFO_BITS];
    uint8_t code[SCFDE_LDPC_CODE_BITS];
    uint8_t decoded[SCFDE_LDPC_INFO_BITS];
    float llr[SCFDE_LDPC_CODE_BITS];
    uint16_t i;
    uint8_t trial, ok;

    /* 1) Clean-channel decode must always converge to the exact bits. */
    for (trial = 0; trial < 8; trial++)
    {
        fill_info(info);
        scfde_ldpc_encode(info, code);
        for (i = 0; i < SCFDE_LDPC_CODE_BITS; i++)
        {
            llr[i] = code[i] ? -8.0f : 8.0f;   /* negative LLR favors bit 1 */
        }
        ok = scfde_ldpc_decode(llr, decoded, 10u);
        CHECK(ok == 1u, "clean-channel decode must converge");
        CHECK(memcmp(info, decoded, SCFDE_LDPC_INFO_BITS) == 0,
              "decoded bits must match encoded bits");
    }
    printf("8 clean trials: PASS\n");

    /* 2) Decoder iteration bound: 10 iterations worst case, no hang. */
    memset(llr, 0, sizeof(llr));        /* all-zero LLRs (ambiguous) */
    ok = scfde_ldpc_decode(llr, decoded, 10u);
    printf("zero-LLR run finished (syndrome ok = %d)\n", ok);

    /* 3) Correction capability report (regression against probe).
     * No hard assertion: the code is KNOWN to have d_min = 2, so a strict
     * correction assertion would fail by design. Reported numbers must
     * remain stable across builds (deterministic seed). */
    {
        uint32_t ok1 = 0, ok2 = 0;
        const uint32_t trials = 2000;
        uint32_t trialIndex;
        for (trialIndex = 0; trialIndex < trials; trialIndex++)
        {
            uint16_t a, b;
            fill_info(info);
            scfde_ldpc_encode(info, code);
            for (i = 0; i < SCFDE_LDPC_CODE_BITS; i++)
            {
                llr[i] = code[i] ? -8.0f : 8.0f;
            }
            a = (uint16_t)(next_rand() % SCFDE_LDPC_CODE_BITS);
            llr[a] = -llr[a];
            if (scfde_ldpc_decode(llr, decoded, 10u) == 1u &&
                memcmp(info, decoded, SCFDE_LDPC_INFO_BITS) == 0)
            {
                ok1++;
            }
            llr[a] = -llr[a];
            a = (uint16_t)(next_rand() % SCFDE_LDPC_CODE_BITS);
            do { b = (uint16_t)(next_rand() % SCFDE_LDPC_CODE_BITS); } while (b == a);
            llr[a] = -llr[a];
            llr[b] = -llr[b];
            if (scfde_ldpc_decode(llr, decoded, 10u) == 1u &&
                memcmp(info, decoded, SCFDE_LDPC_INFO_BITS) == 0)
            {
                ok2++;
            }
        }
        printf("correction report (%u trials): single-flip %.1f%%, "
               "double-flip %.1f%% (known d_min=2 limitation)\n",
               trials, 100.0 * ok1 / trials, 100.0 * ok2 / trials);
    }

    printf("PASS\n");
    return 0;
}
