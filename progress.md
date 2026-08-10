# Progress: 37 Equalizer Runtime Repair Plan

## 2026-08-10

- Read planning-with-files, writing-plans and MATLAB skill instructions.
- Confirmed there were no existing root planning files or active plan to merge.
- Recorded the observed Chapter-4 and CCK/CSK failures from direct MATLAB executions.
- Created persistent planning files; production code remains unchanged.
- Read all six affected Chapter-4 iteration kernels plus shared decoder/trace helpers.
- Chose a shared frame-contract and decoder-feedback migration rather than eight local truncation fixes.
- Mapped the receiver contract, all affected wrappers/kernels, statistics entry point and proposed all-37 audit runner.
- Saved the complete nine-task TDD plan under `docs/superpowers/plans/`.
- Self-review corrected two plan defects: RNG tests now call wrappers directly, and the obsolete decoder helper is deleted only after all callers migrate so intermediate commits remain runnable.
- Confirmed the plan contains no placeholder tasks and includes source/result commit separation for exact metadata traceability.
