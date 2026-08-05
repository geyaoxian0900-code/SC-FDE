#include "scfde_equalizer.h"
#include <string.h>

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

static scfde_complex_t g_received_spectrum[SCFDE_EQUALIZER_MAX_FFT];
static scfde_complex_t g_decision_spectrum[SCFDE_EQUALIZER_MAX_FFT];
static scfde_complex_t g_tde_input[SCFDE_EQUALIZER_MAX_FFT];

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
        "AUTO", "MMSE-FDE", "ZF-FDE", "MF-FDE", "IB-DFE", "NLMS-TDE"
    };
    if((uint8_t)mode >= (uint8_t)SCFDE_EQUALIZER_COUNT)
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
