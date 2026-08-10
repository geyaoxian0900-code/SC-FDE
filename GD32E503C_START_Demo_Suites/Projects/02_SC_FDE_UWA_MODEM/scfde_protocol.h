#ifndef SCFDE_PROTOCOL_H
#define SCFDE_PROTOCOL_H

#include "scfde_modem.h"
#include <stdint.h>

/* Chapter-2 MAC protocol layer ported from the 01 DSSS demo (request-
   response handshake, time-slot burst with majority voting, idle frames).
   Frame-type tags ride in the packet sequence field of the SC-FDE packet
   [A5 5A len seq payload CRC16]; an idle frame is len=0 with seq=0. */

#define SCFDE_PROTO_REQ_SEQ      0xA1u  /**< Request frame (payload = user byte). */
#define SCFDE_PROTO_REPLY_SEQ    0xA2u  /**< Reply frame (payload = echoed byte). */
#define SCFDE_PROTO_IDLE_SEQ     0x00u  /**< Idle keep-alive frame (len 0). */
#define SCFDE_PROTO_REPEAT_COUNT 5u     /**< Slot burst repetition count. */
#define SCFDE_PROTO_VOTE_MAJORITY 3u    /**< Majority needed out of REPEAT_COUNT. */

/** Receiver-side slot voting state (5 samples, 3/5 majority). */
typedef struct
{
    uint8_t active;        /**< A first non-idle frame opened this voting slot. */
    uint8_t slot_count;    /**< Frames consumed since the slot opened. */
    uint8_t valid_count;   /**< Non-idle, valid frames collected. */
    uint8_t samples[SCFDE_PROTO_REPEAT_COUNT];
} scfde_proto_vote_t;

/** Outcome of one voting slot. */
typedef struct
{
    uint8_t finalized;     /**< Voting slot closed. */
    uint8_t success;       /**< Majority found. */
    uint8_t rx_data;       /**< Majority byte (valid when success). */
} scfde_proto_vote_result_t;

/** Frame-type predicates on a decoded packet. */
uint8_t scfde_proto_is_request(const scfde_rx_result_t *result);
uint8_t scfde_proto_is_reply(const scfde_rx_result_t *result);
uint8_t scfde_proto_is_idle(const scfde_rx_result_t *result);

/** Build packet content for protocol frames. */
void scfde_proto_make_request(uint8_t data, uint8_t *seq_out, uint8_t *payload_out);
void scfde_proto_make_reply(uint8_t data, uint8_t *seq_out, uint8_t *payload_out);
void scfde_proto_make_idle(uint8_t *seq_out, uint8_t *payload_out, uint8_t *len_out);

/** Reset the voting state. */
void scfde_proto_vote_reset(scfde_proto_vote_t *state);

/**
 * Consume one received frame into the voting slot.
 * @param rx_ok  1 when the frame decoded with CRC valid.
 * @param rx_idle 1 when the frame is an idle keep-alive.
 * @param rx_data The payload byte of a valid non-idle frame.
 * @param result Receives the outcome; finalized=1 when the slot closes
 *        (REPEAT_COUNT frames consumed or an idle frame arrives).
 */
void scfde_proto_vote_consume(scfde_proto_vote_t *state, uint8_t rx_ok,
                              uint8_t rx_idle, uint8_t rx_data,
                              scfde_proto_vote_result_t *result);

/** Pick the 3/5 majority byte from the collected samples. */
uint8_t scfde_proto_vote_pick(const scfde_proto_vote_t *state, uint8_t *rx_data_out);

#endif
