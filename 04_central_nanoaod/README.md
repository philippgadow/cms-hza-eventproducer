# Central btvNanoAllPF Production

Reprocess centrally-produced MiniAOD into **BTV NanoAOD with all PF candidates**
(`BTVCustomNanoAOD_allPF`) for the H → Za analysis — both **background MC** and
**2024 collision data**.

## Overview

Two dataset lists are provided:
- **`datasets_mc.txt`** — Drell-Yan background MC (`RunIII2024Summer24MiniAODv6`)
- **`datasets_data.txt`** — 2024 collision data (`MINIv6NANOv15` ReReco, eras C–I)

The `submit.sh` script auto-selects the correct global tag, PSet (MC/data),
splitting strategy, and lumi mask based on the `--mc` / `--data` flag.

## Parameters

| Parameter | MC | Data |
|-----------|-----|------|
| CMSSW release | `CMSSW_15_0_18` (`el9_amd64_gcc12`) | same |
| Global tag | `150X_mcRun3_2024_realistic_v2` | `150X_dataRun3_v2` |
| Era | `Run3_2024` | same |
| Step | NANO (MiniAOD → NanoAOD) | same |
| Customisation | `BTVCustomNanoAOD_allPF` | same |
| eventcontent | `NANOAODSIM` | `NANOAOD` |
| Splitting | `FileBased` (5 files/job) | `LumiBased` (50 LS/job) |
| Lumi mask | — | Golden JSON (`Cert_Collisions2024_378981_386951_Golden.json`) |
| Storage site | `T2_DE_DESY` | same |
| Output tag | `RunIII2024Summer24BTVNanoAllPF` | `Run2024BTVNanoAllPF` |

## Quick Start

```bash
# 1. Set up CMSSW environment, generate PSet (MC + data), initialise proxy
source setup.sh

# 2. Background MC
./submit.sh                       # dry run — MC (default)
./submit.sh --submit              # submit MC jobs

# 3. 2024 Data
./submit.sh --data                # dry run — data
./submit.sh --data --submit       # submit data jobs

# 4. (Optional) Custom dataset list
./submit.sh --dataset-file my_datasets.txt --mc --submit

# 5. Monitor jobs (mrCrabs)
./call_mrCrabs.sh              # status overview
./call_mrCrabs.sh --resubmit   # auto-resubmit failed jobs
```

## Files

| File | Description |
|------|-------------|
| `datasets_mc.txt` | Background MC MiniAOD dataset paths (Drell-Yan, `MINIAODSIM`). |
| `datasets_data.txt` | 2024 data MiniAOD dataset paths (Muon0/1, EGamma0/1, eras C–I, `MINIAOD`). |
| `setup.sh` | Sets up `CMSSW_15_0_18`, generates `btvnano_mc_cfg.py` + `btvnano_data_cfg.py`, grid proxy + CRAB |
| `submit.sh` | Reads dataset list, generates CRAB configs, optionally submits. Use `--mc` (default) or `--data`. |
| `btvnano_mc_cfg.py` | Auto-generated cmsDriver config for MC NanoAOD (created by `setup.sh`) |
| `btvnano_data_cfg.py` | Auto-generated cmsDriver config for data NanoAOD (created by `setup.sh`) |
| `crab_configs/` | Generated per-dataset CRAB configs (created by `submit.sh`) |

## Datasets

### Background MC

Currently configured Drell-Yan (powheg) samples from `RunIII2024Summer24MiniAODv6`:

- **DY → ee**: 10 mass bins (10–50, 50–120, ..., 6000–∞ GeV)
- **DY → μμ**: 10 mass bins
- **DY → ττ**: 10 mass bins

### 2024 Collision Data

`MINIv6NANOv15` ReReco, eras C through I:

- **Muon0**: 7 eras (C, D, E, F, G, H, I)
- **Muon1**: 7 eras
- **EGamma0**: 7 eras
- **EGamma1**: 7 eras

Golden JSON: `Cert_Collisions2024_378981_386951_Golden.json`
(from `/eos/user/c/cmsdqm/www/CAF/certification/Collisions24/`)

## Notes

- Unlike the signal production (`03_nanoaod`) which uses `userInputFiles` for
  privately produced MiniAOD, this setup uses `config.Data.inputDataset` to
  read centrally produced MiniAOD directly from DBS.
- For MC: 5 MiniAOD files per CRAB job (`FileBased` splitting).
- For data: 50 lumi sections per CRAB job (`LumiBased` splitting).
- Adjust `FILES_PER_JOB` / `LUMIS_PER_JOB` in `submit.sh` if jobs are too
  short or hit memory limits.
