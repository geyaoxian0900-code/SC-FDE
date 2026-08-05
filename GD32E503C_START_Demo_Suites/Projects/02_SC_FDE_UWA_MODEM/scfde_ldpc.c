#include "scfde_ldpc.h"
#include <string.h>

/**
 * @file scfde_ldpc.c
 * @brief Embedded systematic (192,128) sparse code and min-sum decoder.
 *
 * The parity-check matrix has 64 rows. Each row touches four information
 * bits and its own systematic parity bit, for 320 graph edges. A compact
 * quasi-cyclic shift table generates the graph instead of storing a matrix.
 * This is a project-specific short LDPC, not a DVB-S2 or 5G base graph.
 */

#define LDPC_INFO_BLOCK 32u
#define LDPC_CHECKS 64u
#define LDPC_INFO_DEGREE 4u
#define LDPC_EDGE_COUNT (LDPC_CHECKS * (LDPC_INFO_DEGREE + 1u))

static const uint8_t g_shifts[2][LDPC_INFO_DEGREE] = {
    {0u, 5u, 11u, 17u},
    {1u, 7u, 13u, 19u}
};

static uint16_t ldpc_info_index(uint16_t check, uint8_t block)
{
    uint16_t row = check & 31u;
    uint8_t group = (check >= 32u) ? 1u : 0u;
    /* Four 32-bit information blocks use one of two circulant-shift groups. */
    return (uint16_t)(block * LDPC_INFO_BLOCK + ((row + g_shifts[group][block]) & 31u));
}

static uint8_t ldpc_check_sum(const uint8_t *bits, uint16_t check)
{
    uint8_t sum = 0u;
    uint8_t block;
    for(block = 0u; block < LDPC_INFO_DEGREE; block++)
    {
        sum ^= bits[ldpc_info_index(check, block)];
    }
    return sum;
}

void scfde_ldpc_encode(const uint8_t *info_bits, uint8_t *code_bits)
{
    uint16_t check;
    if((info_bits == 0) || (code_bits == 0))
    {
        return;
    }
    /* Systematic encoding copies information first and appends one parity bit
       per sparse check equation. */
    memcpy(code_bits, info_bits, SCFDE_LDPC_INFO_BITS);
    for(check = 0u; check < LDPC_CHECKS; check++)
    {
        code_bits[SCFDE_LDPC_INFO_BITS + check] = ldpc_check_sum(info_bits, check);
    }
}

static uint8_t ldpc_syndrome_ok(const uint8_t *bits)
{
    uint16_t check;
    for(check = 0u; check < LDPC_CHECKS; check++)
    {
        if((ldpc_check_sum(bits, check) ^ bits[SCFDE_LDPC_INFO_BITS + check]) != 0u)
        {
            return 0u;
        }
    }
    return 1u;
}

uint8_t scfde_ldpc_decode(const float *llr, uint8_t *info_bits, uint8_t max_iterations)
{
    float variable[SCFDE_LDPC_CODE_BITS];
    float messages[LDPC_EDGE_COUNT];
    uint8_t hard[SCFDE_LDPC_CODE_BITS];
    uint16_t check;
    uint8_t iteration;

    if((llr == 0) || (info_bits == 0))
    {
        return 0u;
    }
    if(max_iterations == 0u)
    {
        max_iterations = 8u;
    }
    /* variable stores current posterior LLRs. messages stores the previous
       check-to-variable value on each of the 320 sparse graph edges. */
    memcpy(variable, llr, sizeof(variable));
    memset(messages, 0, sizeof(messages));

    /* Layered normalized min-sum: update one check and immediately fold its
       extrinsic message back into connected variable beliefs. */
    for(iteration = 0u; iteration < max_iterations; iteration++)
    {
        for(check = 0u; check < LDPC_CHECKS; check++)
        {
            float values[LDPC_INFO_DEGREE + 1u];
            float min1 = 1.0e30f;
            float min2 = 1.0e30f;
            uint8_t min_index = 0u;
            uint8_t sign_product = 0u;
            uint8_t edge;
            /* First pass finds total sign and the two smallest magnitudes. */
            for(edge = 0u; edge < LDPC_INFO_DEGREE + 1u; edge++)
            {
                uint16_t variable_index = (edge < LDPC_INFO_DEGREE) ?
                    ldpc_info_index(check, edge) : (SCFDE_LDPC_INFO_BITS + check);
                uint16_t message_index = check * (LDPC_INFO_DEGREE + 1u) + edge;
                values[edge] = variable[variable_index] - messages[message_index];
                if(values[edge] < 0.0f) sign_product ^= 1u;
                if(values[edge] < 0.0f ? -values[edge] < min1 : values[edge] < min1)
                {
                    min2 = min1;
                    min1 = values[edge] < 0.0f ? -values[edge] : values[edge];
                    min_index = edge;
                }
                else if((values[edge] < 0.0f ? -values[edge] : values[edge]) < min2)
                {
                    min2 = values[edge] < 0.0f ? -values[edge] : values[edge];
                }
            }
            /* Excluding an edge selects min2 for the minimum edge and min1
               for every other edge. Factor 0.80 normalizes min-sum bias. */
            for(edge = 0u; edge < LDPC_INFO_DEGREE + 1u; edge++)
            {
                uint16_t variable_index = (edge < LDPC_INFO_DEGREE) ?
                    ldpc_info_index(check, edge) : (SCFDE_LDPC_INFO_BITS + check);
                uint16_t message_index = check * (LDPC_INFO_DEGREE + 1u) + edge;
                float magnitude = (edge == min_index) ? min2 : min1;
                uint8_t sign = sign_product ^ (values[edge] < 0.0f ? 1u : 0u);
                messages[message_index] = (sign != 0u ? -1.0f : 1.0f) * 0.80f * magnitude;
                variable[variable_index] = values[edge] + messages[message_index];
            }
        }
        for(check = 0u; check < SCFDE_LDPC_CODE_BITS; check++)
        {
            hard[check] = (variable[check] < 0.0f) ? 1u : 0u;
        }
        /* Early termination avoids unnecessary iterations after convergence. */
        if(ldpc_syndrome_ok(hard) != 0u)
        {
            memcpy(info_bits, hard, SCFDE_LDPC_INFO_BITS);
            return 1u;
        }
    }
    for(check = 0u; check < SCFDE_LDPC_INFO_BITS; check++)
    {
        info_bits[check] = (variable[check] < 0.0f) ? 1u : 0u;
    }
    return ldpc_syndrome_ok(hard);
}
