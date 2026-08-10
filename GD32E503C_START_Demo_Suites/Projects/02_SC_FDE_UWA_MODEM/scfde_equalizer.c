#include "scfde_equalizer.h"
#include <string.h>
#include <math.h>

/**
 * @file scfde_equalizer.c
 * @brief Resource-bounded FDE, IB-DFE, and NLMS-TDE implementations.
 *
 * The frequency-domain methods share one-tap complex weights. IB-DFE keeps
 * Y[k], forms hard time-domain QPSK decisions, transforms them to D[k], and
 * applies X[k]=W[k]Y[k]-beta(W[k]H[k]-1)D[k]. NLMS-TDE is independent of the
 * FFT and learns a causal inverse FIR from the repeated UW.
 */

#define SCFDE_EQUALIZER_MAX_FFT       128u
#define SCFDE_IB_DFE_ITERATIONS       2u
#define SCFDE_IB_DFE_FEEDBACK_GAIN    0.65f
#define SCFDE_TDE_TAPS                 16u
#define SCFDE_TDE_TRAINING_EPOCHS      6u
#define SCFDE_TDE_NLMS_STEP            0.35f
#define SCFDE_TDE_NLMS_EPSILON         1.0e-6f

/* A-grade family parameters (aligned with the MATLAB equalizer package). */
#define SCFDE_HTFDE_BRANCHES           4u
#define SCFDE_HTFDE_ITERATIONS         3u
#define SCFDE_IBDFE_ITERATIONS         4u
#define SCFDE_ICE_CHANNEL_TAPS         16u
#define SCFDE_ICE_CHANNEL_REGULARIZATION 0.1f
#define SCFDE_DFE_FF_TAPS              12u
#define SCFDE_DFE_FB_TAPS              6u
#define SCFDE_LMS_STEP                 0.008f
#define SCFDE_NLMS_STEP                0.35f
#define SCFDE_RLS_FORGETTING           0.985f
#define SCFDE_RLS_INIT_INV_CORR        100.0f
#define SCFDE_DPLL_PROP_GAIN           0.020f
#define SCFDE_DPLL_INTEGRAL_GAIN       0.0004f
#define SCFDE_FBLMS_BLOCK              32u
#define SCFDE_FBLMS_FILTER             16u
#define SCFDE_FBLMS_FFT                (SCFDE_FBLMS_BLOCK + 2u * SCFDE_FBLMS_FILTER)
#define SCFDE_FBLMS_STEP               0.5f
#define SCFDE_FBLMS_EPSILON            1.0e-6f

static scfde_complex_t g_received_spectrum[SCFDE_EQUALIZER_MAX_FFT];
static scfde_complex_t g_decision_spectrum[SCFDE_EQUALIZER_MAX_FFT];
static scfde_complex_t g_tde_input[SCFDE_EQUALIZER_MAX_FFT];
static scfde_complex_t g_block_work[SCFDE_EQUALIZER_MAX_FFT];
static scfde_complex_t g_impulse[SCFDE_EQUALIZER_MAX_FFT];
/* DFE family workspace: adaptive weights (FF+FB) and RLS inverse
   correlation (36x36 complex).  Shared by all DFE modes. */
#define SCFDE_DFE_WEIGHTS (SCFDE_DFE_FF_TAPS + SCFDE_DFE_FB_TAPS)
static scfde_complex_t g_dfe_weights[SCFDE_DFE_WEIGHTS];
static scfde_complex_t g_dfe_rls[SCFDE_DFE_WEIGHTS * SCFDE_DFE_WEIGHTS];
static float g_dfe_input_power;
/* C-grade multichannel DFE workspace: B=2 pseudo-branches (the second
   branch is the received stream delayed by one symbol), weights of
   B*FF+FB taps and a (B*FF+FB)x(B*FF+FB) RLS inverse correlation. */
#define SCFDE_MC_BRANCHES 2u
#define SCFDE_MC_WEIGHTS (SCFDE_MC_BRANCHES * SCFDE_DFE_FF_TAPS + SCFDE_DFE_FB_TAPS)
#define SCFDE_MC_FF_TOTAL (SCFDE_MC_BRANCHES * SCFDE_DFE_FF_TAPS)
static scfde_complex_t g_mc_weights[SCFDE_MC_WEIGHTS];
static scfde_complex_t g_mc_rls[SCFDE_MC_WEIGHTS * SCFDE_MC_WEIGHTS];
/* PTR front-end workspace bound: the LS impulse is 28 taps, so the
   equivalent autocorrelation channel is at most 55 taps. */
#define SCFDE_PTR_MAX_TAPS 28u

static scfde_complex_t complex_multiply(scfde_complex_t a, scfde_complex_t b)
{
    scfde_complex_t value;
    value.re = a.re * b.re - a.im * b.im;
    value.im = a.re * b.im + a.im * b.re;
    return value;
}

static scfde_complex_t complex_conjugate(scfde_complex_t value)
{
    value.im = -value.im;
    return value;
}

static float complex_power(scfde_complex_t value)
{
    return value.re * value.re + value.im * value.im;
}

static void frequency_equalize(scfde_equalizer_mode_t mode,
                               const scfde_complex_t *channel,
                               scfde_complex_t *spectrum,
                               float regularization,
                               uint16_t size)
{
    float average_power = 0.0f;
    float floor;
    uint16_t n;

    /* Mean power normalizes the matched filter and defines a scale-relative
       floor for ZF, preventing division by a deep spectral null. */
    for(n = 0u; n < size; n++)
    {
        average_power += complex_power(channel[n]);
    }
    average_power /= (float)size;
    floor = average_power * 1.0e-4f;
    if(floor < 1.0e-12f)
    {
        floor = 1.0e-12f;
    }

    for(n = 0u; n < size; n++)
    {
        float power = complex_power(channel[n]);
        float denominator;
        scfde_complex_t numerator = complex_multiply(spectrum[n], complex_conjugate(channel[n]));

        if(mode == SCFDE_EQUALIZER_MF_FDE)
        {
            denominator = average_power + floor;
        }
        else if(mode == SCFDE_EQUALIZER_ZF_FDE)
        {
            denominator = power > floor ? power : floor;
        }
        else
        {
            denominator = power + regularization;
        }
        spectrum[n].re = numerator.re / denominator;
        spectrum[n].im = numerator.im / denominator;
    }
}

static void ib_dfe_equalize(const scfde_complex_t *channel,
                            scfde_complex_t *block,
                            float regularization,
                            uint16_t size,
                            uint16_t data_symbols,
                            const scfde_complex_t *tail_uw,
                            uint16_t tail_length)
{
    uint8_t iteration;
    uint16_t n;

    /* block contains Y[k] on entry. Preserve it because every feedback pass
       must start from the same received observation rather than its predecessor. */
    memcpy(g_received_spectrum, block, size * sizeof(scfde_complex_t));
    frequency_equalize(SCFDE_EQUALIZER_MMSE_FDE, channel, block, regularization, size);
    scfde_fft(block, size, 1u);

    for(iteration = 0u; iteration < SCFDE_IB_DFE_ITERATIONS; iteration++)
    {
        /* Decisions are made in time. The known UW3 tail is injected exactly
           instead of hard-slicing it, which stabilizes channel-null feedback. */
        for(n = 0u; n < size; n++)
        {
            if((n >= data_symbols) && ((n - data_symbols) < tail_length) && (tail_uw != 0))
            {
                g_decision_spectrum[n] = tail_uw[n - data_symbols];
            }
            else
            {
                g_decision_spectrum[n].re = block[n].re >= 0.0f ? 1.0f : -1.0f;
                g_decision_spectrum[n].im = block[n].im >= 0.0f ? 1.0f : -1.0f;
            }
        }
        scfde_fft(g_decision_spectrum, size, 0u);
        for(n = 0u; n < size; n++)
        {
            float denominator = complex_power(channel[n]) + regularization;
            scfde_complex_t weight;
            scfde_complex_t feedforward;
            scfde_complex_t response;
            scfde_complex_t feedback;

            /* W=conj(H)/(|H|^2+lambda), B=WH-1, X=WY-beta*B*D. */
            weight = complex_conjugate(channel[n]);
            weight.re /= denominator;
            weight.im /= denominator;
            feedforward = complex_multiply(g_received_spectrum[n], weight);
            response = complex_multiply(weight, channel[n]);
            response.re -= 1.0f;
            feedback = complex_multiply(response, g_decision_spectrum[n]);
            block[n].re = feedforward.re - SCFDE_IB_DFE_FEEDBACK_GAIN * feedback.re;
            block[n].im = feedforward.im - SCFDE_IB_DFE_FEEDBACK_GAIN * feedback.im;
        }
        scfde_fft(block, size, 1u);
    }
}

void scfde_equalizer_apply(scfde_equalizer_mode_t mode,
                           const scfde_complex_t *channel_response,
                           scfde_complex_t *block,
                           float regularization,
                           uint16_t fft_size,
                           uint16_t data_symbols,
                           const scfde_complex_t *tail_uw,
                           uint16_t tail_uw_length)
{
    if((channel_response == 0) || (block == 0) || (fft_size > SCFDE_EQUALIZER_MAX_FFT))
    {
        return;
    }
    scfde_fft(block, fft_size, 0u);
    if(mode == SCFDE_EQUALIZER_IB_DFE)
    {
        ib_dfe_equalize(channel_response, block, regularization, fft_size,
                        data_symbols, tail_uw, tail_uw_length);
        return;
    }
    if((mode != SCFDE_EQUALIZER_ZF_FDE) && (mode != SCFDE_EQUALIZER_MF_FDE))
    {
        mode = SCFDE_EQUALIZER_MMSE_FDE;
    }
    frequency_equalize(mode, channel_response, block, regularization, fft_size);
    scfde_fft(block, fft_size, 1u);
}

const char *scfde_equalizer_name(scfde_equalizer_mode_t mode)
{
    static const char *const names[SCFDE_EQUALIZER_COUNT] = {
        "AUTO", "MMSE-FDE", "ZF-FDE", "MF-FDE", "IB-DFE", "NLMS-TDE",
        "HTFDE", "SD-IBDFE", "HD-IBDFE", "ICE-SD-IBDFE", "ICE-HD-IBDFE",
        "DFE", "LMS-DFE", "NLMS-DFE", "RLS-DFE", "DPLL-DFE", "FBLMS",
        "FD-TURBO", "FD-DFE", "TF-TURBO", "BITF-TURBO", "BLMS-TF-TURBO",
        "TD-TURBO", "FDDA-TEQ", "TDDA-TEQ", "FDDA-DFE-TEQ",
        "PTR-DFE", "SUBBAND-PTR-DFE", "MC-LMS-DFE", "MC-NLMS-DFE", "MC-RLS-DFE",
        "CCK-MFB", "CCK-RAKE", "CCK-DFE", "CCK-BIDFE",
        "CCK-BIDFE2", "CCK-TR-DIV", "CCK-FDE"
    };
    if ((uint8_t)mode >= (uint8_t)SCFDE_EQUALIZER_COUNT)
    {
        return "UNKNOWN";
    }
    return names[(uint8_t)mode];
}

void scfde_equalizer_nlms_tde(scfde_complex_t *block,
                              uint16_t block_length,
                              const scfde_complex_t *training_rx,
                              const scfde_complex_t *training_reference,
                              uint16_t training_length)
{
    scfde_complex_t coefficient[SCFDE_TDE_TAPS];
    uint8_t epoch;
    uint16_t n;
    uint16_t tap;

    if((block == 0) || (training_rx == 0) || (training_reference == 0) ||
       (training_length == 0u) || (block_length > SCFDE_EQUALIZER_MAX_FFT))
    {
        return;
    }
    /* Start from an identity channel. NLMS then scales safely for raw ADC
       amplitudes because every update is divided by current input energy. */
    memset(coefficient, 0, sizeof(coefficient));
    coefficient[0].re = 1.0f;

    /* The first UW is a cyclic prefix for the repeated training UW, so the
       training input history can wrap within the known 32-symbol sequence. */
    for(epoch = 0u; epoch < SCFDE_TDE_TRAINING_EPOCHS; epoch++)
    {
        for(n = 0u; n < training_length; n++)
        {
            scfde_complex_t output = {0.0f, 0.0f};
            scfde_complex_t error;
            float input_power = SCFDE_TDE_NLMS_EPSILON;

            for(tap = 0u; tap < SCFDE_TDE_TAPS; tap++)
            {
                uint16_t index = (uint16_t)((n + training_length -
                    (tap % training_length)) % training_length);
                scfde_complex_t input = training_rx[index];
                scfde_complex_t product = complex_multiply(coefficient[tap], input);
                output.re += product.re;
                output.im += product.im;
                input_power += complex_power(input);
            }
            /* e[n]=d[n]-w*x[n], w<-w+mu*e[n]*conj(x[n])/(||x||^2+eps). */
            error.re = training_reference[n].re - output.re;
            error.im = training_reference[n].im - output.im;
            for(tap = 0u; tap < SCFDE_TDE_TAPS; tap++)
            {
                uint16_t index = (uint16_t)((n + training_length -
                    (tap % training_length)) % training_length);
                scfde_complex_t update = complex_multiply(error,
                    complex_conjugate(training_rx[index]));
                coefficient[tap].re += SCFDE_TDE_NLMS_STEP * update.re / input_power;
                coefficient[tap].im += SCFDE_TDE_NLMS_STEP * update.im / input_power;
            }
        }
    }

    /* Keep an immutable input copy: writing an output sample must not corrupt
       the future FIR input history. Negative indices come from received UW2. */
    memcpy(g_tde_input, block, block_length * sizeof(scfde_complex_t));
    for(n = 0u; n < block_length; n++)
    {
        scfde_complex_t output = {0.0f, 0.0f};
        for(tap = 0u; tap < SCFDE_TDE_TAPS; tap++)
        {
            scfde_complex_t input;
            if(n >= tap)
            {
                input = g_tde_input[n - tap];
            }
            else
            {
                uint16_t history = (uint16_t)(tap - n);
                input = training_rx[training_length - history];
            }
            output.re += coefficient[tap].re * input.re - coefficient[tap].im * input.im;
            output.im += coefficient[tap].re * input.im + coefficient[tap].im * input.re;
        }
        block[n] = output;
    }
}
/* ------------------------------------------------------------------ */
/* A-grade family: shared QPSK helpers                                */
/* ------------------------------------------------------------------ */

static scfde_complex_t qpsk_hard_decision(scfde_complex_t value)
{
    scfde_complex_t d;
    const float inv_sqrt2 = 0.7071067811865476f;
    d.re = (value.re >= 0.0f) ? inv_sqrt2 : -inv_sqrt2;
    d.im = (value.im >= 0.0f) ? inv_sqrt2 : -inv_sqrt2;
    return d;
}

static scfde_complex_t qpsk_posterior_mean(scfde_complex_t value, float noise_variance)
{
    scfde_complex_t hard = qpsk_hard_decision(value);
    float dv = (value.re - hard.re) * (value.re - hard.re) +
               (value.im - hard.im) * (value.im - hard.im);
    float effective = noise_variance > dv ? noise_variance : dv;
    if (effective < 1.0e-8f) { effective = 1.0e-8f; }
    float scale = 1.4142135623730951f / effective;
    scfde_complex_t m;
    m.re = tanhf(scale * value.re) * 0.7071067811865476f;
    m.im = tanhf(scale * value.im) * 0.7071067811865476f;
    return m;
}

static float qpsk_reliability(const scfde_complex_t *symbols,
                              uint16_t count, float noise_variance)
{
    float sum = 0.0f;
    uint16_t n;
    for (n = 0; n < count; n++)
    {
        scfde_complex_t m = qpsk_posterior_mean(symbols[n], noise_variance);
        sum += m.re * m.re + m.im * m.im;
    }
    sum /= (float)count;
    return sum > 0.999f ? 0.999f : sum;
}

static void circular_postcursor(const scfde_complex_t *decisions,
                                const scfde_complex_t *impulse,
                                uint16_t impulse_taps,
                                uint16_t size,
                                scfde_complex_t *postcursor)
{
    uint16_t n, tap;
    for (n = 0; n < size; n++)
    {
        postcursor[n].re = 0.0f;
        postcursor[n].im = 0.0f;
    }
    for (tap = 1; tap < impulse_taps; tap++)
    {
        for (n = 0; n < size; n++)
        {
            uint16_t src = (uint16_t)((n + size - tap) % size);
            postcursor[n].re += impulse[tap].re * decisions[src].re -
                                impulse[tap].im * decisions[src].im;
            postcursor[n].im += impulse[tap].re * decisions[src].im +
                                impulse[tap].im * decisions[src].re;
        }
    }
}

/* ------------------------------------------------------------------ */
/* HTFDE: branch-phase correction + reliability-weighted postcursor   */
/* ------------------------------------------------------------------ */

static void htfde_equalize(const scfde_complex_t *channel,
                           scfde_complex_t *block,
                           float noise_variance,
                           uint16_t size,
                           uint16_t data_symbols,
                           const scfde_complex_t *tail_uw,
                           uint16_t tail_length,
                           const scfde_complex_t *impulse)
{
    uint16_t segment = size / SCFDE_HTFDE_BRANCHES;
    uint16_t iter, n, branch;
    scfde_complex_t *symbols = g_block_work;
    scfde_complex_t *decision = g_decision_spectrum;
    scfde_complex_t *predicted = g_received_spectrum;
    scfde_complex_t *phase_corrected = g_tde_input;
    scfde_complex_t *postcursor = g_impulse;

    memcpy(symbols, block, size * sizeof(scfde_complex_t));
    for (iter = 0; iter < SCFDE_HTFDE_ITERATIONS; iter++)
    {
        scfde_fft(symbols, size, 0u);
        for (n = 0; n < size; n++)
        {
            float p = complex_power(channel[n]);
            float den = p + noise_variance;
            scfde_complex_t num = complex_multiply(symbols[n], complex_conjugate(channel[n]));
            symbols[n].re = num.re / den;
            symbols[n].im = num.im / den;
        }
        scfde_fft(symbols, size, 1u);
        for (n = 0; n < size; n++)
        {
            if ((n >= data_symbols) && ((n - data_symbols) < tail_length) && (tail_uw != 0))
            {
                decision[n] = tail_uw[n - data_symbols];
            }
            else
            {
                decision[n] = qpsk_hard_decision(symbols[n]);
            }
        }
        float reliability = qpsk_reliability(symbols, data_symbols, noise_variance);
        memcpy(predicted, decision, size * sizeof(scfde_complex_t));
        scfde_fft(predicted, size, 0u);
        for (n = 0; n < size; n++)
        {
            predicted[n] = complex_multiply(channel[n], predicted[n]);
        }
        scfde_fft(predicted, size, 1u);
        for (branch = 0; branch < SCFDE_HTFDE_BRANCHES; branch++)
        {
            uint16_t start = branch * segment;
            float sum_re = 0.0f, sum_im = 0.0f;
            for (n = 0; n < segment; n++)
            {
                uint16_t idx = start + n;
                sum_re += block[idx].re * predicted[idx].re + block[idx].im * predicted[idx].im;
                sum_im += block[idx].im * predicted[idx].re - block[idx].re * predicted[idx].im;
            }
            float angle = atan2f(sum_im, sum_re);
            float c = cosf(angle), s = sinf(angle);
            for (n = 0; n < segment; n++)
            {
                uint16_t idx = start + n;
                phase_corrected[idx].re = block[idx].re * c + block[idx].im * s;
                phase_corrected[idx].im = -block[idx].re * s + block[idx].im * c;
            }
        }
        circular_postcursor(decision, impulse, SCFDE_ICE_CHANNEL_TAPS, size, postcursor);
        for (n = 0; n < size; n++)
        {
            symbols[n].re = phase_corrected[n].re - reliability * postcursor[n].re;
            symbols[n].im = phase_corrected[n].im - reliability * postcursor[n].im;
        }
        memset(g_impulse, 0, size * sizeof(scfde_complex_t));
        for (n = 0; n < SCFDE_ICE_CHANNEL_TAPS && n < size; n++)
        {
            g_impulse[n] = impulse[n];
        }
        for (n = 1; n < SCFDE_ICE_CHANNEL_TAPS; n++)
        {
            g_impulse[n].re *= (1.0f - reliability);
            g_impulse[n].im *= (1.0f - reliability);
        }
        scfde_fft(g_impulse, size, 0u);
        memcpy(symbols, phase_corrected, size * sizeof(scfde_complex_t));
        scfde_fft(symbols, size, 0u);
        for (n = 0; n < size; n++)
        {
            float p = complex_power(g_impulse[n]);
            float den = p + noise_variance;
            scfde_complex_t num = complex_multiply(symbols[n], complex_conjugate(g_impulse[n]));
            symbols[n].re = num.re / den;
            symbols[n].im = num.im / den;
        }
        scfde_fft(symbols, size, 1u);
    }
    memcpy(block, symbols, size * sizeof(scfde_complex_t));
}
/* ------------------------------------------------------------------ */
/* SD/HD-IBDFE with optional iterative channel estimation (ICE)       */
/* ------------------------------------------------------------------ */

static void ibdfe_grade_a(scfde_complex_t *channel, scfde_complex_t *block,
                          float noise_variance, uint16_t size,
                          uint16_t data_symbols,
                          const scfde_complex_t *tail_uw, uint16_t tail_length,
                          uint8_t soft_mode, uint8_t update_channel,
                          const scfde_complex_t *training_spectrum,
                          const scfde_complex_t *training_received_spectrum)
{
    uint16_t iter, n;
    float reliability = 0.0f;
    scfde_complex_t *y = g_received_spectrum;
    scfde_complex_t *feedback_spectrum = g_decision_spectrum;
    scfde_complex_t *feedback_mean = g_tde_input;
    scfde_complex_t *channel_work = g_block_work;
    scfde_complex_t *impulse_work = g_impulse;

    memcpy(y, block, size * sizeof(scfde_complex_t));
    scfde_fft(y, size, 0u);
    for (iter = 0; iter < SCFDE_IBDFE_ITERATIONS; iter++)
    {
        float symbol_variance = 1.0f - reliability;
        if (symbol_variance < 1.0e-6f) { symbol_variance = 1.0e-6f; }
        float gamma_re = 0.0f, gamma_im = 0.0f;
        for (n = 0; n < size; n++)
        {
            float p = complex_power(channel[n]);
            float den = p * symbol_variance + noise_variance;
            if (den < 1.0e-12f) { den = 1.0e-12f; }
            channel_work[n].re = channel[n].re * symbol_variance / den;
            channel_work[n].im = -channel[n].im * symbol_variance / den;
            gamma_re += channel_work[n].re * channel[n].re - channel_work[n].im * channel[n].im;
            gamma_im += channel_work[n].re * channel[n].im + channel_work[n].im * channel[n].re;
        }
        float gamma_norm = sqrtf(gamma_re * gamma_re + gamma_im * gamma_im);
        if (gamma_norm < 1.0e-12f) { gamma_norm = 1.0e-12f; }
        for (n = 0; n < size; n++)
        {
            scfde_complex_t w, wg;
            w.re = channel_work[n].re / gamma_norm;
            w.im = channel_work[n].im / gamma_norm;
            wg = complex_multiply(w, channel[n]);
            scfde_complex_t wy = complex_multiply(w, y[n]);
            scfde_complex_t fb = complex_multiply(feedback_spectrum[n], wg);
            block[n].re = wy.re - fb.re + feedback_spectrum[n].re;
            block[n].im = wy.im - fb.im + feedback_spectrum[n].im;
        }
        scfde_fft(block, size, 1u);
        for (n = 0; n < size; n++)
        {
            if ((n >= data_symbols) && ((n - data_symbols) < tail_length) && (tail_uw != 0))
            {
                feedback_mean[n] = tail_uw[n - data_symbols];
            }
            else if (soft_mode != 0u)
            {
                feedback_mean[n] = qpsk_posterior_mean(block[n], noise_variance);
            }
            else
            {
                feedback_mean[n] = qpsk_hard_decision(block[n]);
            }
        }
        reliability = qpsk_reliability(block, data_symbols, noise_variance);
        memcpy(feedback_spectrum, feedback_mean, size * sizeof(scfde_complex_t));
        scfde_fft(feedback_spectrum, size, 0u);
        if (update_channel != 0u)
        {
            float regularization = SCFDE_ICE_CHANNEL_REGULARIZATION *
                                   (float)size * noise_variance;
            for (n = 0; n < size; n++)
            {
                float tp = complex_power(training_spectrum[n]);
                float dp = complex_power(feedback_spectrum[n]);
                float den = tp + reliability * dp + regularization;
                if (den < 1.0e-12f) { den = 1.0e-12f; }
                scfde_complex_t num;
                num = complex_multiply(training_received_spectrum[n],
                                       complex_conjugate(training_spectrum[n]));
                num.re += reliability * (feedback_spectrum[n].re * y[n].re +
                                         feedback_spectrum[n].im * y[n].im);
                num.im += reliability * (feedback_spectrum[n].re * y[n].im -
                                         feedback_spectrum[n].im * y[n].re);
                channel[n].re = num.re / den;
                channel[n].im = num.im / den;
            }
            scfde_fft(channel, size, 1u);
            for (n = SCFDE_ICE_CHANNEL_TAPS; n < size; n++)
            {
                channel[n].re = 0.0f;
                channel[n].im = 0.0f;
            }
            scfde_fft(channel, size, 0u);
        }
    }
    (void)impulse_work;
}
/* ------------------------------------------------------------------ */
/* FBLMS: overlap-save frequency-domain block LMS                     */
/* ------------------------------------------------------------------ */

static void fblms_equalize(const scfde_complex_t *frame, uint16_t frame_symbols,
                           const scfde_complex_t *training, uint16_t training_length,
                           uint16_t data_symbols, scfde_complex_t *output)
{
    const uint16_t n_block = SCFDE_FBLMS_BLOCK;
    const uint16_t n_f = SCFDE_FBLMS_FILTER;
    const uint16_t fft_len = SCFDE_FBLMS_FFT;
    static scfde_complex_t weights[SCFDE_FBLMS_FFT];
    static scfde_complex_t input_block[SCFDE_FBLMS_FFT];
    static scfde_complex_t filtered[SCFDE_FBLMS_FFT];
    static scfde_complex_t error_spectrum[SCFDE_FBLMS_FFT];
    static scfde_complex_t front_tail[SCFDE_FBLMS_FILTER];
    uint16_t block_index, n;
    uint16_t symbol_cursor = 0u;

    memset(weights, 0, sizeof(weights));
    memset(front_tail, 0, sizeof(front_tail));
    {
        uint16_t total_blocks = (uint16_t)((frame_symbols + n_block - 1u) / n_block);
        for (block_index = 0; block_index < total_blocks; block_index++)
        {
            uint32_t block_start = (uint32_t)block_index * n_block;
            uint16_t i;
            for (i = 0; i < n_f; i++)
            {
                input_block[i] = front_tail[i];
            }
            for (i = 0; i < n_block; i++)
            {
                uint32_t idx = block_start + i;
                if (idx < frame_symbols)
                {
                    input_block[n_f + i] = frame[idx];
                }
                else
                {
                    input_block[n_f + i].re = 0.0f;
                    input_block[n_f + i].im = 0.0f;
                }
            }
            for (i = 0; i < n_f; i++)
            {
                uint32_t idx = block_start + n_block + i;
                input_block[n_f + n_block + i].re = (idx < frame_symbols) ? frame[idx].re : 0.0f;
                input_block[n_f + n_block + i].im = (idx < frame_symbols) ? frame[idx].im : 0.0f;
            }
            for (i = 0; i < n_f; i++)
            {
                front_tail[i] = input_block[n_block - n_f + i];
            }
            scfde_fft(input_block, fft_len, 0u);
            for (i = 0; i < fft_len; i++)
            {
                filtered[i] = complex_multiply(weights[i], input_block[i]);
            }
            scfde_fft(filtered, fft_len, 1u);
            float scalar_energy = 0.0f;
            for (i = 0; i < n_block; i++)
            {
                scfde_complex_t xhat = filtered[n_f + i];
                scfde_complex_t ref = {0.0f, 0.0f};
                uint32_t idx = block_start + i;
                if (idx < training_length)
                {
                    ref = training[idx % (training_length / 2u)];
                }
                else if (idx < frame_symbols)
                {
                    ref = qpsk_hard_decision(xhat);
                }
                error_spectrum[n_f + i].re = ref.re - xhat.re;
                error_spectrum[n_f + i].im = ref.im - xhat.im;
                scalar_energy += xhat.re * xhat.re + xhat.im * xhat.im;
                if ((idx < frame_symbols) && (idx >= training_length) &&
                    (symbol_cursor < data_symbols))
                {
                    output[symbol_cursor++] = xhat;
                }
            }
            for (i = 0; i < n_f; i++)
            {
                error_spectrum[i].re = 0.0f;
                error_spectrum[i].im = 0.0f;
                error_spectrum[n_f + n_block + i].re = 0.0f;
                error_spectrum[n_f + n_block + i].im = 0.0f;
            }
            scfde_fft(error_spectrum, fft_len, 0u);
            for (i = 0; i < fft_len; i++)
            {
                scfde_complex_t update;
                update.re = error_spectrum[i].re * input_block[i].re +
                            error_spectrum[i].im * input_block[i].im;
                update.im = error_spectrum[i].im * input_block[i].re -
                            error_spectrum[i].re * input_block[i].im;
                float den = scalar_energy + 0.1f;
                weights[i].re += SCFDE_FBLMS_STEP * update.re / den;
                weights[i].im += SCFDE_FBLMS_STEP * update.im / den;
            }
            memcpy(filtered, weights, fft_len * sizeof(scfde_complex_t));
            scfde_fft(filtered, fft_len, 1u);
            memset(weights, 0, fft_len * sizeof(scfde_complex_t));
            for (i = 0; i < n_f; i++)
            {
                weights[i] = filtered[i];
            }
            scfde_fft(weights, fft_len, 0u);
        }
    }
}
/* ------------------------------------------------------------------ */
/* DFE family: known-channel MMSE and adaptive (LMS/NLMS/RLS/DPLL)    */
/* ------------------------------------------------------------------ */

static void dfe_known(const scfde_complex_t *frame, uint16_t frame_symbols,
                      const scfde_complex_t *impulse, uint16_t impulse_taps,
                      float noise_variance, uint16_t training_symbols,
                      uint16_t data_symbols, scfde_complex_t *output)
{
    const uint16_t ff = SCFDE_DFE_FF_TAPS;
    const uint16_t fb = SCFDE_DFE_FB_TAPS;
    uint16_t delay = impulse_taps / 2u;
    uint16_t conv_len;
    uint16_t i, j, n;
    static scfde_complex_t gram[SCFDE_DFE_FF_TAPS * SCFDE_DFE_FF_TAPS];
    static scfde_complex_t rhs[SCFDE_DFE_FF_TAPS];
    /* The equivalent PTR channel is 2*SCFDE_PTR_MAX_TAPS-1 = 55 taps, so the
       combined impulse convolution needs 12+55 = 67 entries. */
    static scfde_complex_t eff[SCFDE_DFE_FF_TAPS + 64u];
    static scfde_complex_t decisions[192];
    uint16_t out_index = 0u;

    if (delay > ff - 1u) { delay = ff - 1u; }
    conv_len = impulse_taps + ff - 1u;
    for (i = 0; i < ff; i++)
    {
        for (j = 0; j < ff; j++)
        {
            float sum_re = 0.0f, sum_im = 0.0f;
            uint16_t k;
            for (k = 0; k < conv_len; k++)
            {
                scfde_complex_t ci = {0.0f, 0.0f}, cj = {0.0f, 0.0f};
                if ((k >= i) && (k - i < impulse_taps)) { ci = impulse[k - i]; }
                if ((k >= j) && (k - j < impulse_taps)) { cj = impulse[k - j]; }
                sum_re += ci.re * cj.re + ci.im * cj.im;
                sum_im += ci.im * cj.re - ci.re * cj.im;
            }
            gram[i * ff + j].re = sum_re;
            gram[i * ff + j].im = sum_im;
        }
        gram[i * ff + i].re += noise_variance;
        /* rhs = C' * e_d: column of the convolution matrix at the target
           delay (impulse[delay - i]), not the unit target itself. */
        if ((i <= delay) && ((delay - i) < impulse_taps))
        {
            rhs[i] = impulse[delay - i];
        }
        else
        {
            rhs[i].re = 0.0f;
            rhs[i].im = 0.0f;
        }
    }
    for (i = 0; i < ff; i++)
    {
        uint16_t pivot = i;
        float best = complex_power(gram[i * ff + i]);
        for (j = i + 1; j < ff; j++)
        {
            float p = complex_power(gram[j * ff + i]);
            if (p > best) { best = p; pivot = j; }
        }
        if (pivot != i)
        {
            for (j = 0; j < ff; j++)
            {
                scfde_complex_t t = gram[i * ff + j];
                gram[i * ff + j] = gram[pivot * ff + j];
                gram[pivot * ff + j] = t;
            }
            {
                scfde_complex_t t = rhs[i];
                rhs[i] = rhs[pivot];
                rhs[pivot] = t;
            }
        }
        for (j = i + 1; j < ff; j++)
        {
            scfde_complex_t factor;
            float den = complex_power(gram[i * ff + i]);
            if (den < 1.0e-12f) { den = 1.0e-12f; }
            factor.re = (gram[j * ff + i].re * gram[i * ff + i].re +
                         gram[j * ff + i].im * gram[i * ff + i].im) / den;
            factor.im = (gram[j * ff + i].im * gram[i * ff + i].re -
                         gram[j * ff + i].re * gram[i * ff + i].im) / den;
            for (n = i; n < ff; n++)
            {
                gram[j * ff + n].re -= factor.re * gram[i * ff + n].re -
                                       factor.im * gram[i * ff + n].im;
                gram[j * ff + n].im -= factor.re * gram[i * ff + n].im +
                                       factor.im * gram[i * ff + n].re;
            }
            rhs[j].re -= factor.re * rhs[i].re - factor.im * rhs[i].im;
            rhs[j].im -= factor.re * rhs[i].im + factor.im * rhs[i].re;
        }
    }
    for (i = ff; i > 0; i--)
    {
        uint16_t row = i - 1u;
        scfde_complex_t x;
        x.re = rhs[row].re;
        x.im = rhs[row].im;
        for (j = row + 1u; j < ff; j++)
        {
            x.re -= gram[row * ff + j].re * g_dfe_weights[j].re -
                    gram[row * ff + j].im * g_dfe_weights[j].im;
            x.im -= gram[row * ff + j].re * g_dfe_weights[j].im +
                    gram[row * ff + j].im * g_dfe_weights[j].re;
        }
        {
            float den = complex_power(gram[row * ff + row]);
            if (den < 1.0e-12f) { den = 1.0e-12f; }
            g_dfe_weights[row].re = (x.re * gram[row * ff + row].re +
                                     x.im * gram[row * ff + row].im) / den;
            g_dfe_weights[row].im = (x.im * gram[row * ff + row].re -
                                     x.re * gram[row * ff + row].im) / den;
        }
    }
    memset(eff, 0, sizeof(eff));
    for (i = 0; i < ff; i++)
    {
        for (j = 0; j < impulse_taps; j++)
        {
            eff[i + j].re += g_dfe_weights[i].re * impulse[j].re -
                             g_dfe_weights[i].im * impulse[j].im;
            eff[i + j].im += g_dfe_weights[i].re * impulse[j].im +
                             g_dfe_weights[i].im * impulse[j].re;
        }
    }
    memset(decisions, 0, sizeof(decisions));
    for (n = 0; n < training_symbols && n < frame_symbols; n++)
    {
        /* Normalize the training decisions to symbol level so the feedback
           taps share one scale with the payload decisions; the raw I&D
           symbols are ~4200x larger and would otherwise dominate feedback. */
        decisions[n] = qpsk_hard_decision(frame[n]);
    }
    for (n = delay; n < frame_symbols && out_index < data_symbols; n++)
    {
        uint32_t obs = (uint32_t)n + delay;
        scfde_complex_t estimate = {0.0f, 0.0f};
        if (obs >= frame_symbols) { break; }
        for (i = 0; i < ff; i++)
        {
            uint32_t idx = obs - i;
            if (idx < frame_symbols)
            {
                estimate.re += g_dfe_weights[i].re * frame[idx].re -
                               g_dfe_weights[i].im * frame[idx].im;
                estimate.im += g_dfe_weights[i].re * frame[idx].im +
                               g_dfe_weights[i].im * frame[idx].re;
            }
        }
        for (i = 0; i < fb; i++)
        {
            uint16_t ch = delay + i + 1;
            if ((ch < (ff + impulse_taps)) && (n >= i + 1u))
            {
                estimate.re -= eff[ch].re * decisions[n - 1u - i].re -
                               eff[ch].im * decisions[n - 1u - i].im;
                estimate.im -= eff[ch].re * decisions[n - 1u - i].im +
                               eff[ch].im * decisions[n - 1u - i].re;
            }
        }
        if (n >= training_symbols && out_index < data_symbols)
        {
            output[out_index++] = estimate;
        }
        if (n >= training_symbols)
        {
            decisions[n] = qpsk_hard_decision(estimate);
        }
    }
}
static void dfe_adaptive(scfde_equalizer_mode_t mode,
                         const scfde_complex_t *frame, uint16_t frame_symbols,
                         const scfde_complex_t *training, uint16_t training_length,
                         uint16_t data_symbols, scfde_complex_t *output)
{
    const uint16_t ff = SCFDE_DFE_FF_TAPS;
    const uint16_t fb = SCFDE_DFE_FB_TAPS;
    const uint16_t delay = SCFDE_DFE_FF_TAPS / 3u;
    uint16_t n, i, k;
    float phase = 0.0f, frequency = 0.0f;
    uint8_t is_rls = (mode == SCFDE_EQUALIZER_RLS_DFE);
    uint8_t is_dpll = (mode == SCFDE_EQUALIZER_DPLL_DFE);
    uint8_t is_lms = (mode == SCFDE_EQUALIZER_LMS_DFE);
    uint16_t first_symbol = (ff > fb + delay) ? ff : (fb + delay + 1u);
    uint16_t last_symbol = (frame_symbols > delay) ? (uint16_t)(frame_symbols - delay) : 0u;
    uint16_t out_index = 0u;
    scfde_complex_t input[SCFDE_DFE_WEIGHTS];
    scfde_complex_t decision_ring[SCFDE_DFE_FB_TAPS];

    memset(g_dfe_weights, 0, sizeof(g_dfe_weights));
    memset(decision_ring, 0, sizeof(decision_ring));
    /* Normalize the received symbols to symbol level (the I&D output is
       ~4200x the unit-energy symbols) so the LMS/NLMS/RLS steps match the
       symbol-level MATLAB link. */
    {
        float scale = 0.0f;
        for (n = 0; n < training_length && n < frame_symbols; n++)
        {
            scale += sqrtf(complex_power(frame[n]));
        }
        scale /= (float)training_length;
        if (scale < 1.0e-6f) { scale = 1.0f; }
        g_dfe_input_power = scale;
    }
    if (is_rls)
    {
        memset(g_dfe_rls, 0, sizeof(g_dfe_rls));
        for (i = 0; i < SCFDE_DFE_WEIGHTS; i++)
        {
            g_dfe_rls[i * SCFDE_DFE_WEIGHTS + i].re = SCFDE_RLS_INIT_INV_CORR;
        }
    }
    for (n = first_symbol; n < last_symbol; n++)
    {
        scfde_complex_t estimate = {0.0f, 0.0f};
        scfde_complex_t decision;
        scfde_complex_t error;
        for (k = 0; k < ff; k++)
        {
            uint32_t idx = (uint32_t)n + delay - k;
            scfde_complex_t v = (idx < frame_symbols) ? frame[idx] :
                                (scfde_complex_t){0.0f, 0.0f};
            input[k].re = v.re / g_dfe_input_power;
            input[k].im = v.im / g_dfe_input_power;
            if (is_dpll)
            {
                float c = cosf(-phase), s = sinf(-phase);
                scfde_complex_t r = input[k];
                input[k].re = r.re * c - r.im * s;
                input[k].im = r.re * s + r.im * c;
            }
        }
        for (k = 0; k < fb; k++)
        {
            input[ff + k].re = -decision_ring[k].re;
            input[ff + k].im = -decision_ring[k].im;
        }
        for (k = 0; k < SCFDE_DFE_WEIGHTS; k++)
        {
            estimate.re += g_dfe_weights[k].re * input[k].re -
                           g_dfe_weights[k].im * input[k].im;
            estimate.im += g_dfe_weights[k].re * input[k].im +
                           g_dfe_weights[k].im * input[k].re;
        }
        if (n < training_length)
        {
            decision = training[n % (training_length / 2u)];
        }
        else
        {
            decision = qpsk_hard_decision(estimate);
            if (out_index < data_symbols)
            {
                output[out_index++] = estimate;
            }
        }
        error.re = decision.re - estimate.re;
        error.im = decision.im - estimate.im;
        if (is_rls)
        {
            scfde_complex_t pv[SCFDE_DFE_WEIGHTS];
            scfde_complex_t gain[SCFDE_DFE_WEIGHTS];
            for (i = 0; i < SCFDE_DFE_WEIGHTS; i++)
            {
                pv[i].re = 0.0f; pv[i].im = 0.0f;
                for (k = 0; k < SCFDE_DFE_WEIGHTS; k++)
                {
                    pv[i].re += g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].re * input[k].re -
                                g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].im * input[k].im;
                    pv[i].im += g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].re * input[k].im +
                                g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].im * input[k].re;
                }
            }
            {
                float denom = SCFDE_RLS_FORGETTING;
                for (k = 0; k < SCFDE_DFE_WEIGHTS; k++)
                {
                    denom += input[k].re * pv[k].re + input[k].im * pv[k].im;
                }
                if (denom < 1.0e-3f) { denom = 1.0e-3f; }
                for (i = 0; i < SCFDE_DFE_WEIGHTS; i++)
                {
                    gain[i].re = pv[i].re / denom;
                    gain[i].im = pv[i].im / denom;
                    g_dfe_weights[i].re += gain[i].re * error.re + gain[i].im * error.im;
                    g_dfe_weights[i].im += gain[i].re * error.im - gain[i].im * error.re;
                }
            }
            /* P = (P - gain * (input' * P)) / lambda, updated only during
               the training segment; the payload segment freezes P and
               uses the converged inverse correlation for w updates.
               (input'*P)[k] = sum_j conj(input[j]) * P[j][k] */
            if (n < training_length)
            {
            for (i = 0; i < SCFDE_DFE_WEIGHTS; i++)
            {
                for (k = 0; k < SCFDE_DFE_WEIGHTS; k++)
                {
                    float q_re = 0.0f, q_im = 0.0f;
                    uint16_t j;
                    for (j = 0; j < SCFDE_DFE_WEIGHTS; j++)
                    {
                        q_re += input[j].re * g_dfe_rls[j * SCFDE_DFE_WEIGHTS + k].re +
                                input[j].im * g_dfe_rls[j * SCFDE_DFE_WEIGHTS + k].im;
                        q_im += input[j].re * g_dfe_rls[j * SCFDE_DFE_WEIGHTS + k].im -
                                input[j].im * g_dfe_rls[j * SCFDE_DFE_WEIGHTS + k].re;
                    }
                    {
                        float gv_re = gain[i].re * q_re - gain[i].im * q_im;
                        float gv_im = gain[i].re * q_im + gain[i].im * q_re;
                        g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].re =
                            (g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].re - gv_re) / SCFDE_RLS_FORGETTING;
                        g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].im =
                            (g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].im - gv_im) / SCFDE_RLS_FORGETTING;
                    }
                }
            }
            /* hermitianize P = (P + P')/2 to keep float32 RLS stable */
            for (i = 0; i < SCFDE_DFE_WEIGHTS; i++)
            {
                for (k = i + 1u; k < SCFDE_DFE_WEIGHTS; k++)
                {
                    float re = (g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].re +
                                g_dfe_rls[k * SCFDE_DFE_WEIGHTS + i].re) * 0.5f;
                    float im = (g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].im -
                                g_dfe_rls[k * SCFDE_DFE_WEIGHTS + i].im) * 0.5f;
                    g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].re = re;
                    g_dfe_rls[i * SCFDE_DFE_WEIGHTS + k].im = im;
                    g_dfe_rls[k * SCFDE_DFE_WEIGHTS + i].re = re;
                    g_dfe_rls[k * SCFDE_DFE_WEIGHTS + i].im = -im;
                }
            }
            /* diagonal loading keeps float32 P positive definite */
            for (i = 0; i < SCFDE_DFE_WEIGHTS; i++)
            {
                g_dfe_rls[i * SCFDE_DFE_WEIGHTS + i].re += 1.0f;
            }
            }
        }
        else
        {
            float power = 1.0e-5f;
            float step;
            if (!is_lms)
            {
                for (k = 0; k < SCFDE_DFE_WEIGHTS; k++)
                {
                    power += complex_power(input[k]);
                }
            }
            step = is_lms ? SCFDE_LMS_STEP : SCFDE_NLMS_STEP;
            for (k = 0; k < SCFDE_DFE_WEIGHTS; k++)
            {
                /* LMS uses the raw step; NLMS/DPLL normalize by input power. */
                float scale = is_lms ? SCFDE_LMS_STEP : (step / power);
                g_dfe_weights[k].re += scale * (input[k].re * error.re + input[k].im * error.im);
                g_dfe_weights[k].im += scale * (input[k].re * error.im - input[k].im * error.re);
            }
        }
        if (is_dpll)
        {
            float phase_error;
            scfde_complex_t ff_est = {0.0f, 0.0f};
            for (k = 0; k < ff; k++)
            {
                ff_est.re += g_dfe_weights[k].re * input[k].re -
                             g_dfe_weights[k].im * input[k].im;
                ff_est.im += g_dfe_weights[k].re * input[k].im +
                             g_dfe_weights[k].im * input[k].re;
            }
            /* phaseError = imag(ff_est * conj(decision)) */
            phase_error = ff_est.im * decision.re - ff_est.re * decision.im;
            frequency += SCFDE_DPLL_INTEGRAL_GAIN * phase_error;
            phase += frequency + SCFDE_DPLL_PROP_GAIN * phase_error;
        }
        for (i = SCFDE_DFE_FB_TAPS - 1u; i > 0u; i--)
        {
            decision_ring[i] = decision_ring[i - 1u];
        }
        decision_ring[0] = decision;
    }
}

static void fdda_equalize(scfde_equalizer_mode_t mode,
                          const scfde_complex_t *frame, uint16_t frame_symbols,
                          const scfde_complex_t *training, uint16_t training_length,
                          uint16_t data_symbols, scfde_complex_t *output);

/* C-grade PTR front end (book 2-47): time-reversed conjugate channel
   matched filter, then a known-channel MMSE DFE on the equivalent channel
   g = h*(-n) * h(n).  Subband PTR (2-48) reduces to the same single-branch
   combination when no branch data is available, so both modes share this
   core (subband_ptr falls back to a single branch in MATLAB). */
static void ptr_dfe_equalize(const scfde_complex_t *frame, uint16_t frame_symbols,
                             const scfde_complex_t *impulse, uint16_t impulse_taps,
                             float noise_variance, uint16_t training_symbols,
                             uint16_t data_symbols, scfde_complex_t *output)
{
    const uint16_t ff = SCFDE_DFE_FF_TAPS;
    const uint16_t fb = SCFDE_DFE_FB_TAPS;
    uint16_t delay = impulse_taps / 2u;
    uint16_t eq_taps;
    uint16_t n, m;
    static scfde_complex_t tr[SCFDE_PTR_MAX_TAPS];
    static scfde_complex_t filtered[192 + SCFDE_PTR_MAX_TAPS];
    static scfde_complex_t eq[SCFDE_PTR_MAX_TAPS * 2u - 1u];
    uint16_t out_index = 0u;

    if ((frame == 0) || (output == 0) || (impulse_taps > SCFDE_PTR_MAX_TAPS))
    {
        return;
    }
    (void)ff;
    (void)fb;
    (void)out_index;
    if (delay > ff - 1u) { delay = ff - 1u; }
    /* timeReversal = conj(fliplr(impulse)); y = filter(TR, 1, received). */
    for (n = 0u; n < impulse_taps; n++)
    {
        tr[n].re = impulse[impulse_taps - 1u - n].re;
        tr[n].im = -impulse[impulse_taps - 1u - n].im;
    }
    for (n = 0u; n < frame_symbols + impulse_taps - 1u; n++)
    {
        filtered[n].re = 0.0f;
        filtered[n].im = 0.0f;
        for (m = 0u; m < impulse_taps; m++)
        {
            if ((m <= n) && ((n - m) < frame_symbols))
            {
                uint32_t idx = n - m;
                filtered[n].re += tr[m].re * frame[idx].re - tr[m].im * frame[idx].im;
                filtered[n].im += tr[m].re * frame[idx].im + tr[m].im * frame[idx].re;
            }
        }
    }
    /* equivalent = conv(TR, impulse), length 2*impulse_taps - 1. */
    memset(eq, 0, (2u * impulse_taps - 1u) * sizeof(scfde_complex_t));
    for (n = 0u; n < impulse_taps; n++)
    {
        for (m = 0u; m < impulse_taps; m++)
        {
            scfde_complex_t p = complex_multiply(tr[n], impulse[m]);
            eq[n + m].re += p.re;
            eq[n + m].im += p.im;
        }
    }
    /* Peak alignment: the TR autocorrelation concentrates energy at the
       center tap (2*impulse_taps-1)/2, which may lie beyond the DFE
       feedforward aperture. Shift both the filtered stream and the
       equivalent channel so the peak lands at the feedforward delay. */
    {
        float best_power = 0.0f;
        uint16_t peak = 0u;
        uint16_t shift;
        for (n = 0u; n < 2u * impulse_taps - 1u; n++)
        {
            float p = complex_power(eq[n]);
            if (p > best_power) { best_power = p; peak = n; }
        }
        shift = (peak > delay) ? (uint16_t)(peak - delay) : 0u;
        if (shift > 0u)
        {
            uint16_t n2;
            for (n2 = 0u; n2 < frame_symbols; n2++)
            {
                filtered[n2] = filtered[n2 + shift];
            }
            for (n2 = 0u; n2 + shift < 2u * impulse_taps - 1u; n2++)
            {
                eq[n2] = eq[n2 + shift];
            }
            eq_taps = (uint16_t)(2u * impulse_taps - 1u - shift);
        }
    }
    /* Known-channel MMSE DFE on the focused stream (shared core). */
    dfe_known(filtered, frame_symbols, eq, eq_taps, noise_variance,
              training_symbols, data_symbols, output);
}

/* C-grade multichannel adaptive DFE (book ch2 multichannel structure):
   B pseudo-branches share one DFE; the second branch is the received
   stream delayed by one symbol (a self-diversity view of a single sensor).
   Training uses the first 64 symbols (UW1|UW2), payload decisions follow. */
static void multichannel_dfe_equalize(scfde_equalizer_mode_t mode,
                                      const scfde_complex_t *frame,
                                      uint16_t frame_symbols,
                                      const scfde_complex_t *training,
                                      uint16_t training_length,
                                      uint16_t data_symbols,
                                      scfde_complex_t *output)
{
    const uint16_t ff = SCFDE_DFE_FF_TAPS;
    const uint16_t fb = SCFDE_DFE_FB_TAPS;
    const uint16_t delay = SCFDE_DFE_FF_TAPS / 3u;
    const uint16_t B = SCFDE_MC_BRANCHES;
    const uint16_t W = SCFDE_MC_WEIGHTS;
    uint16_t n, i, k, b;
    uint8_t is_rls = (mode == SCFDE_EQUALIZER_MC_RLS_DFE);
    uint8_t is_lms = (mode == SCFDE_EQUALIZER_MC_LMS_DFE);
    uint16_t first_symbol = (ff > fb + delay) ? ff : (fb + delay + 1u);
    uint16_t last_symbol = (frame_symbols > delay) ? (uint16_t)(frame_symbols - delay) : 0u;
    uint16_t out_index = 0u;
    scfde_complex_t input[SCFDE_MC_WEIGHTS];
    scfde_complex_t decision_ring[SCFDE_DFE_FB_TAPS];
    float scale = 0.0f;

    if ((frame == 0) || (training == 0) || (output == 0))
    {
        return;
    }
    memset(g_mc_weights, 0, sizeof(g_mc_weights));
    memset(decision_ring, 0, sizeof(decision_ring));
    for (b = 0u; b < B; b++)
    {
        g_mc_weights[b * ff + delay].re = 1.0f / (float)B;
    }
    for (n = 0; n < training_length && n < frame_symbols; n++)
    {
        scale += sqrtf(complex_power(frame[n]));
    }
    scale /= (float)training_length;
    if (scale < 1.0e-6f) { scale = 1.0f; }
    g_dfe_input_power = scale;
    if (is_rls)
    {
        memset(g_mc_rls, 0, sizeof(g_mc_rls));
        for (i = 0; i < W; i++)
        {
            g_mc_rls[i * W + i].re = SCFDE_RLS_INIT_INV_CORR;
        }
    }
    for (n = first_symbol; n < last_symbol; n++)
    {
        scfde_complex_t estimate = {0.0f, 0.0f};
        scfde_complex_t decision;
        scfde_complex_t error;
        for (b = 0u; b < B; b++)
        {
            uint16_t base = b * ff;
            for (k = 0; k < ff; k++)
            {
                uint32_t idx = (uint32_t)n + delay - k - (uint32_t)b;
                scfde_complex_t v = ((idx < frame_symbols) && (b <= (uint32_t)n + delay - k)) ?
                                    frame[idx] : (scfde_complex_t){0.0f, 0.0f};
                input[base + k].re = v.re / scale;
                input[base + k].im = v.im / scale;
            }
        }
        for (k = 0; k < fb; k++)
        {
            input[B * ff + k].re = -decision_ring[k].re;
            input[B * ff + k].im = -decision_ring[k].im;
        }
        for (k = 0; k < W; k++)
        {
            estimate.re += g_mc_weights[k].re * input[k].re -
                           g_mc_weights[k].im * input[k].im;
            estimate.im += g_mc_weights[k].re * input[k].im +
                           g_mc_weights[k].im * input[k].re;
        }
        if (n < training_length)
        {
            decision = training[n % (training_length / 2u)];
        }
        else
        {
            decision = qpsk_hard_decision(estimate);
            if (out_index < data_symbols)
            {
                output[out_index++] = estimate;
            }
        }
        error.re = decision.re - estimate.re;
        error.im = decision.im - estimate.im;
        if (is_rls)
        {
            scfde_complex_t pv[SCFDE_MC_WEIGHTS];
            scfde_complex_t gain[SCFDE_MC_WEIGHTS];
            for (i = 0; i < W; i++)
            {
                pv[i].re = 0.0f; pv[i].im = 0.0f;
                for (k = 0; k < W; k++)
                {
                    pv[i].re += g_mc_rls[i * W + k].re * input[k].re -
                                g_mc_rls[i * W + k].im * input[k].im;
                    pv[i].im += g_mc_rls[i * W + k].re * input[k].im +
                                g_mc_rls[i * W + k].im * input[k].re;
                }
            }
            {
                float denom = SCFDE_RLS_FORGETTING;
                for (k = 0; k < W; k++)
                {
                    denom += input[k].re * pv[k].re + input[k].im * pv[k].im;
                }
                if (denom < 1.0e-3f) { denom = 1.0e-3f; }
                for (i = 0; i < W; i++)
                {
                    gain[i].re = pv[i].re / denom;
                    gain[i].im = pv[i].im / denom;
                    g_mc_weights[i].re += gain[i].re * error.re + gain[i].im * error.im;
                    g_mc_weights[i].im += gain[i].re * error.im - gain[i].im * error.re;
                }
            }
            if (n < training_length)
            {
                for (i = 0; i < W; i++)
                {
                    for (k = 0; k < W; k++)
                    {
                        float q_re = 0.0f, q_im = 0.0f;
                        uint16_t j;
                        for (j = 0; j < W; j++)
                        {
                            q_re += input[j].re * g_mc_rls[j * W + k].re +
                                    input[j].im * g_mc_rls[j * W + k].im;
                            q_im += input[j].re * g_mc_rls[j * W + k].im -
                                    input[j].im * g_mc_rls[j * W + k].re;
                        }
                        {
                            float gv_re = gain[i].re * q_re - gain[i].im * q_im;
                            float gv_im = gain[i].re * q_im + gain[i].im * q_re;
                            g_mc_rls[i * W + k].re =
                                (g_mc_rls[i * W + k].re - gv_re) / SCFDE_RLS_FORGETTING;
                            g_mc_rls[i * W + k].im =
                                (g_mc_rls[i * W + k].im - gv_im) / SCFDE_RLS_FORGETTING;
                        }
                    }
                }
                for (i = 0; i < W; i++)
                {
                    for (k = i + 1u; k < W; k++)
                    {
                        float re = (g_mc_rls[i * W + k].re + g_mc_rls[k * W + i].re) * 0.5f;
                        float im = (g_mc_rls[i * W + k].im - g_mc_rls[k * W + i].im) * 0.5f;
                        g_mc_rls[i * W + k].re = re;
                        g_mc_rls[i * W + k].im = im;
                        g_mc_rls[k * W + i].re = re;
                        g_mc_rls[k * W + i].im = -im;
                    }
                }
            }
        }
        else
        {
            float power = SCFDE_FBLMS_EPSILON;
            float step;
            for (k = 0; k < W; k++)
            {
                power += input[k].re * input[k].re + input[k].im * input[k].im;
            }
            step = is_lms ? SCFDE_LMS_STEP : (SCFDE_NLMS_STEP / power);
            for (k = 0; k < W; k++)
            {
                g_mc_weights[k].re += step * (input[k].re * error.re + input[k].im * error.im);
                g_mc_weights[k].im += step * (input[k].re * error.im - input[k].im * error.re);
            }
        }
        for (i = SCFDE_DFE_FB_TAPS - 1u; i > 0u; i--)
        {
            decision_ring[i] = decision_ring[i - 1u];
        }
        decision_ring[0] = decision;
    }
}


void scfde_equalizer_dfe(scfde_equalizer_mode_t mode,
                         const scfde_complex_t *frame,
                         uint16_t frame_symbols,
                         const scfde_complex_t *training,
                         const scfde_complex_t *impulse,
                         uint16_t impulse_taps,
                         float noise_variance,
                         uint16_t data_symbols,
                         scfde_complex_t *output)
{
    if ((frame == 0) || (output == 0))
    {
        return;
    }
    switch (mode)
    {
    case SCFDE_EQUALIZER_DFE:
        dfe_known(frame, frame_symbols, impulse, impulse_taps, noise_variance,
                  64u, data_symbols, output);
        break;
    case SCFDE_EQUALIZER_PTR_DFE:
    case SCFDE_EQUALIZER_SUBBAND_PTR_DFE:
        ptr_dfe_equalize(frame, frame_symbols, impulse, impulse_taps,
                         noise_variance, 64u, data_symbols, output);
        break;
    case SCFDE_EQUALIZER_MC_LMS_DFE:
    case SCFDE_EQUALIZER_MC_NLMS_DFE:
    case SCFDE_EQUALIZER_MC_RLS_DFE:
        multichannel_dfe_equalize(mode, frame, frame_symbols, training, 64u,
                                  data_symbols, output);
        break;
    case SCFDE_EQUALIZER_LMS_DFE:
    case SCFDE_EQUALIZER_NLMS_DFE:
    case SCFDE_EQUALIZER_RLS_DFE:
    case SCFDE_EQUALIZER_DPLL_DFE:
        dfe_adaptive(mode, frame, frame_symbols, training, 64u,
                     data_symbols, output);
        break;
    case SCFDE_EQUALIZER_FBLMS:
        fblms_equalize(frame, frame_symbols, training, 64u, data_symbols, output);
        break;
    case SCFDE_EQUALIZER_FDDA_TEQ:
    case SCFDE_EQUALIZER_TDDA_TEQ:
    case SCFDE_EQUALIZER_FDDA_DFE_TEQ:
        fdda_equalize(mode, frame, frame_symbols, training, 64u,
                      data_symbols, output);
        break;
    default:
        break;
    }
}
/* A-grade ch3-family entry: HTFDE / SD-IBDFE / HD-IBDFE / ICE variants.
   block: 128-symbol time-domain DATA|UW3; channel_response: H[k] (128);
   impulse: LS impulse (28 taps); ice_training_rx: received UW2 (32) or NULL. */
void scfde_equalizer_apply_a(scfde_equalizer_mode_t mode,
                             const scfde_complex_t *channel_response,
                             const scfde_complex_t *impulse,
                             scfde_complex_t *block,
                             float regularization,
                             uint16_t fft_size,
                             uint16_t data_symbols,
                             const scfde_complex_t *tail_uw,
                             uint16_t tail_uw_length,
                             const scfde_complex_t *ice_training_rx)
{
    static scfde_complex_t training_spectrum[SCFDE_EQUALIZER_MAX_FFT];
    static scfde_complex_t training_rx_spectrum[SCFDE_EQUALIZER_MAX_FFT];
    static scfde_complex_t channel_copy[SCFDE_EQUALIZER_MAX_FFT];
    uint16_t n;

    if ((channel_response == 0) || (block == 0))
    {
        return;
    }
    if (mode == SCFDE_EQUALIZER_HTFDE)
    {
        htfde_equalize(channel_response, block, regularization, fft_size,
                       data_symbols, tail_uw, tail_uw_length, impulse);
        return;
    }
    if ((mode != SCFDE_EQUALIZER_SD_IBDFE) &&
        (mode != SCFDE_EQUALIZER_HD_IBDFE) &&
        (mode != SCFDE_EQUALIZER_ICE_SD_IBDFE) &&
        (mode != SCFDE_EQUALIZER_ICE_HD_IBDFE))
    {
        return;
    }
    memcpy(channel_copy, channel_response, fft_size * sizeof(scfde_complex_t));
    {
        uint8_t soft = (mode == SCFDE_EQUALIZER_SD_IBDFE) ||
                       (mode == SCFDE_EQUALIZER_ICE_SD_IBDFE);
        uint8_t ice = (mode == SCFDE_EQUALIZER_ICE_SD_IBDFE) ||
                      (mode == SCFDE_EQUALIZER_ICE_HD_IBDFE);
        const scfde_complex_t *ts = 0;
        const scfde_complex_t *trs = 0;
        if (ice)
        {
            /* training = UW repeated to fft_size; received training = UW2
               repeated to fft_size */
            for (n = 0; n < fft_size; n++)
            {
                training_spectrum[n] = tail_uw[n % tail_uw_length];
                training_rx_spectrum[n] = (ice_training_rx != 0) ?
                    ice_training_rx[n % tail_uw_length] :
                    tail_uw[n % tail_uw_length];
            }
            scfde_fft(training_spectrum, fft_size, 0u);
            scfde_fft(training_rx_spectrum, fft_size, 0u);
            ts = training_spectrum;
            trs = training_rx_spectrum;
        }
        ibdfe_grade_a(channel_copy, block, regularization, fft_size,
                      data_symbols, tail_uw, tail_uw_length,
                      soft, ice, ts, trs);
        /* write back the refined channel so the modem can report it */
        memcpy((scfde_complex_t *)channel_response, channel_copy,
               fft_size * sizeof(scfde_complex_t));
    }
}

/* ------------------------------------------------------------------ */
/* FDDA family: decision-directed frequency-domain adaptive equalizers */
/* (book Fig. 4-31/4-32, ch4_fdda_teq_core). Shared kernel with the     */
/* FBLMS overlap-save structure plus decision feedback.                */
/* ------------------------------------------------------------------ */

#define SCFDE_FDDA_BLOCK   32u
#define SCFDE_FDDA_FFT     64u
#define SCFDE_FDDA_FILTER  16u
#define SCFDE_FDDA_FB_TAPS 6u
#define SCFDE_FDDA_STEP_F  0.2f
#define SCFDE_FDDA_STEP_B  0.01f
#define SCFDE_FDDA_FORGET  0.97f

static void fdda_equalize(scfde_equalizer_mode_t mode,
                          const scfde_complex_t *frame, uint16_t frame_symbols,
                          const scfde_complex_t *training, uint16_t training_length,
                          uint16_t data_symbols, scfde_complex_t *output)
{
    const uint16_t n_block = SCFDE_FDDA_BLOCK;
    const uint16_t n_f = SCFDE_FDDA_FILTER;
    const uint16_t fft_len = SCFDE_FDDA_FFT;
    static scfde_complex_t weights[SCFDE_FDDA_FFT];
    static scfde_complex_t fb_weights[SCFDE_FDDA_FB_TAPS];
    static scfde_complex_t input_block[SCFDE_FDDA_FFT];
    static scfde_complex_t filtered[SCFDE_FDDA_FFT];
    static scfde_complex_t error_spectrum[SCFDE_FDDA_FFT];
    static scfde_complex_t front_tail[SCFDE_FDDA_FILTER];
    static scfde_complex_t decision_ring[SCFDE_FDDA_FB_TAPS];
    uint16_t block_index, n;
    uint16_t symbol_cursor = 0u;
    uint8_t use_fb = (mode == SCFDE_EQUALIZER_FDDA_DFE_TEQ);

    static float fdda_scale;   /* set at the top of fdda_equalize */    memset(weights, 0, sizeof(weights));
    memset(fb_weights, 0, sizeof(fb_weights));
    memset(front_tail, 0, sizeof(front_tail));
    memset(decision_ring, 0, sizeof(decision_ring));
    {
        uint16_t total_blocks;
        float scale = 0.0f;
        for (n = 0; n < training_length && n < frame_symbols; n++)
        {
            scale += sqrtf(complex_power(frame[n]));
        }
        scale /= (float)training_length;
        fdda_scale = (scale < 1.0e-6f) ? 1.0f : scale;
        total_blocks = (uint16_t)((frame_symbols + n_block - 1u) / n_block);
        for (block_index = 0; block_index < total_blocks; block_index++)
        {
            uint32_t block_start = (uint32_t)block_index * n_block;
            uint16_t i;
            for (i = 0; i < n_f; i++)
            {
                input_block[i] = front_tail[i];
            }
            for (i = 0; i < n_block; i++)
            {
                uint32_t idx = block_start + i;
                if (idx < frame_symbols)
                {
                    input_block[n_f + i].re = frame[idx].re / fdda_scale;
                    input_block[n_f + i].im = frame[idx].im / fdda_scale;
                }
                else
                {
                    input_block[n_f + i].re = 0.0f;
                    input_block[n_f + i].im = 0.0f;
                }
            }
            for (i = 0; i < n_f; i++)
            {
                uint32_t idx = block_start + n_block + i;
                input_block[n_f + n_block + i].re = (idx < frame_symbols) ? frame[idx].re : 0.0f;
                input_block[n_f + n_block + i].im = (idx < frame_symbols) ? frame[idx].im : 0.0f;
            }
            for (i = 0; i < n_f; i++)
            {
                front_tail[i] = input_block[n_block - n_f + i];
            }
            scfde_fft(input_block, fft_len, 0u);
            for (i = 0; i < fft_len; i++)
            {
                filtered[i] = complex_multiply(weights[i], input_block[i]);
            }
            scfde_fft(filtered, fft_len, 1u);
            {
                float scalar_energy = 0.0f;
                for (i = 0; i < n_block; i++)
                {
                    scfde_complex_t xhat = filtered[n_f + i];
                    scfde_complex_t ref = {0.0f, 0.0f};
                    uint32_t idx = block_start + i;
                    /* decision feedback term (DFE variant) */
                    if (use_fb && idx > 0u)
                    {
                        uint16_t k;
                        for (k = 0u; k < SCFDE_FDDA_FB_TAPS && (idx - 1u - k) < frame_symbols; k++)
                        {
                            uint32_t d_idx = idx - 1u - k;
                            scfde_complex_t d = (d_idx < training_length) ?
                                training[d_idx % (training_length / 2u)] : decision_ring[k];
                            xhat.re -= fb_weights[k].re * d.re - fb_weights[k].im * d.im;
                            xhat.im -= fb_weights[k].re * d.im + fb_weights[k].im * d.re;
                        }
                    }
                    if (idx < training_length)
                    {
                        ref = training[idx % (training_length / 2u)];
                    }
                    else if (idx < frame_symbols)
                    {
                        ref = qpsk_hard_decision(xhat);
                    }
                    error_spectrum[n_f + i].re = ref.re - xhat.re;
                    error_spectrum[n_f + i].im = ref.im - xhat.im;
                    scalar_energy += xhat.re * xhat.re + xhat.im * xhat.im;
                    if ((idx < frame_symbols) && (idx >= training_length) &&
                        (symbol_cursor < data_symbols))
                    {
                        output[symbol_cursor++] = xhat;
                    }
                    /* decision ring update */
                    {
                        uint16_t k2;
                        for (k2 = SCFDE_FDDA_FB_TAPS - 1u; k2 > 0u; k2--)
                        {
                            decision_ring[k2] = decision_ring[k2 - 1u];
                        }
                    }
                    decision_ring[0] = ref;
                }
                for (i = 0; i < n_f; i++)
                {
                    error_spectrum[i].re = 0.0f;
                    error_spectrum[i].im = 0.0f;
                    error_spectrum[n_f + n_block + i].re = 0.0f;
                    error_spectrum[n_f + n_block + i].im = 0.0f;
                }
                scfde_fft(error_spectrum, fft_len, 0u);
                for (i = 0; i < fft_len; i++)
                {
                    scfde_complex_t update;
                    update.re = error_spectrum[i].re * input_block[i].re +
                                error_spectrum[i].im * input_block[i].im;
                    update.im = error_spectrum[i].im * input_block[i].re -
                                error_spectrum[i].re * input_block[i].im;
                    float den = scalar_energy + 0.1f;
                    weights[i].re += SCFDE_FDDA_STEP_F * update.re / den;
                    weights[i].im += SCFDE_FDDA_STEP_F * update.im / den;
                }
                /* time constraint: first n_f taps only */
                memcpy(filtered, weights, fft_len * sizeof(scfde_complex_t));
                scfde_fft(filtered, fft_len, 1u);
                memset(weights, 0, fft_len * sizeof(scfde_complex_t));
                for (i = 0; i < n_f; i++)
                {
                    weights[i] = filtered[i];
                }
                scfde_fft(weights, fft_len, 0u);
                /* feedback tap update (DFE variant) */
                if (use_fb)
                {
                    uint16_t k;
                    for (k = 0u; k < SCFDE_FDDA_FB_TAPS; k++)
                    {
                        fb_weights[k].re += SCFDE_FDDA_STEP_B * decision_ring[k].re *
                                            error_spectrum[n_f].re;
                        fb_weights[k].im += SCFDE_FDDA_STEP_B * decision_ring[k].im *
                                            error_spectrum[n_f].im;
                    }
                }
            }
        }
    }
}
