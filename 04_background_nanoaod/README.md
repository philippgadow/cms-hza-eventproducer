# Background btvNanoAllPF Production

Reprocess centrally-produced MiniAOD into **BTV NanoAOD with all PF candidates**
(`BTVCustomNanoAOD_allPF`) for the H → Za background samples.

## Overview

The input MiniAOD datasets are listed directly in `datasets.txt`
(from the `RunIII2024Summer24MiniAODv6` campaign).

## Parameters

| Parameter | Value |
|-----------|-------|
| CMSSW release | `CMSSW_15_0_18` (`el9_amd64_gcc12`) |
| Global tag | `150X_mcRun3_2024_realistic_v2` |
| Era | `Run3_2024` |
| Step | NANO only (MiniAOD → NanoAOD) |
| Customisation | `BTVCustomNanoAOD_allPF` |
| Storage site | `T2_DE_DESY` |
| Output tag | `RunIII2024Summer24BTVNanoAllPF` |

## Quick Start

```bash
# 1. Set up CMSSW environment, generate PSet, initialise proxy
source setup.sh

# 2. Dry run — generates CRAB configs
./submit.sh

# 3. Submit to CRAB
./submit.sh --submit

# 4. (Optional) Use a custom dataset list
./submit.sh --dataset-file my_datasets.txt --submit

# 5. Monitor jobs (mrCrabs)
./call_mrCrabs.sh              # status overview
./call_mrCrabs.sh --resubmit   # auto-resubmit failed jobs
```

## Files

| File | Description |
|------|-------------|
| `datasets.txt` | MiniAOD dataset paths (one per line), used directly as CRAB `inputDataset`. |
| `setup.sh` | Sets up `CMSSW_15_0_18`, generates `btvnano_cfg.py`, initialises grid proxy + CRAB |
| `submit.sh` | Reads `datasets.txt`, generates CRAB configs, optionally submits |
| `btvnano_cfg.py` | Auto-generated cmsDriver config for BTV NanoAOD (created by `setup.sh`) |
| `crab_configs/` | Generated per-dataset CRAB configs (created by `submit.sh`) |

## Datasets

Currently configured Drell-Yan (powheg) samples:

- **DY → ee**: 10 mass bins (10–50, 50–120, ..., 6000–∞ GeV)
- **DY → μμ**: 10 mass bins
- **DY → ττ**: 10 mass bins

To add more datasets, simply append the MiniAOD dataset path to `datasets.txt`.

## Notes

- Unlike the signal production (`03_nanoaod`) which uses `userInputFiles` for
  privately produced MiniAOD, this setup uses `config.Data.inputDataset` to
  read centrally produced MiniAOD directly from DBS.
- Default: 5 MiniAOD files per CRAB job. Adjust `FILES_PER_JOB` in `submit.sh`
  if jobs are too short or hit memory limits.
