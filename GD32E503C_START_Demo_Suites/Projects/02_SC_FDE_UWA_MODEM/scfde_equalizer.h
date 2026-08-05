#ifndef SCFDE_EQUALIZER_H
#define SCFDE_EQUALIZER_H

#include "scfde_fft.h"
#include <stdint.h>

typedef enum
{
    SCFDE_EQUALIZER_AUTO = 0, /**< Modem tries fixed modes until packet CRC passes. */
    SCFDE_EQUALIZER_MMSE_FDE, /**< Regularized one-tap frequency-domain equalizer. */
    SCFDE_EQUALIZER_ZF_FDE,   /**< Zero forcing with a deep-null denominator floor. */
    SCFDE_EQUALIZER_MF_FDE,   /**< Channel matched filter normalized by mean power. */
    SCFDE_EQUALIZER_IB_DFE,   /**< MMSE feedforward plus iterative decision feedback. */
    SCFDE_EQUALIZER_NLMS_TDE, /**< Trained 16-tap time-domain FIR equalizer. */
    SCFDE_EQUALIZER_COUNT     /**< Sentinel used for validation and menu iteration. */
} scfde_equalizer_mode_t;

/**
 * Equalize one circular SC-FDE block in place.
 *
 * MMSE: Xhat=Y*conj(H)/(|H|^2+lambda)
 * ZF:   Xhat=Y*conj(H)/max(|H|^2,floor)
 * MF:   Xhat=Y*conj(H)/mean(|H|^2)
 * IB-DFE adds two hard-decision feedback iterations after the MMSE estimate.
 * AUTO and NLMS-TDE are selected by the modem and are not processed here.
 *
 * @param mode One fixed frequency-domain mode.
 * @param channel_response fft_size complex frequency-response bins.
 * @param block fft_size time-domain samples on entry and equalized samples on exit.
 * @param regularization Estimated frequency-domain noise power lambda.
 * @param fft_size Power-of-two transform length, no larger than 128.
 * @param data_symbols Number of unknown QPSK symbols before the trailing UW.
 * @param tail_uw Known trailing symbols used by IB-DFE; may be NULL.
 * @param tail_uw_length Number of valid entries in tail_uw.
 */
void scfde_equalizer_apply(scfde_equalizer_mode_t mode,
                           const scfde_complex_t *channel_response,
                           scfde_complex_t *block,
                           float regularization,
                           uint16_t fft_size,
                           uint16_t data_symbols,
                           const scfde_complex_t *tail_uw,
                           uint16_t tail_uw_length);

/** Return a stable, static display name for an equalizer enum value. */
const char *scfde_equalizer_name(scfde_equalizer_mode_t mode);

/**
 * Train and apply the true time-domain NLMS FIR equalizer.
 * @param block Time-domain receive block modified in place.
 * @param block_length Number of complex samples in block, no larger than 128.
 * @param training_rx Received repeated UW after CFO compensation.
 * @param training_reference Known transmitted UW in the desired timing phase.
 * @param training_length Length of both training arrays; currently 32.
 * @note The repeated UW permits circular training history. DATA filtering uses
 *       the received training UW as the causal history before block[0].
 */
void scfde_equalizer_nlms_tde(scfde_complex_t *block,
                              uint16_t block_length,
                              const scfde_complex_t *training_rx,
                              const scfde_complex_t *training_reference,
                              uint16_t training_length);

#endif
