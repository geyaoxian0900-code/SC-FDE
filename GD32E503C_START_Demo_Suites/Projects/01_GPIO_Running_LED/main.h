#ifndef MAIN_H
#define MAIN_H

#include "bsp_usart.h"
#include "bsp_half_duplex.h"
#include "bsp_passband_tx.h"
#include "bsp_passband_rx.h"
#include "uwa_modem.h"

typedef enum
{
    APP_MODE_TEST = 0,
    APP_MODE_WORK = 1
} app_mode_t;

#endif
