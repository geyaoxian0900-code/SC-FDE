/* test_export_golden.c - C-side golden-vector exporter (mirror of
 * golden_vectors/export_golden_vectors.m, see FORMAT.md).
 *
 * Compiles the real firmware sources with the static-include trick so every
 * internal stage (UW, frame symbols, channel estimate, equalized symbols,
 * LLR) is dumped from the actual firmware implementation, not a replica.
 * The RX orchestration (phase search -> CFO -> LS -> MMSE) is transcribed
 * here from scfde_modem.c and cross-checked against scfde_modem_decode(). */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define static
#include "scfde_fft.c"
#include "scfde_ldpc.c"
#include "scfde_equalizer.c"
#include "scfde_turbo.c"
#include "scfde_modem.c"
#undef static

#define OUT_LEN   2816u                     /* 2304 frame + 512 tail zeros */
#define TX_LEN    (SCFDE_FRAME_SYMBOLS * SCFDE_TX_SAMPLES_PER_SYMBOL)

static uint16_t g_capture[OUT_LEN];
static uint8_t g_packet[SCFDE_PACKET_BYTES];

/* ---------------- binary writers (little-endian) ---------------- */

static void w_u8(FILE *f, const uint8_t *v, uint32_t n) { fwrite(v, 1, n, f); }

static void w_u16(FILE *f, const uint16_t *v, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++)
    {
        fputc(v[i] & 0xFFu, f);
        fputc((v[i] >> 8u) & 0xFFu, f);
    }
}

static void w_f32(FILE *f, const float *v, uint32_t n)
{
    fwrite(v, sizeof(float), n, f);
}

static void w_cplx(FILE *f, const scfde_complex_t *v, uint32_t n)
{
    uint32_t i;
    float pair[2];
    for (i = 0; i < n; i++)
    {
        pair[0] = v[i].re;
        pair[1] = v[i].im;
        fwrite(pair, sizeof(float), 2, f);
    }
}

static FILE *open_out(const char *dir, const char *name)
{
    char path[512];
    FILE *f;
    snprintf(path, sizeof(path), "%s/%s", dir, name);
    f = fopen(path, "wb");
    if (f == NULL) { printf("FAIL: cannot open %s\n", path); exit(1); }
    return f;
}

static void pack_bits(FILE *f, const uint8_t *bits, uint32_t count)
{
    uint32_t byte, bit;
    uint8_t value;
    for (byte = 0; byte < (count + 7u) / 8u; byte++)
    {
        value = 0u;
        for (bit = 0; bit < 8u; bit++)
        {
            uint32_t src = byte * 8u + bit;
            if ((src < count) && bits[src]) value |= (uint8_t)(1u << bit);
        }
        fputc(value, f);
    }
}

/* ---------------- stage helpers ---------------- */

static void build_packet(const uint8_t *payload, uint8_t length, uint8_t seq)
{
    uint16_t crc;
    memset(g_packet, 0, sizeof(g_packet));
    g_packet[0] = 0xA5u; g_packet[1] = 0x5Au;
    g_packet[2] = length; g_packet[3] = seq;
    if (length > 0u) memcpy(&g_packet[4], payload, length);
    crc = scfde_crc16_ccitt(g_packet, SCFDE_PACKET_CRC_INDEX);
    g_packet[SCFDE_PACKET_CRC_INDEX] = (uint8_t)(crc >> 8u);
    g_packet[SCFDE_PACKET_CRC_INDEX + 1u] = (uint8_t)crc;
}

static void build_capture(void)
{
    uint32_t index;
    for (index = 0; index < OUT_LEN; index++)
    {
        int32_t code = 2048;
        if (index < (SCFDE_FRAME_SYMBOLS * SCFDE_RX_SAMPLES_PER_SYMBOL))
        {
            code = 2048 + (int32_t)scfde_modem_get_tx_sample(index * 2u);
        }
        if (code < 0) code = 0;
        else if (code > 4095) code = 4095;
        g_capture[index] = (uint16_t)code;
    }
}

int main(int argc, char **argv)
{
    const char *out_dir = (argc > 1) ? argv[1] : "c_export";
    const uint8_t payload[] = {'S','C','-','F','D','E','1','2','3','4'};
    uint8_t qpsk_bits[SCFDE_DATA_SYMBOLS * 2u];
    uint8_t hard_bits[SCFDE_DATA_SYMBOLS * 2u];
    uint8_t rx_packet[SCFDE_PACKET_BYTES];
    float llr[SCFDE_LDPC_CODE_BITS];
    scfde_complex_t frame[SCFDE_FRAME_SYMBOLS];
    scfde_complex_t downconverted[OUT_LEN];
    scfde_complex_t integrated[OUT_LEN / SCFDE_RX_SAMPLES_PER_SYMBOL + 1u];
    scfde_complex_t block_copy[SCFDE_FFT_SIZE];
    float phase_angles[SCFDE_FRAME_SYMBOLS];
    float frequency_offset_hz;
    float start_rate, end_rate;
    float regularization;
    uint32_t best_sample = 0u;
    float best_metric = 0.0f;
    uint32_t sample_index, i;
    uint8_t phase;
    FILE *f;
    char text[SCFDE_MAX_PAYLOAD + 1u];

    scfde_modem_init();
    scfde_modem_set_equalizer(SCFDE_EQUALIZER_MMSE_FDE);

    /* ---- TX side ---- */
    build_packet(payload, (uint8_t)sizeof(payload), 0x00u);
    scfde_modem_prepare_tx(payload, (uint8_t)sizeof(payload), 0x00u);

    /* stage 01: packet bytes */
    f = open_out(out_dir, "01_packet_bytes.bin"); w_u8(f, g_packet, SCFDE_PACKET_BYTES); fclose(f);

    /* stage 02: QPSK input bits (192, unpacked from the packet) */
    for (i = 0; i < (SCFDE_DATA_SYMBOLS * 2u); i++)
    {
        qpsk_bits[i] = (uint8_t)((g_packet[i >> 3u] >> (i & 7u)) & 1u);
    }
    f = open_out(out_dir, "02_qpsk_input_bits.bin");
    pack_bits(f, qpsk_bits, SCFDE_DATA_SYMBOLS * 2u);
    fclose(f);

    /* stage 03: modulated symbols (real g_tx_data) */
    f = open_out(out_dir, "03_modulated_symbols.bin"); w_cplx(f, g_tx_data, SCFDE_DATA_SYMBOLS); fclose(f);

    /* stage 04: UW (real g_uw) */
    f = open_out(out_dir, "04_uw.bin"); w_cplx(f, g_uw, SCFDE_UW_LENGTH); fclose(f);

    /* stage 05: full frame symbols (replica of scfde_get_tx_symbol) */
    for (i = 0; i < SCFDE_FRAME_SYMBOLS; i++)
    {
        if (i < 2u * SCFDE_UW_LENGTH) frame[i] = g_uw[i % SCFDE_UW_LENGTH];
        else if (i < 2u * SCFDE_UW_LENGTH + SCFDE_DATA_SYMBOLS) frame[i] = g_tx_data[i - 2u * SCFDE_UW_LENGTH];
        else frame[i] = g_uw[i - 2u * SCFDE_UW_LENGTH - SCFDE_DATA_SYMBOLS];
    }
    f = open_out(out_dir, "05_frame_symbols.bin"); w_cplx(f, frame, SCFDE_FRAME_SYMBOLS); fclose(f);

    /* stage 06: 96 kHz baseband (rectangular hold, complex) */
    {
        static scfde_complex_t baseband[TX_LEN];
        for (i = 0; i < TX_LEN; i++) baseband[i] = frame[i / SCFDE_TX_SAMPLES_PER_SYMBOL];
        f = open_out(out_dir, "06_tx_baseband_96k.bin"); w_cplx(f, baseband, TX_LEN); fclose(f);
    }

    /* stage 07: 96 kHz passband (real firmware samples) as float32 */
    {
        int16_t passband[TX_LEN];
        float sample;
        for (i = 0; i < TX_LEN; i++)
        {
            passband[i] = scfde_modem_get_tx_sample((uint32_t)i);
        }
        f = open_out(out_dir, "07_passband_tx_96k.bin");
        for (i = 0; i < TX_LEN; i++)
        {
            sample = (float)passband[i];
            fwrite(&sample, sizeof(float), 1, f);
        }
        fclose(f);
    }

    /* stage 08: 48 kHz ADC codes */
    build_capture();
    f = open_out(out_dir, "08_adc_capture.bin"); w_u16(f, g_capture, OUT_LEN); fclose(f);

    /* ---- RX side (transcription of scfde_modem_decode stages) ---- */
    {
        float midpoint = 0.0f;
        for (i = 0; i < OUT_LEN; i++) midpoint += (float)g_capture[i];
        midpoint /= (float)OUT_LEN;

        /* stage 09: downconverted complex baseband (4-point LO, replica) */
        for (sample_index = 0; sample_index < OUT_LEN; sample_index++)
        {
            static const int8_t cos4[4] = {1, 0, -1, 0};
            static const int8_t sin4[4] = {0, 1, 0, -1};
            float value = (float)g_capture[sample_index] - midpoint;
            uint8_t carrier = (uint8_t)(sample_index & 3u);
            downconverted[sample_index].re = value * (float)cos4[carrier];
            downconverted[sample_index].im = -value * (float)sin4[carrier];
        }
        f = open_out(out_dir, "09_downconverted.bin"); w_cplx(f, downconverted, OUT_LEN); fclose(f);

        /* phase search (same code as scfde_modem_decode) */
        for (phase = 0u; phase < SCFDE_RX_SAMPLES_PER_SYMBOL; phase++)
        {
            uint32_t symbol_count = (OUT_LEN - phase) / SCFDE_RX_SAMPLES_PER_SYMBOL;
            uint32_t symbol;
            if (symbol_count > SCFDE_MAX_RX_SYMBOLS) symbol_count = SCFDE_MAX_RX_SYMBOLS;
            for (symbol = 0u; symbol < symbol_count; symbol++)
            {
                float in_phase = 0.0f, quadrature = 0.0f;
                uint8_t k;
                uint32_t start = phase + symbol * SCFDE_RX_SAMPLES_PER_SYMBOL;
                for (k = 0u; k < SCFDE_RX_SAMPLES_PER_SYMBOL; k++)
                {
                    static const int8_t cos4[4] = {1, 0, -1, 0};
                    static const int8_t sin4[4] = {0, 1, 0, -1};
                    uint32_t idx = start + k;
                    float value = (float)g_capture[idx] - midpoint;
                    uint8_t carrier = (uint8_t)(idx & 3u);
                    in_phase += value * (float)cos4[carrier];
                    quadrature -= value * (float)sin4[carrier];
                }
                g_phase_symbols[symbol].re = in_phase;
                g_phase_symbols[symbol].im = quadrature;
            }
            if (symbol_count >= SCFDE_FRAME_SYMBOLS)
            {
                uint32_t offset;
                for (offset = 0u; offset <= (symbol_count - SCFDE_FRAME_SYMBOLS); offset++)
                {
                    float metric = scfde_sync_metric(&g_phase_symbols[offset]);
                    if (metric > best_metric)
                    {
                        best_metric = metric;
                        best_sample = phase + offset * SCFDE_RX_SAMPLES_PER_SYMBOL;
                        memcpy(g_frame_symbols, &g_phase_symbols[offset], sizeof(g_frame_symbols));
                    }
                }
            }
        }

        /* stage 10: integrated symbols at phase 0 (re-run of the I&D only;
         * the phase search above ends with phase 11 in g_phase_symbols). */
        {
            uint32_t count = OUT_LEN / SCFDE_RX_SAMPLES_PER_SYMBOL;
            for (i = 0; i < count; i++)
            {
                float in_phase = 0.0f, quadrature = 0.0f;
                uint8_t k;
                for (k = 0u; k < SCFDE_RX_SAMPLES_PER_SYMBOL; k++)
                {
                    static const int8_t cos4[4] = {1, 0, -1, 0};
                    static const int8_t sin4[4] = {0, 1, 0, -1};
                    uint32_t idx = i * SCFDE_RX_SAMPLES_PER_SYMBOL + k;
                    float value = (float)g_capture[idx] - midpoint;
                    uint8_t carrier = (uint8_t)(idx & 3u);
                    in_phase += value * (float)cos4[carrier];
                    quadrature -= value * (float)sin4[carrier];
                }
                integrated[i].re = in_phase;
                integrated[i].im = quadrature;
            }
            f = open_out(out_dir, "10_integrated_symbols.bin");
            w_cplx(f, integrated, count);
            fclose(f);
        }
    }

    /* stage 11: sync result + CFO */
    scfde_estimate_frequency_offsets(&start_rate, &end_rate);
    frequency_offset_hz = 0.5f * (start_rate + end_rate) *
                          (float)SCFDE_SYMBOL_RATE_HZ / (2.0f * SCFDE_PI);
    {
        FILE *f = open_out(out_dir, "11_sync_result.txt");
        fprintf(f, "%lu\n%.6f\n%.3f\n",
                (unsigned long)best_sample, best_metric, frequency_offset_hz);
        fclose(f);
    }

    /* stage 12: phase correction angles (formula replica) */
    {
        float slope = (end_rate - start_rate) / (float)(SCFDE_FRAME_SYMBOLS - 1u);
        for (i = 0u; i < SCFDE_FRAME_SYMBOLS; i++)
        {
            float s = (float)i;
            phase_angles[i] = start_rate * s + 0.5f * slope * s * s;
        }
        f = open_out(out_dir, "12_phase_correction.bin"); w_f32(f, phase_angles, SCFDE_FRAME_SYMBOLS); fclose(f);
    }

    /* stage 13: corrected symbols (real firmware buffer) */
    scfde_correct_frequency_offset(start_rate, end_rate);
    f = open_out(out_dir, "13_corrected_symbols.bin"); w_cplx(f, g_frame_symbols, SCFDE_FRAME_SYMBOLS); fclose(f);

    /* stage 14/15: channel impulse (real) and frequency response (real) */
    regularization = scfde_build_channel_response();
    f = open_out(out_dir, "14_channel_impulse.bin"); w_cplx(f, g_fft_b, SCFDE_UW_LENGTH); fclose(f);
    f = open_out(out_dir, "15_channel_response.bin"); w_cplx(f, g_fft_a, SCFDE_FFT_SIZE); fclose(f);

    /* stage 16/17: FDE block input and its FFT output */
    for (i = 0; i < SCFDE_FFT_SIZE; i++)
    {
        block_copy[i] = g_frame_symbols[2u * SCFDE_UW_LENGTH + i];
    }
    f = open_out(out_dir, "16_fft_block_in.bin"); w_cplx(f, block_copy, SCFDE_FFT_SIZE); fclose(f);
    scfde_fft(block_copy, SCFDE_FFT_SIZE, 0u);
    f = open_out(out_dir, "17_fft_block_out.bin"); w_cplx(f, block_copy, SCFDE_FFT_SIZE); fclose(f);

    /* stage 18: MMSE-FDE output (real) */
    scfde_equalize_data(regularization, SCFDE_EQUALIZER_MMSE_FDE);
    f = open_out(out_dir, "18_equalized_symbols.bin"); w_cplx(f, g_fft_b, SCFDE_DATA_SYMBOLS); fclose(f);

    /* stage 19: LLR (same formula as the firmware demodulator) */
    for (i = 0; i < SCFDE_LDPC_CODE_BITS; i++)
    {
        uint16_t sym = (uint16_t)(i / 2u);
        if ((i & 1u) == 0u) llr[i] = -g_fft_b[sym].re;
        else llr[i] = -g_fft_b[sym].im;
    }
    f = open_out(out_dir, "19_ldpc_llr.bin"); w_f32(f, llr, SCFDE_LDPC_CODE_BITS); fclose(f);

    /* stage 20: hard-decision bits (baseline: component sign, bit 1 = +) */
    for (i = 0; i < (SCFDE_DATA_SYMBOLS * 2u); i++)
    {
        uint16_t sym = (uint16_t)(i / 2u);
        float value = ((i & 1u) == 0u) ? g_fft_b[sym].re : g_fft_b[sym].im;
        hard_bits[i] = (value > 0.0f) ? 1u : 0u;
    }
    f = open_out(out_dir, "20_decoded_bits.bin");
    pack_bits(f, hard_bits, SCFDE_DATA_SYMBOLS * 2u);
    fclose(f);

    /* stage 21: received packet (real firmware demodulator) */
    if (scfde_demodulate_packet(rx_packet) == 0u)
    {
        printf("FAIL: demodulator rejected the packet\n");
        return 1;
    }
    f = open_out(out_dir, "21_rx_packet.bin"); w_u8(f, rx_packet, SCFDE_PACKET_BYTES); fclose(f);

    /* stage 22: CRC result */
    {
        uint8_t header_ok = (rx_packet[0] == 0xA5u) && (rx_packet[1] == 0x5Au) &&
                            (rx_packet[2] <= SCFDE_MAX_PAYLOAD);
        uint16_t crc = (uint16_t)(((uint16_t)rx_packet[SCFDE_PACKET_CRC_INDEX] << 8u) |
                                  rx_packet[SCFDE_PACKET_CRC_INDEX + 1u]);
        uint8_t crc_ok = (scfde_crc16_ccitt(rx_packet, SCFDE_PACKET_CRC_INDEX) == crc);
        uint8_t valid = header_ok && crc_ok;
        int32_t bit_errors = 0;
        for (i = 0; i < SCFDE_PACKET_BYTES; i++)
        {
            uint8_t d = (uint8_t)(rx_packet[i] ^ g_packet[i]);
            for (phase = 0; phase < 8u; phase++)
            {
                if (d & (1u << phase)) bit_errors++;
            }
        }
        f = open_out(out_dir, "22_crc_result.txt");
        fprintf(f, "%d\n%d\n%d\n%ld\n", header_ok, crc_ok, valid, (long)bit_errors);
        fclose(f);
    }

    /* stage 23: final text */
    {
        uint8_t len = rx_packet[2];
        if (len > SCFDE_MAX_PAYLOAD) len = SCFDE_MAX_PAYLOAD;
        memcpy(text, &rx_packet[4], len);
        text[len] = '\0';
        f = open_out(out_dir, "23_final_text.txt");
        fprintf(f, "%s", text);
        fclose(f);
    }

    /* Cross-check the orchestration against the real public decode API. */
    {
        scfde_rx_result_t result = scfde_modem_decode(g_capture, OUT_LEN);
        printf("cross-check: valid=%u start=%lu metric=%.4f CFO=%.2f Hz\n",
               result.valid, (unsigned long)result.frame_start_sample,
               result.sync_metric, result.frequency_offset_hz);
        if (result.valid != 1u) { printf("FAIL: real decode failed\n"); return 1; }
        if (result.frame_start_sample != best_sample) { printf("FAIL: sync start mismatch\n"); return 1; }
        if (memcmp(result.payload, payload, sizeof(payload)) != 0) { printf("FAIL: payload mismatch\n"); return 1; }
    }

    printf("Golden vectors written to %s\n", out_dir);
    printf("PASS\n");
    return 0;
}
