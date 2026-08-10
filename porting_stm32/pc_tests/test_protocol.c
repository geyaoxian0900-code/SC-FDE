/* test_protocol.c - MAC protocol layer unit tests: request/reply/idle
 * frame tagging and the 5-repeat 3/5-majority slot voting state machine. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "scfde_protocol.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } \
} while (0)

static void make_result(scfde_rx_result_t *r, uint8_t valid, uint8_t seq,
                        uint8_t len, uint8_t data)
{
    memset(r, 0, sizeof(*r));
    r->valid = valid;
    r->sequence = seq;
    r->payload_length = len;
    if (len > 0u) { r->payload[0] = data; }
}

int main(void)
{
    scfde_rx_result_t r;
    scfde_proto_vote_t vote;
    scfde_proto_vote_result_t result;
    uint8_t seq, payload, len, data;

    /* frame tagging */
    make_result(&r, 1, SCFDE_PROTO_REQ_SEQ, 1, 0x42);
    CHECK(scfde_proto_is_request(&r) == 1u, "request tag");
    CHECK(scfde_proto_is_reply(&r) == 0u, "request not reply");
    CHECK(scfde_proto_is_idle(&r) == 0u, "request not idle");
    make_result(&r, 1, SCFDE_PROTO_REPLY_SEQ, 1, 0x42);
    CHECK(scfde_proto_is_reply(&r) == 1u, "reply tag");
    make_result(&r, 1, SCFDE_PROTO_IDLE_SEQ, 0, 0);
    CHECK(scfde_proto_is_idle(&r) == 1u, "idle tag");
    make_result(&r, 0, SCFDE_PROTO_REQ_SEQ, 1, 0x42);
    CHECK(scfde_proto_is_request(&r) == 0u, "invalid frame not request");

    /* frame builders */
    scfde_proto_make_request(0x11, &seq, &payload);
    CHECK(seq == SCFDE_PROTO_REQ_SEQ && payload == 0x11, "request builder");
    scfde_proto_make_reply(0x22, &seq, &payload);
    CHECK(seq == SCFDE_PROTO_REPLY_SEQ && payload == 0x22, "reply builder");
    scfde_proto_make_idle(&seq, &payload, &len);
    CHECK(seq == SCFDE_PROTO_IDLE_SEQ && len == 0u, "idle builder");

    /* voting: 5 frames with 3/5 majority (finalized at the 5th frame) */
    scfde_proto_vote_reset(&vote);
    scfde_proto_vote_consume(&vote, 1, 0, 0x5A, &result);
    CHECK(result.finalized == 0u, "first frame opens slot");
    scfde_proto_vote_consume(&vote, 1, 0, 0x5A, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x5A, &result);
    CHECK(result.finalized == 0u, "three frames not yet finalized");
    scfde_proto_vote_consume(&vote, 1, 0, 0x5A, &result);
    CHECK(result.finalized == 0u, "slot waits for the full repeat count");
    scfde_proto_vote_consume(&vote, 1, 0, 0x5A, &result);
    CHECK(result.finalized == 1u && result.success == 1u &&
          result.rx_data == 0x5A, "majority at the 5th frame");
    CHECK(vote.active == 0u, "slot reset after finalize");

    /* voting: no majority (2 vs 2 vs 1) */
    scfde_proto_vote_reset(&vote);
    scfde_proto_vote_consume(&vote, 1, 0, 0x11, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x11, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x22, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x22, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x33, &result);
    CHECK(result.finalized == 1u && result.success == 0u, "no majority");

    /* voting: idle closes the slot early (single sample cannot form a
       3/5 majority, matching the 01-DSSS semantics) */
    scfde_proto_vote_reset(&vote);
    scfde_proto_vote_consume(&vote, 1, 0, 0x77, &result);
    scfde_proto_vote_consume(&vote, 1, 1, 0, &result);
    CHECK(result.finalized == 1u && result.success == 0u,
          "idle finalizes; one sample is no majority");

    /* voting: idle after 4 identical samples still wins */
    scfde_proto_vote_reset(&vote);
    scfde_proto_vote_consume(&vote, 1, 0, 0x77, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x77, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x77, &result);
    scfde_proto_vote_consume(&vote, 1, 0, 0x77, &result);
    scfde_proto_vote_consume(&vote, 1, 1, 0, &result);
    CHECK(result.finalized == 1u && result.success == 1u &&
          result.rx_data == 0x77, "idle finalizes with 4/5 majority");

    /* voting: decodes in between (timeouts) do not open the slot */
    scfde_proto_vote_reset(&vote);
    scfde_proto_vote_consume(&vote, 0, 0, 0, &result);
    CHECK(result.finalized == 0u && vote.active == 0u, "decode fail ignored");

    printf("PASS\n");
    return 0;
}
