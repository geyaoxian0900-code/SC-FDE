#ifndef SCFDE_APP_H
#define SCFDE_APP_H

/**
 * Run the blocking serial user interface and node-role state machine.
 * This function owns the foreground loop and normally never returns.
 */
void scfde_app_run(void);

#endif
