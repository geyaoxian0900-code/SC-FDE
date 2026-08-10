/* scfde_protocol.c - MAC protocol layer ported from the 01 DSSS demo:
 * request-response handshake tags, idle keep-alive frames, and time-slot
 * burst voting (5 repeats, 3/5 majority). The SC-FDE packet structure
 * [A5 5A len seq payload CRC16] carries the protocol tags in `seq`. */

#include "scfde_protocol.h"

uint8_t scfde_proto_is_request(const scfde_rx_result_t *result)
{
    return ((result != 0) && (result->valid != 0u) &&
            (result->sequence == SCFDE_PROTO_REQ_SEQ) &&
            (result->payload_length >= 1u)) ? 1u : 0u;
}

uint8_t scfde_proto_is_reply(const scfde_rx_result_t *result)
{
    return ((result != 0) && (result->valid != 0u) &&
            (result->sequence == SCFDE_PROTO_REPLY_SEQ) &&
            (result->payload_length >= 1u)) ? 1u : 0u;
}

uint8_t scfde_proto_is_idle(const scfde_rx_result_t *result)
{
    return ((result != 0) && (result->valid != 0u) &&
            (result->payload_length == 0u) &&
            (result->sequence == SCFDE_PROTO_IDLE_SEQ)) ? 1u : 0u;
}

void scfde_proto_make_request(uint8_t data, uint8_t *seq_out, uint8_t *payload_out)
{
    if (seq_out != 0) { *seq_out = SCFDE_PROTO_REQ_SEQ; }
    if (payload_out != 0) { *payload_out = data; }
}

void scfde_proto_make_reply(uint8_t data, uint8_t *seq_out, uint8_t *payload_out)
{
    if (seq_out != 0) { *seq_out = SCFDE_PROTO_REPLY_SEQ; }
    if (payload_out != 0) { *payload_out = data; }
}

void scfde_proto_make_idle(uint8_t *seq_out, uint8_t *payload_out, uint8_t *len_out)
{
    if (seq_out != 0) { *seq_out = SCFDE_PROTO_IDLE_SEQ; }
    if (payload_out != 0) { *payload_out = 0u; }
    if (len_out != 0) { *len_out = 0u; }
}

void scfde_proto_vote_reset(scfde_proto_vote_t *state)
{
    uint8_t index;
    if (state == 0) { return; }
    state->active = 0u;
    state->slot_count = 0u;
    state->valid_count = 0u;
    for (index = 0u; index < SCFDE_PROTO_REPEAT_COUNT; index++)
    {
        state->samples[index] = 0u;
    }
}

uint8_t scfde_proto_vote_pick(const scfde_proto_vote_t *state, uint8_t *rx_data_out)
{
    uint8_t i, j;
    if ((state == 0) || (rx_data_out == 0))
    {
        return 0u;
    }
    for (i = 0u; i < state->valid_count; i++)
    {
        uint8_t match_count = 0u;
        for (j = 0u; j < state->valid_count; j++)
        {
            if (state->samples[j] == state->samples[i])
            {
                match_count++;
            }
        }
        if (match_count >= SCFDE_PROTO_VOTE_MAJORITY)
        {
            *rx_data_out = state->samples[i];
            return 1u;
        }
    }
    return 0u;
}

static void scfde_proto_vote_finalize(scfde_proto_vote_t *state,
                                      scfde_proto_vote_result_t *result)
{
    result->finalized = 1u;
    result->success = scfde_proto_vote_pick(state, &result->rx_data);
    scfde_proto_vote_reset(state);
}

void scfde_proto_vote_consume(scfde_proto_vote_t *state, uint8_t rx_ok,
                              uint8_t rx_idle, uint8_t rx_data,
                              scfde_proto_vote_result_t *result)
{
    if (result == 0)
    {
        return;
    }
    result->finalized = 0u;
    result->success = 0u;
    result->rx_data = 0u;
    if (state == 0)
    {
        return;
    }
    if (state->active == 0u)
    {
        if ((rx_ok != 0u) && (rx_idle == 0u))
        {
            state->active = 1u;
            state->slot_count = 1u;
            state->valid_count = 1u;
            state->samples[0] = rx_data;
            if (SCFDE_PROTO_REPEAT_COUNT <= 1u)
            {
                scfde_proto_vote_finalize(state, result);
            }
        }
        return;
    }
    if ((rx_ok != 0u) && (rx_idle == 0u))
    {
        if (state->valid_count < SCFDE_PROTO_REPEAT_COUNT)
        {
            state->samples[state->valid_count] = rx_data;
            state->valid_count++;
        }
        if (state->slot_count < SCFDE_PROTO_REPEAT_COUNT)
        {
            state->slot_count++;
        }
    }
    else if ((rx_ok != 0u) && (rx_idle != 0u))
    {
        scfde_proto_vote_finalize(state, result);
        return;
    }
    else
    {
        if (state->slot_count < SCFDE_PROTO_REPEAT_COUNT)
        {
            state->slot_count++;
        }
    }
    if (state->slot_count >= SCFDE_PROTO_REPEAT_COUNT)
    {
        scfde_proto_vote_finalize(state, result);
    }
}
