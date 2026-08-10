# Findings: 37 Equalizer Runtime Repair

## Confirmed runtime failures

- Chapter 4, one-frame turbo scenario:
  - Dimension errors: `td-turbo`, `fd-dfe`, `fd-turbo`, `tf-turbo`, `bitf-turbo`, `blms-tf-turbo`, `tdda-teq`, `fdda-dfe-teq`.
  - Runs but reports semantically invalid information BER: `fblms` returns frame/coded-symbol-domain output and is compared against 512 information bits.
  - Valid information-bit output: `fdda-teq`.
- CCK and CSK multi-method scenarios execute receivers but fail in the common Clopper-Pearson postprocessor because `ber/errorBits` are vectors and `totalBits` is scalar.
- CCK with fewer than four 8-chip symbols fails earlier at the fixed `chips(1:32)` training slice.

## Root causes

- Eight legacy Chapter-4 wrappers regenerate `randperm(N)` with `N=1280`, ignore `cfg.permutation` of length 1024, reset global RNG, and send the complete training-plus-data frame into the rate-1/2 BCJR decoder. This yields 640 decoded bits rather than 512.
- Iterative kernels assume every equalized sample belongs to the coded data stream; they lack explicit training/data masks and cannot rebuild a full feedback frame from known training plus decoded soft data.
- Receiver outputs do not have an explicit domain contract. `fdda-teq` returns information decisions, while `fblms` returns frame-symbol estimates; the turbo metric assumes all outputs are information decisions.
- The common metric layer reconstructs `errorBits` from floating BER and assumes `totalBits` has the same shape.

## Target contract

- Turbo frame descriptor: training range 1:256, coded-data range 257:1280, information length 512, coded length 1024, scenario-owned permutation length 1024.
- Turbo receiver output: exactly 512 hard information-symbol decisions; traces may additionally expose equalized coded symbols and full-frame soft feedback.
- Scenario result vectors: `ber`, `errorBits`, `totalBits`, CI bounds and `reachedTarget` all have one element per returned equalizer ID.

## Kernel migration implications

- The iterative kernels allocate full-frame `softSymbols` and traces of length 1280, but currently pass full-frame LLRs to BCJR. The repair must keep full-frame equalization while slicing only `dataIndices` before deinterleaving/decoding.
- Decoder feedback must return both:
  - 1024 coded-data soft symbols in transmitted/interleaved order; and
  - a 1280 full-frame feedback vector assembled as `[knownTraining, codedSoftData]`.
- `ch4_decoder_feedback` and `ch4_initial_soft_feedback` are the best shared boundaries to migrate first; this avoids eight wrappers duplicating slicing and reassembly.
- `ch4_save_trace` currently requires decoder LLR and equalizer LLR arrays to match the full trace width. The new decoder helper should expose a full-frame decoder-LLR vector with zeros (or documented known-symbol values) in the training positions, while preserving the 1024 data-domain LLR separately if needed.
- `fblms` must either decode its equalized data segment before packaging or explicitly declare a coded/frame-symbol output domain. For the existing turbo scenario contract, decoding inside the wrapper is the smaller compatible change.
- `ch4_frequency_dfe_baseline` is non-iterative but has the same full-frame BCJR misuse and must use the common frame descriptor.

## Additional consistency issue

- Eight legacy Chapter-4 wrappers reset global RNG with `rng(2024)` and generate `randperm(N)`. All must consume `cfg.permutation`; validation must reject missing/wrong-length permutations rather than silently regenerate them.

## Receiver-contract finding

- `papers/README.md` currently says `outputs{1}` aligns with `source.tx`, but the turbo metric and `fdda-teq` use information-symbol output aligned with `source.data`. The repair will standardize Chapter-4 wrappers on 512 information decisions and update the documentation to state that the scenario defines the metric-domain output.
- `receiver_bank_pluggable` does not need a breaking interface change if every Chapter-4 wrapper normalizes to the turbo scenario's information domain before calling `pack_equalizer`.

## Planned production file map

- Create shared Chapter-4 contract helpers:
  - `ch4_turbo_frame_contract.m`
  - `ch4_decoder_feedback_frame.m`
- Delete the obsolete `ch4_decoder_feedback.m` after all callers migrate; keeping both would leave a callable helper with the old invalid full-frame BCJR contract.
- Modify shared Chapter-4 helpers/kernels:
  - `ch4_initial_soft_feedback.m`
  - `ch4_frequency_dfe_baseline.m`
  - `ch4_iterate_time_turbo.m`
  - `ch4_iterate_frequency_turbo.m`
  - `ch4_iterate_time_frequency_turbo.m`
  - `ch4_iterate_td_nlms_turbo.m`
  - `ch4_iterate_fd_blms_turbo.m`
- Modify wrappers:
  - `td_turbo.m`, `fd_dfe.m`, `fd_turbo.m`, `tf_turbo.m`, `bitf_turbo.m`, `blms_tf_turbo.m`, `tdda_teq.m`, `fdda_dfe_teq.m`, `fblms.m`.
- Preserve `fdda_teq_true.m` behavior; use it as the working frame-contract reference and add output-length regression protection.
- Modify `run_unified_equalizer.m` to return exact vector counts from every scenario and add explicit CCK short-frame validation.
- Create `run_all_equalizers.m` for grouped 17/10/7/3 execution and a combined 37-row audit table.
- Create `papers/tests/test_all_equalizer_runtime_contracts.m` for focused contract and all-37 smoke tests.
