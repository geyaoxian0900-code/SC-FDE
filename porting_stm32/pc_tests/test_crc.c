/* test_crc.c - CRC-16/CCITT validation against the standard test vector and
 * the MATLAB golden packet bytes. Compiles the real firmware source with the
 * static-include trick so the actual scfde_crc16_ccitt() is tested. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define static
#include "scfde_fft.c"
#include "scfde_ldpc.c"
#include "scfde_equalizer.c"
#include "scfde_modem.c"
#undef static

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

int main(void)
{
    static const uint8_t std_vector[] = "123456789";  /* 9 bytes, no NUL */
    uint16_t crc = scfde_crc16_ccitt(std_vector, 9u);
    printf("CRC-16/CCITT(\"123456789\") = 0x%04X (expect 0x29B1)\n", crc);
    CHECK(crc == 0x29B1u, "standard CCITT test vector mismatch");

    /* Golden packet: A5 5A 0A 00 'SC-FDE1234' + CRC16. CRC bytes must be the
     * high-then-low order used by both MATLAB and the firmware. */
    uint8_t packet[SCFDE_PACKET_BYTES];
    const uint8_t payload[] = {'S', 'C', '-', 'F', 'D', 'E', '1', '2', '3', '4'};
    memset(packet, 0, sizeof(packet));
    packet[0] = 0xA5u; packet[1] = 0x5Au;
    packet[2] = (uint8_t)sizeof(payload); packet[3] = 0x00u;
    memcpy(&packet[4], payload, sizeof(payload));
    crc = scfde_crc16_ccitt(packet, SCFDE_PACKET_CRC_INDEX);
    packet[SCFDE_PACKET_CRC_INDEX]     = (uint8_t)(crc >> 8u);
    packet[SCFDE_PACKET_CRC_INDEX + 1] = (uint8_t)crc;
    printf("Golden packet CRC16 = 0x%04X (MATLAB exports the same bytes)\n", crc);
    CHECK(scfde_crc16_ccitt(packet, SCFDE_PACKET_CRC_INDEX) == crc,
          "self-check CRC failed");

    printf("PASS\n");
    return 0;
}
