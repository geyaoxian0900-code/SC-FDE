#include "main.h"
#include "scfde_app.h"
#include <stdio.h>

/**
 * @file main.c
 * @brief Minimal hardware bring-up followed by the foreground application.
 *
 * Initialization order matters: console first for diagnostics, then DAC/ADC,
 * external direction control, and finally DSP lookup tables and modem state.
 *
 * DEBUG: STEP prints after every init to locate a startup hang/fault on
 * hardware bring-up. Remove before release.
 */

static void step(const char *tag)
{
    printf("STEP[%s]\r\n", tag);
}

int main(void)
{
    system_init();
    usart0_init();
    step("usart0_init");
    passband_tx_init();
    step("passband_tx_init");
    passband_rx_init();
    step("passband_rx_init");
    half_duplex_init();
    step("half_duplex_init");
    scfde_modem_init();
    step("scfde_modem_init");

    printf("SCFDE banner follows\r\n");
    scfde_app_run();
    while(1)
    {
    }
}
