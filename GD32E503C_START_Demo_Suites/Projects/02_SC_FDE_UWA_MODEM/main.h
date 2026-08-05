#ifndef MAIN_H
#define MAIN_H

/* Common application-facing BSP and modem interfaces. Algorithm modules do
 * not include this aggregate header; they include only their dependencies. */
#include "gd32e50x.h"
#include "bsp_usart.h"
#include "bsp_half_duplex.h"
#include "bsp_passband_tx.h"
#include "bsp_passband_rx.h"
#include "scfde_modem.h"

#endif
