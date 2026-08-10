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
    /* A-grade ported family (book ch3): hybrid time-frequency FDE and
       iterative block DFE variants on the 128-symbol DATA|UW3 block. */
    SCFDE_EQUALIZER_HTFDE,        /**< Hybrid time-frequency decision-feedback FDE. */
    SCFDE_EQUALIZER_SD_IBDFE,     /**< Soft-decision IB-DFE, 4 iterations, unit gain. */
    SCFDE_EQUALIZER_HD_IBDFE,     /**< Hard-decision IB-DFE, 4 iterations, unit gain. */
    SCFDE_EQUALIZER_ICE_SD_IBDFE, /**< Iterative channel estimation + soft IB-DFE. */
    SCFDE_EQUALIZER_ICE_HD_IBDFE, /**< Iterative channel estimation + hard IB-DFE. */
    /* A-grade ported family (book ch2/ch4): time-domain and block adaptive
       equalizers on the full UW1|UW2|DATA|UW3 symbol stream. */
    SCFDE_EQUALIZER_DFE,      /**< Known-channel MMSE time-domain DFE. */
    SCFDE_EQUALIZER_LMS_DFE,  /**< LMS adaptive DFE. */
    SCFDE_EQUALIZER_NLMS_DFE, /**< NLMS adaptive DFE. */
    SCFDE_EQUALIZER_RLS_DFE,  /**< RLS adaptive DFE. */
    SCFDE_EQUALIZER_DPLL_DFE, /**< NLMS DFE with DPLL carrier-phase tracking. */
    SCFDE_EQUALIZER_FBLMS,    /**< Frequency-domain block LMS (overlap-save). */
    /* Chapter-4 turbo family (conv-coded frame, BCJR soft feedback). */
    SCFDE_EQUALIZER_FD_TURBO,      /**< FD-IBDFE + BCJR iterations. */
    SCFDE_EQUALIZER_FD_DFE,        /**< Frequency DFE + single BCJR. */
    SCFDE_EQUALIZER_TF_TURBO,      /**< Time+frequency averaged turbo. */
    SCFDE_EQUALIZER_BITF_TURBO,    /**< Bidirectional time-frequency turbo. */
    SCFDE_EQUALIZER_BLMS_TF_TURBO, /**< Leaky FD-BLMS adaptive turbo. */
    SCFDE_EQUALIZER_TD_TURBO,      /**< Time-domain LMMSE turbo (MMSE eq.). */
    /* Chapter-4 FDDA family (uncoded frame, decision-directed adapt). */
    SCFDE_EQUALIZER_FDDA_TEQ,     /**< FDDA time-domain/decision adaptive. */
    SCFDE_EQUALIZER_TDDA_TEQ,     /**< TDDA variant. */
    SCFDE_EQUALIZER_FDDA_DFE_TEQ, /**< FDDA with decision feedback. */
    SCFDE_EQUALIZER_COUNT     /**< Sentinel used for validation and menu iteration. */
} scfde_equalizer_mode_t;

/**
 * Equalize one circular SC-FDE block in place.
 *
 * MMSE: Xhat=Y*conj(H)/(|H|^2+lambda)
 * ZF:   Xhat=Y*conj(H)/max(|H|^2,floor)
 * MF:   Xhat=Y*conj(H)/mean(|H|^2)
 * IB-DFE adds two hard-decision feedback iterations after the MMSE estimate.
 * HTFDE adds branch-phase correction and reliability-weighted postcursor
 *   cancellation over cfg-equivalent fixed iterations (3).
 * SD/HD-IBDFE run 4 unit-gain iterations with soft/hard feedback; the ICE
 *   variants re-estimate H[k] inside the loop (16 taps, lambda=0.1*N*noise).
 * AUTO, NLMS-TDE, and the DFE family are selected by the modem and are not
 * processed here.
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

/**
 * A-grade chapter-3 family entry: HTFDE and SD/HD-IBDFE (incl. ICE).
 * @param mode One of HTFDE/SD_IBDFE/HD_IBDFE/ICE_SD_IBDFE/ICE_HD_IBDFE.
 * @param channel_response 128-bin H[k]; ICE variants refine it in place.
 * @param impulse Time-domain LS impulse (28 taps).
 * @param block 128-symbol time-domain DATA|UW3 block, equalized in place.
 * @param regularization Noise power estimate.
 * @param fft_size Transform length (128).
 * @param data_symbols Payload symbols (96).
 * @param tail_uw Known trailing UW (32).
 * @param tail_uw_length UW length.
 * @param ice_training_rx Received UW2 (32) for ICE channel updates, or NULL.
 */
void scfde_equalizer_apply_a(scfde_equalizer_mode_t mode,
                             const scfde_complex_t *channel_response,
                             const scfde_complex_t *impulse,
                             scfde_complex_t *block,
                             float regularization,
                             uint16_t fft_size,
                             uint16_t data_symbols,
                             const scfde_complex_t *tail_uw,
                             uint16_t tail_uw_length,
                             const scfde_complex_t *ice_training_rx);

/**
 * Time-domain DFE family on the full frame symbol stream.
 * @param mode One of DFE/LMS_DFE/NLMS_DFE/RLS_DFE/DPLL_DFE/FBLMS.
 * @param frame Full received symbols (UW1|UW2|DATA|UW3).
 * @param frame_symbols Number of symbols in frame (192).
 * @param training Known UW sequence (32 symbols; UW1 and UW2 are both this
 *        sequence, giving 64 training symbols).
 * @param impulse LS channel impulse (28 taps).
 * @param impulse_taps Number of valid impulse taps.
 * @param noise_variance Regularization/noise power estimate.
 * @param data_symbols Number of payload symbols (96).
 * @param output Receives data_symbols symbol estimates.
 */
void scfde_equalizer_dfe(scfde_equalizer_mode_t mode,
                         const scfde_complex_t *frame,
                         uint16_t frame_symbols,
                         const scfde_complex_t *training,
                         const scfde_complex_t *impulse,
                         uint16_t impulse_taps,
                         float noise_variance,
                         uint16_t data_symbols,
                         scfde_complex_t *output);

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
