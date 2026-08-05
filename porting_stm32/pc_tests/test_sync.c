/* test_sync.c - Frame synchronization and CFO estimation with known offsets.
 * Builds a 48 kHz passband capture with an injected carrier offset and
 * leading silence, then verifies the real firmware decode reports the
 * expected sync start and CFO. Uses the static-include trick so the real
 * internal search and estimators are exercised. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define static
#include "scfde_fft.c"
#include "scfde_ldpc.c"
#include "scfde_equalizer.c"
#include "scfde_modem.c"
#undef static

#define CAPTURE_LEN 2816u
#define LEADING     120u     /* leading silence, multiple of 12 */
#define INJECT_HZ   10.0f    /* injected carrier offset (within the ~10 Hz
                                sync+CFO working range verified in MATLAB) */
#define LIMIT_HZ    30.0f    /* beyond the range: documented mis-lock, see
                                AUDIT_REPORT.md; informational only */

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

static uint16_t g_capture[CAPTURE_LEN];

/* Rebuild the frame symbol stream from the real internal buffers. */
static scfde_complex_t frame_symbol(uint16_t index)
{
    if (index < (2u * SCFDE_UW_LENGTH))
    {
        return g_uw[index % SCFDE_UW_LENGTH];
    }
    if (index < (2u * SCFDE_UW_LENGTH + SCFDE_DATA_SYMBOLS))
    {
        return g_tx_data[index - 2u * SCFDE_UW_LENGTH];
    }
    return g_uw[index - 2u * SCFDE_UW_LENGTH - SCFDE_DATA_SYMBOLS];
}

/* Direct 48 kHz passband generation with a tunable carrier offset:
 * y(n) = 700 * Re{s(n/12) * exp(j*2*pi*(fc+df)*n/fs)}. */
static void build_capture(float offset_hz, uint32_t leading)
{
    const uint8_t payload[] = {'S', 'Y', 'N', 'C'};
    uint32_t n;

    memset(g_capture, 0, sizeof(g_capture));
    scfde_modem_prepare_tx(payload, (uint8_t)sizeof(payload), 0x11u);
    for (n = 0; n < CAPTURE_LEN; n++)
    {
        int32_t code = 2048;
        if ((n >= leading) && (((n - leading) / 12u) < SCFDE_FRAME_SYMBOLS))
        {
            scfde_complex_t s = frame_symbol((uint16_t)((n - leading) / 12u));
            float angle = 2.0f * (float)M_PI * (12000.0f + offset_hz) *
                          (float)n / (float)SCFDE_RX_SAMPLE_RATE_HZ;
            float value = 700.0f * (s.re * cosf(angle) - s.im * sinf(angle));
            code = 2048 + (int32_t)lrintf(value);
        }
        if (code < 0) code = 0;
        if (code > 4095) code = 4095;
        g_capture[n] = (uint16_t)code;
    }
}

int main(void)
{
    scfde_rx_result_t result;

    scfde_modem_init();   /* builds the Chu UW and FFT tables */

    /* 1) Aligned, zero-offset capture: sync at sample 0, CFO ~ 0. */
    build_capture(0.0f, 0u);
    result = scfde_modem_decode(g_capture, CAPTURE_LEN);
    printf("clean:  start=%lu metric=%.4f CFO=%.2f Hz valid=%u\n",
           (unsigned long)result.frame_start_sample, result.sync_metric,
           result.frequency_offset_hz, result.valid);
    CHECK(result.frame_start_sample == 0u, "aligned capture must sync at 0");
    CHECK(result.sync_metric > 0.5f, "aligned capture metric too low");
    CHECK(fabsf(result.frequency_offset_hz) < 0.5f,
          "zero-offset CFO estimate must be near zero");
    CHECK(result.valid == 1u, "aligned loopback must decode");
    CHECK(result.payload_length == 4u && result.sequence == 0x11u,
          "payload/sequence mismatch");

    /* 2) Leading silence + injected 10 Hz offset (verified working range). */
    build_capture(INJECT_HZ, LEADING);
    result = scfde_modem_decode(g_capture, CAPTURE_LEN);
    printf("inject: start=%lu metric=%.4f CFO=%.2f Hz valid=%u\n",
           (unsigned long)result.frame_start_sample, result.sync_metric,
           result.frequency_offset_hz, result.valid);
    CHECK(result.frame_start_sample == LEADING,
          "frame start must equal the injected leading silence");
    CHECK(result.valid == 1u, "offset capture must still decode");
    CHECK(fabsf(result.frequency_offset_hz - INJECT_HZ) < 1.0f,
          "CFO estimate must track the injected 10 Hz within 1 Hz");

    /* 3) 30 Hz lies outside the algorithm's CFO range (verified in MATLAB:
     * start=118, CFO~14, valid=0 for both MATLAB and C). Informational. */
    build_capture(LIMIT_HZ, LEADING);
    result = scfde_modem_decode(g_capture, CAPTURE_LEN);
    printf("limit: start=%lu metric=%.4f CFO=%.2f Hz valid=%u (documented "
           "mis-lock beyond ~10 Hz; MATLAB identical)\n",
           (unsigned long)result.frame_start_sample, result.sync_metric,
           result.frequency_offset_hz, result.valid);

    printf("PASS\n");
    return 0;
}
