# MATLAB Simulation Index

> The maintained, unified simulation tree is now `../../../../papers/`.
> Files in this directory remain as compatibility copies for the MCU demo.
> New batch runs should use `papers/run_all_simulations.m`.

## Main Entry Points

- `launch_scfde_text_app`: interactive text-to-waveform-to-text demonstration.
- `run_text_scfde_demo`: programmable end-to-end SC-FDE text link.
- `run_all_scfde_simulations`: runs Chapter 2 through Chapter 6 suites.
- `verify_scfde_project`: checks required files and the GD32E503CE target.

Quick regression run:

```matlab
summary = run_all_scfde_simulations(struct("profile","quick"));
```

Full run:

```matlab
summary = run_all_scfde_simulations(struct("profile","full"));
```

Select chapters with `struct("chapters",[3 5 6])`. Generated figures and the
batch summary are written to `results/`.

## Chapter Mapping

| Chapter | Script | Main coverage |
|---|---|---|
| 2 | `simulate_chapter2_single_carrier_tde` | DFE, NLMS, PLL, multichannel and passive time reversal |
| 3 | `simulate_chapter3_scfde` | SC-FDE, synchronization, joint equalization and IB-DFE |
| 4 | `simulate_chapter4_iterative_equalization` | Coded Turbo and time-frequency iterative equalization |
| 5 | `simulate_chapter5_cck` | CCK families, ISI reception, Turbo detection and CCK-SM |
| 6 | `simulate_chapter6_csk_multiuser` | CSK, multiuser detection, IDMA and CSK-IDMA |

Chapter 3 and Chapter 6 measured-channel hooks accept replaceable lake trial
impulse responses. Built-in reference-channel curves are demonstrations, not
exact reproductions of unavailable lake data.
