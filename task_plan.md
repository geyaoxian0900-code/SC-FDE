# 37 Equalizer Runtime Repair Plan

## Goal

Produce a complete, test-driven modification plan that makes all 37 registered equalizer modules execute through their intended scenario, return metrics in a consistent domain, preserve RNG state, and generate auditable BER results.

## Current Phase

Phase 5 complete

## Phases

### Phase 1: Establish Observed Failures and Contracts

- [x] Record direct MATLAB reproduction results.
- [x] Define the Chapter-4 frame and metric contracts.
- **Status:** complete

### Phase 2: Map Affected Production Files

- [x] Map all wrappers, kernels, metrics and documentation files.
- [x] Identify helpers to create and retire.
- **Status:** complete

### Phase 3: Design the TDD Implementation Sequence

- [x] Split the repair into independently testable tasks.
- [x] Include failing tests, implementation interfaces and commit boundaries.
- **Status:** complete

### Phase 4: Define the 37-Method Acceptance Matrix

- [x] Define isolated and grouped runtime gates.
- [x] Define RNG, BER, CI, formula and metadata gates.
- **Status:** complete

### Phase 5: Save and Self-Review the Final Plan

- [x] Save `docs/superpowers/plans/2026-08-10-unified-equalizer-runtime-contract.md`.
- [x] Scan for placeholders and inconsistent interfaces.
- **Status:** complete

## Constraints

- Do not truncate decoded bits merely to silence dimension errors.
- The Chapter-4 frame remains `[256 training; 1024 coded BPSK data]`, with 512 information bits and a 1024-entry scenario-owned interleaver.
- Equalizer modules must not reset the caller's global RNG.
- BER metadata must preserve exact per-equalizer error and bit counts.
- Formula-correct FDDA-TEQ behavior and existing 40 unit tests must remain intact.
- Planning only in this turn; no MATLAB production-code modifications.

## Errors Encountered

| Error | Attempt | Resolution |
|---|---|---|
| Initial session-catchup command used the `.codex` skill path and returned exit 1 | 1 | Located the installed skill under `.agents` and reran successfully |
