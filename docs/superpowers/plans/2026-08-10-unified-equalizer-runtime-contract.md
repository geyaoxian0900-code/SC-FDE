# 37 Equalizer Runtime Contract Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all 37 registered MATLAB equalizers execute through the correct chapter scenario, return BER in the correct metric domain, preserve caller RNG state, and produce exact per-method confidence-interval metadata.

**Architecture:** Keep the Chapter-4 transmitted frame unchanged as `[256 known training; 1024 interleaved convolutionally coded BPSK symbols]`. Introduce one validated frame descriptor and one decoder-feedback adapter so full-frame equalizers operate on 1280 samples while BCJR sees only the 1024 coded-data samples and returns exactly 512 information decisions. Normalize all scenario metrics to per-equalizer exact count vectors, then add a registry-driven runner that executes all 37 IDs independently and records failures without masking later methods.

**Tech Stack:** MATLAB R2024a, MATLAB function-based unit tests, existing `+scfde` package modules, Git result metadata.

## Global Constraints

- Preserve the original Chapter-4 parameters: 256 training symbols, 512 information bits, rate-1/2 `(7,5)_8` convolutional code, 1024 coded symbols and three outer iterations.
- Never fix a dimension mismatch by truncating `bits`, `info`, LLRs or permutations.
- The scenario owns the interleaver. Equalizer modules must consume `cfg.permutation` and must not call `rng` or `randperm`.
- Training samples participate in full-frame equalization and feedback as known symbols but never enter BCJR.
- Every Chapter-4 module exposed through the turbo scenario returns exactly 512 hard information-symbol decisions in `outputs{1}`.
- `errorBits` and `totalBits` remain exact integer counts; do not reconstruct them with `round(ber .* totalBits)`.
- Preserve the audited FDDA-TEQ equations (4-75), (4-81) and (4-82) and their current numerical tests.
- Keep `equalizers="all"` backward-compatible as the existing 17-method QPSK bank; use the new audit runner for all 37 IDs.

---

## File Structure

### Create

- `papers/modules/+scfde/+equalizers/ch4_turbo_frame_contract.m` — validates and describes training/data/information ranges and the scenario interleaver.
- `papers/modules/+scfde/+equalizers/ch4_decoder_feedback_frame.m` — slices full-frame LLRs, runs BCJR on coded data only, and rebuilds a full feedback frame.
- `papers/run_all_equalizers.m` — executes each registry ID using its declared scenario and returns a 37-row audit table.
- `papers/tests/test_all_equalizer_runtime_contracts.m` — focused negative regressions and all-37 smoke coverage.

### Delete

- `papers/modules/+scfde/+equalizers/ch4_decoder_feedback.m` — obsolete full-frame-to-BCJR helper replaced by the explicit frame-aware adapter; all callers migrate in Tasks 3 and 4.

### Modify

- `papers/modules/+scfde/equalizer_registry.m` — add chapter and scenario metadata.
- Chapter-4 shared helpers/kernels:
  - `ch4_initial_soft_feedback.m`
  - `ch4_frequency_dfe_baseline.m`
  - `ch4_iterate_time_turbo.m`
  - `ch4_iterate_frequency_turbo.m`
  - `ch4_iterate_time_frequency_turbo.m`
  - `ch4_iterate_td_nlms_turbo.m`
  - `ch4_iterate_fd_blms_turbo.m`
- Chapter-4 wrappers:
  - `td_turbo.m`, `fd_dfe.m`, `fd_turbo.m`, `tf_turbo.m`
  - `bitf_turbo.m`, `blms_tf_turbo.m`, `tdda_teq.m`
  - `fdda_dfe_teq.m`, `fblms.m`
- `papers/run_unified_equalizer.m` — exact vector statistics and explicit CCK minimum-frame validation.
- `papers/README.md`, root `README.md`, `FORMULA_TRACEABILITY.md` — document output-domain and runtime evidence.
- `papers/modules/+scfde/receiver_bank_pluggable.m`, `papers/modules/+scfde/+equalizers/pack_equalizer.m` — align contract comments with scenario-domain outputs.

---

### Task 1: Lock the Chapter-4 Frame Contract with Failing Tests

**Files:**
- Create: `papers/tests/test_all_equalizer_runtime_contracts.m`
- Create: `papers/modules/+scfde/+equalizers/ch4_turbo_frame_contract.m`

**Interfaces:**
- Consumes: `channel.received`, `source.training`, `source.data`, `cfg.trainingSymbols`, `cfg.infoBits`, `cfg.permutation`.
- Produces: scalar struct with `frameLength`, `trainingLength`, `codedLength`, `informationLength`, `trainingIndices`, `dataIndices`, `trainingSymbols`, `informationBits`, `informationSymbols`, `permutation`, `inversePermutation`.

- [ ] **Step 1: Add failing contract tests**

```matlab
function tests = test_all_equalizer_runtime_contracts
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testTurboFrameContractUsesOnlyCodedData(testCase)
rng(42, "twister");
training = 1 - 2 * randi([0 1], 1, 256);
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
tx = [training, 1 - 2 * coded(permutation)];
channel = struct("received", tx);
source = struct("training", training, "data", 1 - 2 * information, "tx", tx);
cfg = struct("trainingSymbols", 256, "infoBits", 512, ...
    "permutation", permutation);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
verifyEqual(testCase, frame.trainingIndices, 1:256);
verifyEqual(testCase, frame.dataIndices, 257:1280);
verifyEqual(testCase, frame.codedLength, 1024);
verifyEqual(testCase, frame.informationLength, 512);
verifyEqual(testCase, frame.inversePermutation(permutation), 1:1024);
end

function testTurboFrameContractRejectsFrameLengthMismatch(testCase)
channel = struct("received", ones(1, 1279));
source = struct("training", ones(1, 256), "data", ones(1, 512));
cfg = struct("trainingSymbols", 256, "infoBits", 512, ...
    "permutation", 1:1024);
verifyError(testCase, ...
    @() scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg), ...
    "SCFDE:TurboFrame");
end

function testTurboFrameContractRejectsInvalidPermutation(testCase)
channel = struct("received", ones(1, 1280));
source = struct("training", ones(1, 256), "data", ones(1, 512));
cfg = struct("trainingSymbols", 256, "infoBits", 512, ...
    "permutation", [1:1023, 1023]);
verifyError(testCase, ...
    @() scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg), ...
    "SCFDE:TurboPermutation");
end
```

- [ ] **Step 2: Run the focused tests and confirm the helper is missing**

Run:

```powershell
matlab -batch "addpath('papers'); addpath('papers/modules'); r=runtests('papers/tests/test_all_equalizer_runtime_contracts.m'); assert(~all([r.Passed]));"
```

Expected: failures report undefined `scfde.equalizers.ch4_turbo_frame_contract`.

- [ ] **Step 3: Implement the validated frame descriptor**

```matlab
function frame = ch4_turbo_frame_contract(channel, source, cfg)
received = channel.received(:).';
training = source.training(:).';
trainingLength = field_required(cfg, "trainingSymbols");
informationLength = field_required(cfg, "infoBits");
expectedCodedLength = 2 * informationLength;
if trainingLength ~= numel(training) || ...
        numel(received) ~= trainingLength + expectedCodedLength
    error("SCFDE:TurboFrame", ...
        "Expected %d training + %d coded samples; received %d samples.", ...
        trainingLength, expectedCodedLength, numel(received));
end
permutation = field_required(cfg, "permutation");
permutation = permutation(:).';
if numel(permutation) ~= expectedCodedLength || ...
        ~isequal(sort(permutation), 1:expectedCodedLength)
    error("SCFDE:TurboPermutation", ...
        "cfg.permutation must be a permutation of 1:%d.", expectedCodedLength);
end
informationSymbols = source.data(:).';
if numel(informationSymbols) ~= informationLength
    error("SCFDE:TurboFrame", ...
        "source.data must contain exactly %d information symbols.", ...
        informationLength);
end
inversePermutation = zeros(1, expectedCodedLength);
inversePermutation(permutation) = 1:expectedCodedLength;
frame = struct( ...
    "frameLength", numel(received), ...
    "trainingLength", trainingLength, ...
    "codedLength", expectedCodedLength, ...
    "informationLength", informationLength, ...
    "trainingIndices", 1:trainingLength, ...
    "dataIndices", trainingLength + (1:expectedCodedLength), ...
    "trainingSymbols", training, ...
    "informationSymbols", informationSymbols, ...
    "informationBits", double(informationSymbols < 0), ...
    "permutation", permutation, ...
    "inversePermutation", inversePermutation);
end

function value = field_required(cfg, name)
if ~isfield(cfg, name) || isempty(cfg.(name))
    error("SCFDE:TurboFrame", "Missing required cfg.%s.", name);
end
value = cfg.(name);
end
```

- [ ] **Step 4: Run focused tests**

Run the Step 2 command without the negative `assert` wrapper. Expected: all three tests pass.

- [ ] **Step 5: Commit the contract**

```powershell
git add papers/tests/test_all_equalizer_runtime_contracts.m papers/modules/+scfde/+equalizers/ch4_turbo_frame_contract.m
git commit -m "test: define chapter4 turbo frame contract"
```

---

### Task 2: Centralize BCJR Slicing and Full-Frame Feedback

**Files:**
- Create: `papers/modules/+scfde/+equalizers/ch4_decoder_feedback_frame.m`
- Test: `papers/tests/test_all_equalizer_runtime_contracts.m`

**Interfaces:**
- `ch4_decoder_feedback_frame(equalizerLlr, frame, previousSoftFrame, damping, decoderMode)` returns `[bits, decoderLlrFrame, softFrame, informationLlr, codedLlr]`.
- All row-vector outputs use transmitted frame order; only the internal BCJR input uses original coded order.

- [ ] **Step 1: Add a perfect-LLR regression test**

```matlab
function testDecoderFeedbackExcludesTrainingFromBcjr(testCase)
rng(7, "twister");
training = 1 - 2 * randi([0 1], 1, 256);
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
tx = [training, 1 - 2 * coded(permutation)];
frame = scfde.equalizers.ch4_turbo_frame_contract( ...
    struct("received", tx), ...
    struct("training", training, "data", 1 - 2 * information, "tx", tx), ...
    struct("trainingSymbols", 256, "infoBits", 512, ...
        "permutation", permutation));
llr = 50 * tx;
previous = [training, zeros(1, 1024)];
[bits, decoderFrame, softFrame] = ...
    scfde.equalizers.ch4_decoder_feedback_frame( ...
        llr, frame, previous, 1, "Log-MAP");
verifyEqual(testCase, numel(bits), 512);
verifyEqual(testCase, bits, logical(information));
verifyEqual(testCase, softFrame(frame.trainingIndices), training);
verifyEqual(testCase, decoderFrame(frame.trainingIndices), zeros(1, 256));
verifySize(testCase, decoderFrame, [1, 1280]);
verifySize(testCase, softFrame, [1, 1280]);
end
```

- [ ] **Step 2: Confirm failure before implementation**

Run the focused test file. Expected: undefined decoder-feedback helper.

- [ ] **Step 3: Implement BCJR slicing and frame reconstruction**

```matlab
function [bits, decoderLlrFrame, softFrame, informationLlr, codedLlr] = ...
        ch4_decoder_feedback_frame(equalizerLlr, frame, ...
        previousSoftFrame, damping, decoderMode)
equalizerLlr = equalizerLlr(:).';
previousSoftFrame = previousSoftFrame(:).';
if numel(equalizerLlr) ~= frame.frameLength || ...
        numel(previousSoftFrame) ~= frame.frameLength
    error("SCFDE:TurboFrame", ...
        "Equalizer LLR and feedback frame must have %d elements.", ...
        frame.frameLength);
end
dataLlrTxOrder = equalizerLlr(frame.dataIndices);
decoderInput = dataLlrTxOrder(frame.inversePermutation);
[informationLlr, codedLlr] = ...
    scfde.equalizers.ch4_bcjr_siso_decode(decoderInput, decoderMode);
if numel(informationLlr) ~= frame.informationLength || ...
        numel(codedLlr) ~= frame.codedLength
    error("SCFDE:TurboDecoder", ...
        "BCJR returned %d information and %d coded LLRs.", ...
        numel(informationLlr), numel(codedLlr));
end
extrinsicOriginalOrder = codedLlr - decoderInput;
extrinsicTxOrder = extrinsicOriginalOrder(frame.permutation);
posteriorTxOrder = codedLlr(frame.permutation);
candidate = tanh(posteriorTxOrder / 2);
softFrame = previousSoftFrame;
softFrame(frame.trainingIndices) = frame.trainingSymbols;
softFrame(frame.dataIndices) = ...
    (1 - damping) * previousSoftFrame(frame.dataIndices) + damping * candidate;
decoderLlrFrame = zeros(1, frame.frameLength);
decoderLlrFrame(frame.dataIndices) = extrinsicTxOrder;
bits = informationLlr < 0;
end
```

- [ ] **Step 4: Run the focused tests and existing BCJR tests**

```powershell
matlab -batch "addpath('papers'); addpath('papers/modules'); r=runtests({'papers/tests/test_all_equalizer_runtime_contracts.m','papers/tests/test_fblms_and_curve_benchmark.m'}); assertSuccess(r);"
```

- [ ] **Step 5: Commit the shared decoder contract**

```powershell
git add papers/modules/+scfde/+equalizers/ch4_decoder_feedback_frame.m papers/tests/test_all_equalizer_runtime_contracts.m
git commit -m "fix: separate chapter4 training from BCJR data"
```

---

### Task 3: Migrate TD-Turbo, FD-DFE and FD-Turbo

**Files:**
- Modify: `ch4_iterate_time_turbo.m`, `ch4_frequency_dfe_baseline.m`, `ch4_iterate_frequency_turbo.m`
- Modify: `td_turbo.m`, `fd_dfe.m`, `fd_turbo.m`
- Test: `papers/tests/test_all_equalizer_runtime_contracts.m`

**Interfaces:**
- Each wrapper creates `frame = ch4_turbo_frame_contract(channel, source, cfg)` and passes it to its kernel.
- Each kernel returns `bits` of length `frame.informationLength`.
- Exact migrated signatures:
  - `ch4_iterate_time_turbo(received, channelMatrix, timeEqualizer, noiseVariance, frame, cfg, decoderMode)`
  - `ch4_frequency_dfe_baseline(Y, H, noiseVariance, frame, cfg)`
  - `ch4_iterate_frequency_turbo(Y, Hest, Hreference, noiseVariance, frame, cfg, decoderMode, adaptiveChannel)`

- [ ] **Step 1: Add three-module runtime and direct-wrapper RNG regressions**

```matlab
function testBasicTurboModulesReturnInformationDomain(testCase)
ids = ["td-turbo", "fd-dfe", "fd-turbo"];
for id = ids
    result = run_unified_equalizer(struct("equalizers", id, ...
        "scenario", "turbo", "frameCount", 1, ...
        "snrDb", 18, "makePlot", false, "randomSeed", 42));
    verifyEqual(testCase, numel(result.ber), 1);
    verifyEqual(testCase, result.totalBits, 512);
    verifyTrue(testCase, isfinite(result.ber) && result.ber >= 0 && result.ber <= 1);
end
end

function testBasicTurboWrappersPreserveRng(testCase)
[channel, source, cfg] = buildTurboFixture();
registry = scfde.equalizer_registry();
ids = ["td-turbo", "fd-dfe", "fd-turbo"];
for id = ids
    match = find(registry.id == id, 1);
    before = rng;
    receiver = registry.module{match}(channel, source, cfg);
    after = rng;
    verifyEqual(testCase, after, before, ...
        "Equalizer wrapper must not mutate caller RNG state");
    verifyEqual(testCase, numel(receiver.outputs{1}), 512);
end
end

function [channel, source, cfg] = buildTurboFixture()
rng(42, "twister");
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
training = 1 - 2 * randi([0 1], 1, 256);
tx = [training, 1 - 2 * coded(permutation)];
impulse = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
H = fft([impulse, zeros(1, numel(tx) - numel(impulse))]);
noiseVariance = 10^(-18 / 10);
received = ifft(H .* fft(tx)) + sqrt(noiseVariance / 2) * ...
    (randn(size(tx)) + 1j * randn(size(tx)));
channel = struct("received", received, "impulse", impulse, ...
    "branches", [received; received]);
source = struct("training", training, "data", 1 - 2 * information, ...
    "tx", tx);
cfg = struct("noiseVariance", noiseVariance, "iterations", 3, ...
    "trainingSymbols", 256, "infoBits", 512, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
    "baselineDecoder", "Log-MAP", "turboDamping", 0.75, ...
    "tdAdaptiveTaps", 16, "tdNlmsStep", 0.35, ...
    "blmsStep", 0.2, "blmsLeakage", 1e-3, ...
    "blmsRegularization", 1e-3, "fddaStepFf", 0.2, ...
    "fddaStepFb", 0.01, "fddaBlockLength", 32, ...
    "fddaFfLength", 32, "fddaFbLength", 10);
end
```

- [ ] **Step 2: Run and confirm the existing dimension failures**

Expected failing locations: `ch4_iterate_time_turbo:22`, `ch4_frequency_dfe_baseline:13`, `ch4_iterate_frequency_turbo:29`.

- [ ] **Step 3: Update each kernel to use full-frame feedback and data-only BCJR**

Use this exact iteration pattern in time and frequency kernels:

```matlab
softSymbols = zeros(1, frame.frameLength);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
for iteration = 1:cfg.iterations
    % Existing full-frame equalizer calculation remains unchanged.
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, ...
            cfg.turboDamping, decoderMode);
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, ...
        equalizerLlr, decoderLlr, softSymbols, channelNmse);
end
```

For `ch4_frequency_dfe_baseline`, call the helper once with a previous frame containing known training and zero data; repeat its trace values for configured iterations.

- [ ] **Step 4: Remove local RNG/interleaver creation from all three wrappers**

Replace `info`, `rng(2024)`, `randperm(N)` and inverse-permutation construction with:

```matlab
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
```

Pass `frame` to the migrated kernel and keep `decisions = 1 - 2 * bits`.

Use these exact calls:

| Wrapper | Kernel call after migration |
|---|---|
| `td_turbo.m` | `ch4_iterate_time_turbo(channel.received, channelMatrix, timeEqualizer, cfg.noiseVariance, frame, cfg, cfg.turboDecoderMode)` |
| `fd_dfe.m` | `ch4_frequency_dfe_baseline(fft(channel.received), H, cfg.noiseVariance, frame, cfg)` |
| `fd_turbo.m` | `ch4_iterate_frequency_turbo(fft(channel.received), H, H, cfg.noiseVariance, frame, cfg, cfg.turboDecoderMode, false)` |

- [ ] **Step 5: Run the focused tests**

Expected: all three IDs return scalar BER, `totalBits=512`, no dimension errors, and direct wrapper calls preserve RNG state.

- [ ] **Step 6: Commit**

```powershell
git add papers/modules/+scfde/+equalizers/ch4_iterate_time_turbo.m papers/modules/+scfde/+equalizers/ch4_frequency_dfe_baseline.m papers/modules/+scfde/+equalizers/ch4_iterate_frequency_turbo.m papers/modules/+scfde/+equalizers/td_turbo.m papers/modules/+scfde/+equalizers/fd_dfe.m papers/modules/+scfde/+equalizers/fd_turbo.m papers/tests/test_all_equalizer_runtime_contracts.m
git commit -m "fix: align basic turbo equalizers with coded data frame"
```

---

### Task 4: Migrate TF/BiTF/BLMS-TF/TDDA/FDDA-DFE Kernels

**Files:**
- Modify: `ch4_initial_soft_feedback.m`, `ch4_iterate_time_frequency_turbo.m`, `ch4_iterate_td_nlms_turbo.m`, `ch4_iterate_fd_blms_turbo.m`
- Delete: `ch4_decoder_feedback.m` after its final two callers migrate.
- Modify: `tf_turbo.m`, `bitf_turbo.m`, `blms_tf_turbo.m`, `tdda_teq.m`, `fdda_dfe_teq.m`
- Test: `papers/tests/test_all_equalizer_runtime_contracts.m`

**Interfaces:**
- Exact migrated signatures:
  - `ch4_iterate_time_frequency_turbo(received, Y, channelMatrix, timeEqualizer, Hest, Hreference, noiseVariance, frame, cfg, bidirectional, adaptiveChannel)`
  - `ch4_iterate_td_nlms_turbo(received, Y, Hinitial, Hreference, noiseVariance, frame, cfg)`
  - `ch4_iterate_fd_blms_turbo(Y, Hinitial, Hreference, noiseVariance, frame, cfg, useDecisionFeedback)`

- [ ] **Step 1: Add a five-module failing runtime test**

```matlab
function testAdvancedTurboModulesReturnInformationDomain(testCase)
ids = ["tf-turbo", "bitf-turbo", "blms-tf-turbo", ...
    "tdda-teq", "fdda-dfe-teq"];
for id = ids
    result = run_unified_equalizer(struct("equalizers", id, ...
        "scenario", "turbo", "frameCount", 1, ...
        "snrDb", 18, "makePlot", false, "randomSeed", 42));
    verifyEqual(testCase, result.totalBits, 512);
    verifyTrue(testCase, isfinite(result.ber) && result.ber >= 0 && result.ber <= 1);
end
end
```

- [ ] **Step 2: Confirm all five tests fail at their current `mean(bits ~= info)` calls**

Expected failures are in `ch4_iterate_time_frequency_turbo`, `ch4_iterate_td_nlms_turbo` and `ch4_iterate_fd_blms_turbo`.

- [ ] **Step 3: Apply the Task-3 full-frame feedback pattern to all three kernels**

Exact required differences:

| Kernel | Initial feedback | Decoder mode | Full-frame adaptive residual |
|---|---|---|---|
| `ch4_iterate_time_frequency_turbo` | known training + zero data | `Log-MAP` | existing channel update uses rebuilt `softSymbols` |
| `ch4_iterate_td_nlms_turbo` | `ch4_initial_soft_feedback(..., frame, cfg)` | `Log-MAP` | `residual` remains length 1280 |
| `ch4_iterate_fd_blms_turbo` | `ch4_initial_soft_feedback(..., frame, cfg)` | `Log-MAP` | `residual = softSymbols - estimate` remains length 1280 |

Every `curve(iteration)` must compare against `frame.informationBits`, never a separately truncated `info` vector.

Replace `ch4_initial_soft_feedback` with this frame-aware implementation before migrating TDDA and FDDA-DFE:

```matlab
function softFrame = ch4_initial_soft_feedback(Y, Hinitial, ...
        noiseVariance, frame, cfg)
initialEstimate = ifft( ...
    scfde.equalizers.ch4_normalized_mmse(Hinitial, noiseVariance) .* Y);
initialLlr = 2 * real(initialEstimate) / noiseVariance;
previous = zeros(1, frame.frameLength);
previous(frame.trainingIndices) = frame.trainingSymbols;
[~, ~, softFrame] = scfde.equalizers.ch4_decoder_feedback_frame( ...
    initialLlr, frame, previous, cfg.turboDamping, "Log-MAP");
end
```

- [ ] **Step 4: Migrate all five wrappers**

For each file, delete its `rng(2024)`, `randperm(N)`, inverse-permutation and local `info` construction. Create the validated `frame` once and pass it to the kernel:

| Wrapper | Kernel call after migration |
|---|---|
| `tf_turbo.m` | `ch4_iterate_time_frequency_turbo(channel.received, fft(channel.received), channelMatrix, timeEqualizer, H, H, cfg.noiseVariance, frame, cfg, false, false)` |
| `bitf_turbo.m` | `ch4_iterate_time_frequency_turbo(channel.received, fft(channel.received), channelMatrix, timeEqualizer, H, H, cfg.noiseVariance, frame, cfg, true, false)` |
| `blms_tf_turbo.m` | `ch4_iterate_time_frequency_turbo(channel.received, fft(channel.received), channelMatrix, timeEqualizer, H, H, cfg.noiseVariance, frame, cfg, false, true)` |
| `tdda_teq.m` | `ch4_iterate_td_nlms_turbo(channel.received, fft(channel.received), Hinitial, Hinitial, cfg.noiseVariance, frame, cfg)` |
| `fdda_dfe_teq.m` | `ch4_iterate_fd_blms_turbo(fft(channel.received), Hinitial, Hinitial, cfg.noiseVariance, frame, cfg, true)` |

- [ ] **Step 5: Add direct-wrapper RNG-state checks for the five IDs**

Capture `before = rng`, invoke the wrapper on a prebuilt deterministic frame, capture `after = rng`, and use `verifyEqual(testCase, after, before)`.

After both old callers have migrated, delete `ch4_decoder_feedback.m`. Confirm `Select-String -Path 'papers/modules/+scfde/+equalizers/*.m' -Pattern 'ch4_decoder_feedback\('` returns no callers.

- [ ] **Step 6: Run focused tests and commit**

```powershell
git rm papers/modules/+scfde/+equalizers/ch4_decoder_feedback.m
git add papers/modules/+scfde/+equalizers/ch4_initial_soft_feedback.m papers/modules/+scfde/+equalizers/ch4_iterate_time_frequency_turbo.m papers/modules/+scfde/+equalizers/ch4_iterate_td_nlms_turbo.m papers/modules/+scfde/+equalizers/ch4_iterate_fd_blms_turbo.m papers/modules/+scfde/+equalizers/tf_turbo.m papers/modules/+scfde/+equalizers/bitf_turbo.m papers/modules/+scfde/+equalizers/blms_tf_turbo.m papers/modules/+scfde/+equalizers/tdda_teq.m papers/modules/+scfde/+equalizers/fdda_dfe_teq.m papers/tests/test_all_equalizer_runtime_contracts.m
git commit -m "fix: migrate advanced turbo equalizers to frame contract"
```

---

### Task 5: Normalize FBLMS to the Turbo Information Domain

**Files:**
- Modify: `papers/modules/+scfde/+equalizers/fblms.m`
- Test: `papers/tests/test_all_equalizer_runtime_contracts.m`

- [ ] **Step 1: Add a failing output-domain test**

```matlab
function testFblmsTurboReturnsDecodedInformation(testCase)
result = run_unified_equalizer(struct("equalizers", "fblms", ...
    "scenario", "turbo", "frameCount", 1, "snrDb", 18, ...
    "makePlot", false, "randomSeed", 42));
verifyEqual(testCase, result.totalBits, 512);
verifyTrue(testCase, result.ber >= 0 && result.ber <= 1);
trace = result.traces{1};
verifyEqual(testCase, trace.outputDomain, "information-symbols");
verifyEqual(testCase, numel(trace.equalizedFrame), 1280);
end
```

- [ ] **Step 2: Confirm the current module reports frame-symbol output and BER=1 for the fixed seed**

- [ ] **Step 3: Decode only when a turbo frame contract is present**

After `fblms_equalizer` returns `output`, retain the current QPSK behavior when no permutation exists. For turbo mode use:

```matlab
if isfield(cfg, "permutation") && ~isempty(cfg.permutation)
    frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
    dataEqualized = output(frame.dataIndices);
    amplitude = mean(abs(real(dataEqualized)));
    llrFrame = zeros(1, frame.frameLength);
    llrFrame(frame.dataIndices) = 2 * real(dataEqualized) / ...
        max(amplitude, 1e-12) / max(cfg.noiseVariance, 1e-6);
    previous = zeros(1, frame.frameLength);
    previous(frame.trainingIndices) = frame.trainingSymbols;
    [bits, ~] = scfde.equalizers.ch4_decoder_feedback_frame( ...
        llrFrame, frame, previous, 1, cfg.turboDecoderMode);
    decisions = 1 - 2 * bits;
    trace.equalizedFrame = output;
    trace.outputDomain = "information-symbols";
else
    decisions = output(1:min(numel(output), numel(reference)));
    trace.outputDomain = "frame-symbols";
end
```

- [ ] **Step 4: Protect the existing QPSK FBLMS regression**

Run `testFblmsProductionEntryReproducible` and confirm its fixed-seed count/CI behavior remains unchanged.

- [ ] **Step 5: Commit**

```powershell
git add papers/modules/+scfde/+equalizers/fblms.m papers/tests/test_all_equalizer_runtime_contracts.m
git commit -m "fix: decode fblms output in turbo scenario"
```

---

### Task 6: Make BER Counts and Confidence Intervals Shape-Safe

**Files:**
- Modify: `papers/run_unified_equalizer.m`
- Test: `papers/tests/test_all_equalizer_runtime_contracts.m`

- [ ] **Step 1: Add failing multi-method CCK/CSK tests**

```matlab
function testCckAndCskReturnPerMethodExactCounts(testCase)
cases = { ...
    struct("equalizers", {{"cck-rake", "cck-dfe"}}, ...
        "scenario", "cck", "symbols", 8), ...
    struct("equalizers", {{"csk-matched-filter", "csk-ese"}}, ...
        "scenario", "csk", "symbols", 8)};
for k = 1:numel(cases)
    cfg = cases{k};
    cfg.frameCount = 1;
    cfg.makePlot = false;
    cfg.randomSeed = 42;
    result = run_unified_equalizer(cfg);
    verifySize(testCase, result.ber, [1, 2]);
    verifySize(testCase, result.errorBits, [1, 2]);
    verifySize(testCase, result.totalBits, [1, 2]);
    verifyEqual(testCase, result.ber, ...
        result.errorBits ./ result.totalBits, "AbsTol", 0);
    verifyTrue(testCase, all(result.ber >= result.berLower95 & ...
        result.ber <= result.berUpper95));
end
end
```

- [ ] **Step 2: Confirm both cases fail in `clopper_pearson_95`**

- [ ] **Step 3: Return exact counts from every scenario**

At the end of QPSK, Turbo, CCK and CSK scenario functions set:

```matlab
results.errorBits = totalErrors;
results.totalBits = totalBits;
results.ber = totalErrors ./ totalBits;
```

Initialize and increment `totalBits` as a row vector with one element per equalizer. For CCK/CSK/Turbo, create it immediately after the first receiver bank result:

```matlab
totalBits = zeros(1, numel(recv.ids));
```

Inside each equalizer loop increment `totalBits(eq)` by the exact number of compared reference bits.

- [ ] **Step 4: Replace floating reconstruction in common postprocessing**

```matlab
if isfield(results, "totalBits") && isfield(results, "errorBits")
    errors = double(results.errorBits(:).');
    bits = double(results.totalBits(:).');
    if isscalar(bits) && ~isscalar(errors)
        bits = repmat(bits, size(errors));
    end
    if ~isequal(size(errors), size(bits)) || ...
            numel(errors) ~= numel(results.ids) || ...
            any(bits <= 0) || any(errors < 0) || any(errors > bits)
        error("SCFDE:MetricShape", ...
            "errorBits and totalBits must be valid per-equalizer vectors.");
    end
    results.errorBits = errors;
    results.totalBits = bits;
    results.ber = errors ./ bits;
    [results.berLower95, results.berUpper95] = ...
        clopper_pearson_95(errors, bits);
    results.reachedTarget = bits >= 1;
end
```

- [ ] **Step 5: Add explicit CCK short-frame behavior**

Before slicing `chips(1:32)`:

```matlab
if cfg.symbols < 4
    error("SCFDE:FrameTooShort", ...
        "CCK scenario requires at least 4 eight-chip symbols for 32 training chips.");
end
```

Add a test calling `symbols=3` and expecting `SCFDE:FrameTooShort`, replacing the current accidental indexing exception.

- [ ] **Step 6: Run the focused tests and commit**

```powershell
git add papers/run_unified_equalizer.m papers/tests/test_all_equalizer_runtime_contracts.m
git commit -m "fix: preserve exact per-equalizer BER counts"
```

---

### Task 7: Add Registry Metadata and the All-37 Audit Runner

**Files:**
- Modify: `papers/modules/+scfde/equalizer_registry.m`
- Create: `papers/run_all_equalizers.m`
- Test: `papers/tests/test_all_equalizer_runtime_contracts.m`

**Interfaces:**
- Registry adds arrays `chapter` and `scenario` parallel to `id` and `module`.
- `run_all_equalizers(options)` returns a table with 37 rows and columns `id`, `chapter`, `scenario`, `status`, `ber`, `errorBits`, `totalBits`, `berLower95`, `berUpper95`, `durationSeconds`, `message`.

- [ ] **Step 1: Add registry metadata tests**

```matlab
function testRegistryHasCompleteScenarioMetadata(testCase)
registry = scfde.equalizer_registry();
verifyEqual(testCase, numel(registry.id), 37);
verifyEqual(testCase, numel(registry.chapter), 37);
verifyEqual(testCase, numel(registry.scenario), 37);
verifyEqual(testCase, sum(registry.scenario == "qpsk"), 17);
verifyEqual(testCase, sum(registry.scenario == "turbo"), 10);
verifyEqual(testCase, sum(registry.scenario == "cck"), 7);
verifyEqual(testCase, sum(registry.scenario == "csk"), 3);
end
```

- [ ] **Step 2: Add registry metadata**

```matlab
chapters = [repmat(2, 1, 10), repmat(3, 1, 7), ...
    repmat(4, 1, 10), repmat(5, 1, 7), repmat(6, 1, 3)];
scenarios = [repmat("qpsk", 1, 17), repmat("turbo", 1, 10), ...
    repmat("cck", 1, 7), repmat("csk", 1, 3)];
registry = struct("id", {ids}, "module", {modules}, ...
    "chapter", {chapters}, "scenario", {scenarios});
```

- [ ] **Step 3: Implement isolated per-ID execution**

```matlab
function report = run_all_equalizers(options)
if nargin < 1, options = struct(); end
rootDir = fileparts(mfilename("fullpath"));
addpath(fullfile(rootDir, "modules"));
frameCount = field_default(options, "frameCount", 1);
snrDb = field_default(options, "snrDb", 18);
symbols = field_default(options, "symbols", 8);
randomSeed = field_default(options, "randomSeed", 42);
registry = scfde.equalizer_registry();
n = numel(registry.id);
rows = repmat(struct("id", "", "chapter", 0, "scenario", "", ...
    "status", "", "ber", NaN, "errorBits", NaN, "totalBits", NaN, ...
    "berLower95", NaN, "berUpper95", NaN, "durationSeconds", NaN, ...
    "message", ""), 1, n);
for k = 1:n
    timer = tic;
    rows(k).id = registry.id(k);
    rows(k).chapter = registry.chapter(k);
    rows(k).scenario = registry.scenario(k);
    try
        result = run_unified_equalizer(struct( ...
            "equalizers", registry.id(k), ...
            "scenario", registry.scenario(k), ...
            "frameCount", frameCount, "snrDb", snrDb, ...
            "symbols", symbols, "makePlot", false, ...
            "randomSeed", randomSeed));
        rows(k).status = "PASS";
        rows(k).ber = result.ber(1);
        rows(k).errorBits = result.errorBits(1);
        rows(k).totalBits = result.totalBits(1);
        rows(k).berLower95 = result.berLower95(1);
        rows(k).berUpper95 = result.berUpper95(1);
    catch exception
        rows(k).status = "ERROR";
        rows(k).message = string(getReport(exception, ...
            "extended", "hyperlinks", "off"));
    end
    rows(k).durationSeconds = toc(timer);
end
report = struct2table(rows);
report.Properties.UserData = struct("gitCommit", git_commit_short(), ...
    "matlabVersion", version, "timestamp", datetime("now"), ...
    "randomSeed", randomSeed);
end

function value = field_default(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end

function commit = git_commit_short()
commit = "";
try
    repoDir = string(fileparts(fileparts(mfilename("fullpath"))));
    [status, out] = system("git -C """ + repoDir + ...
        """ rev-parse --short HEAD 2>nul");
    if status == 0
        commit = strtrim(string(out));
    end
catch
    commit = "";
end
end
```

- [ ] **Step 4: Add the all-37 smoke test**

```matlab
function testAll37EqualizersCompleteSmokeRun(testCase)
report = run_all_equalizers(struct("frameCount", 1, ...
    "snrDb", 18, "symbols", 8, "randomSeed", 42));
verifyEqual(testCase, height(report), 37);
verifyEqual(testCase, sum(report.status == "PASS"), 37, ...
    strjoin(report.message(report.status ~= "PASS"), newline));
verifyTrue(testCase, all(isfinite(report.ber)));
verifyTrue(testCase, all(report.ber >= 0 & report.ber <= 1));
verifyTrue(testCase, all(report.errorBits >= 0));
verifyTrue(testCase, all(report.totalBits > 0));
verifyTrue(testCase, all(report.ber >= report.berLower95 & ...
    report.ber <= report.berUpper95));
end
```

- [ ] **Step 5: Commit**

```powershell
git add papers/modules/+scfde/equalizer_registry.m papers/run_all_equalizers.m papers/tests/test_all_equalizer_runtime_contracts.m
git commit -m "feat: add all-37 equalizer audit runner"
```

---

### Task 8: Full Regression and Formula-Safety Gates

**Files:**
- Test: all files under `papers/tests/`
- Verify: `FORMULA_TRACEABILITY.md`, FDDA reference MAT files and quick simulation outputs.

- [ ] **Step 1: Run Check Code on every modified MATLAB file**

```powershell
matlab -batch "files={'papers/run_unified_equalizer.m','papers/run_all_equalizers.m','papers/modules/+scfde/equalizer_registry.m','papers/modules/+scfde/+equalizers/ch4_turbo_frame_contract.m','papers/modules/+scfde/+equalizers/ch4_decoder_feedback_frame.m','papers/modules/+scfde/+equalizers/ch4_initial_soft_feedback.m','papers/modules/+scfde/+equalizers/ch4_frequency_dfe_baseline.m','papers/modules/+scfde/+equalizers/ch4_iterate_time_turbo.m','papers/modules/+scfde/+equalizers/ch4_iterate_frequency_turbo.m','papers/modules/+scfde/+equalizers/ch4_iterate_time_frequency_turbo.m','papers/modules/+scfde/+equalizers/ch4_iterate_td_nlms_turbo.m','papers/modules/+scfde/+equalizers/ch4_iterate_fd_blms_turbo.m','papers/modules/+scfde/+equalizers/td_turbo.m','papers/modules/+scfde/+equalizers/fd_dfe.m','papers/modules/+scfde/+equalizers/fd_turbo.m','papers/modules/+scfde/+equalizers/tf_turbo.m','papers/modules/+scfde/+equalizers/bitf_turbo.m','papers/modules/+scfde/+equalizers/blms_tf_turbo.m','papers/modules/+scfde/+equalizers/tdda_teq.m','papers/modules/+scfde/+equalizers/fdda_dfe_teq.m','papers/modules/+scfde/+equalizers/fblms.m'}; for k=1:numel(files), m=checkcode(files{k},'-id'); fprintf('%s: %d findings\n',files{k},numel(m)); for j=1:numel(m), fprintf('  L%d %s %s\n',m(j).line,m(j).id,m(j).message); end; end"
```

Expected: every file parses; review and remove every new finding introduced by this repair. Pre-existing unrelated style findings must be listed explicitly in the verification log.

- [ ] **Step 2: Run all unit tests fresh**

```powershell
matlab -batch "addpath('papers'); addpath('papers/modules'); r=runtests('papers/tests'); disp(table(r)); assertSuccess(r);"
```

Required result: zero failed and zero incomplete tests, including all existing FDDA equation tests.

- [ ] **Step 3: Run the isolated all-37 smoke audit**

```powershell
matlab -batch "addpath('papers'); addpath('papers/modules'); report=run_all_equalizers(struct('frameCount',1,'snrDb',18,'symbols',8,'randomSeed',42)); disp(report(:,{'id','scenario','status','ber','errorBits','totalBits'})); assert(all(report.status=='PASS'));"
```

- [ ] **Step 4: Run multi-method scenario integration tests**

Run each chapter group in one receiver bank call to catch vector-shape and shared-state faults:

```matlab
groups = { ...
    {"dfe","lms-dfe","nlms-dfe","rls-dfe","dpll-dfe", ...
     "mc-lms-dfe","mc-nlms-dfe","mc-rls-dfe","ptr-dfe", ...
     "subband-ptr-dfe","mmse-fde","zf-fde","htfde", ...
     "sd-ibdfe","hd-ibdfe","ice-sd-ibdfe","ice-hd-ibdfe"}, ...
    {"td-turbo","fd-dfe","fd-turbo","tf-turbo","bitf-turbo", ...
     "blms-tf-turbo","fblms","tdda-teq","fdda-teq","fdda-dfe-teq"}, ...
    {"cck-rake","cck-dfe","cck-bidfe","cck-bidfe2", ...
     "cck-tr-diversity","cck-fde","cck-mfb"}, ...
    {"csk-matched-filter","csk-soft-sic","csk-ese"}};
scenarios = ["qpsk","turbo","cck","csk"];
for k = 1:4
    result = run_unified_equalizer(struct("equalizers", groups{k}, ...
        "scenario", scenarios(k), "frameCount", 1, ...
        "symbols", 8, "makePlot", false, "randomSeed", 42));
    assert(numel(result.ber) == numel(groups{k}));
    assert(isequal(size(result.ber), size(result.errorBits), size(result.totalBits)));
end
```

- [ ] **Step 5: Run a reproducibility check**

Run `run_all_equalizers` twice at 4 dB with the same seed and assert equality of ID, status, `errorBits`, `totalBits` and BER. Run once more at 4 dB with a different seed and assert that at least one error count changes while IDs, scenarios and bit-count dimensions remain unchanged. The lower SNR prevents an all-zero-error comparison from making the different-seed assertion ineffective.

Also add `testAllTurboWrappersPreserveRng`, using `buildTurboFixture` and direct registry module calls for all ten Chapter-4 IDs. This test asserts identical caller RNG state and exactly 512 returned information decisions for every wrapper.

- [ ] **Step 6: Commit the final acceptance tests**

```powershell
git status --short
git add papers/tests/test_all_equalizer_runtime_contracts.m
git commit -m "test: verify all 37 equalizer runtime contracts"
```

If the test file did not change during this task, do not create an empty commit. Do not include regenerated MAT files or unrelated workspace changes in this source commit.

---

### Task 9: Documentation, BER Table and Auditable Result Artifacts

**Files:**
- Modify: `README.md`, `papers/README.md`, `FORMULA_TRACEABILITY.md`
- Modify: `papers/modules/+scfde/receiver_bank_pluggable.m`, `papers/modules/+scfde/+equalizers/pack_equalizer.m`
- Generate: `papers/results/all_37_equalizers_quick.mat`
- Generate: `papers/results/all_37_equalizers_quick.csv`

- [ ] **Step 1: Correct the receiver-output contract documentation**

Document these exact scenario domains:

| Scenario | `outputs{1}` metric domain |
|---|---|
| QPSK | data-symbol estimates; full-frame TDE outputs are sliced by the metric adapter |
| Turbo | 512 information-symbol decisions after BCJR |
| CCK | chip estimates plus detected codeword indices in trace |
| CSK | spreading-sequence estimates plus detected cyclic-shift indices in trace |

Apply the same wording to the function headers in `receiver_bank_pluggable.m` and `pack_equalizer.m`; do not continue claiming universal `source.tx` alignment.

- [ ] **Step 2: Record the new runtime evidence**

Add to `FORMULA_TRACEABILITY.md`:

- 37/37 registry-to-module mapping;
- 37/37 one-frame execution;
- 17/10/7/3 scenario grouping;
- Chapter-4 training/data/BCJR contract;
- exact vector `errorBits/totalBits` and Clopper-Pearson CI;
- known algorithmic grades A/B/C remain unchanged by runtime repair.

- [ ] **Step 3: Commit documentation with the source tree**

```powershell
git add README.md papers/README.md FORMULA_TRACEABILITY.md papers/modules/+scfde/receiver_bank_pluggable.m papers/modules/+scfde/+equalizers/pack_equalizer.m
git commit -m "docs: record all-37 runtime contract audit"
```

- [ ] **Step 4: Generate quick BER artifacts from the clean source commit**

Use five frames per ID for a quick table while retaining exact confidence intervals:

```powershell
matlab -batch "addpath('papers'); addpath('papers/modules'); report=run_all_equalizers(struct('frameCount',5,'snrDb',18,'symbols',8,'randomSeed',42)); metadata=report.Properties.UserData; save('papers/results/all_37_equalizers_quick.mat','report','metadata'); writetable(report,'papers/results/all_37_equalizers_quick.csv'); assert(height(report)==37 && all(report.status=='PASS'));"
```

Do not interpret zero errors as exact BER zero; report `[berLower95, berUpper95]`.

- [ ] **Step 5: Verify artifact metadata before committing**

```powershell
$env:EXPECTED_CODE_COMMIT = (git rev-parse --short HEAD).Trim()
matlab -batch "S=load('papers/results/all_37_equalizers_quick.mat'); assert(string(S.metadata.gitCommit)==string(getenv('EXPECTED_CODE_COMMIT'))); assert(height(S.report)==37); assert(all(S.report.status=='PASS'));"
```

- [ ] **Step 6: Commit only result artifacts**

```powershell
git add papers/results/all_37_equalizers_quick.mat papers/results/all_37_equalizers_quick.csv
git commit -m "results: add traceable 37-equalizer BER table"
```

- [ ] **Step 7: Final repository gate**

```powershell
git status --short --branch
git log -3 --oneline
```

Required: clean worktree; artifact commit has the verified source commit as its parent; MAT metadata points to that parent source commit.

---

## Acceptance Matrix

| Gate | Required result |
|---|---|
| Registry integrity | 37 IDs, 37 modules, chapters/scenarios lengths all 37 |
| Chapter grouping | QPSK 17, Turbo 10, CCK 7, CSK 3 |
| Turbo frame | 256 training + 1024 coded; BCJR input 1024; output 512 information decisions |
| Interleaver | Exactly `cfg.permutation`; no module-owned `rng(2024)`/`randperm(N)` |
| RNG | Direct calls to all Chapter-4 wrappers preserve caller RNG state |
| FBLMS | QPSK retains frame-symbol behavior; Turbo returns decoded information decisions |
| Statistics | `ber`, `errorBits`, `totalBits`, CI bounds all one-per-ID and shape-identical |
| Exact counts | `ber == errorBits ./ totalBits`; integer `0 <= errorBits <= totalBits` |
| CI | Every BER lies within its Clopper-Pearson 95% interval |
| CCK boundary | `symbols<4` raises `SCFDE:FrameTooShort`, not an indexing exception |
| Unit regression | All existing and new tests pass; FDDA numerical equivalence remains at `1e-12` |
| Runtime smoke | 37/37 IDs status `PASS`, no NaN/Inf BER |
| Multi-method integration | All four chapter groups complete in bank mode without shape errors |
| Reproducibility | Same seed reproduces exact errors/counts; result metadata identifies source commit |
| Documentation | Runtime completion is not confused with formula grade; A/B/C classifications retained |

## Explicit Non-Goals

- Do not tune equalizer parameters merely to improve the one-frame BER table.
- Do not claim BER=0 as proven error-free performance.
- Do not change original channel, code, modulation or FDDA equation parameters during this repair.
- Do not combine QPSK, Turbo, CCK and CSK modules into one incompatible receiver-bank frame.
