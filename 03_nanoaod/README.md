# Custom NanoAOD Reprocessing

Reprocess existing MiniAOD files into specialised NanoAOD formats for the H → Za analysis.

## Supported Formats

| Format | Customisation | Key content | Use case |
|--------|--------------|-------------|----------|
| **BTV NanoAOD** (`btvnano`) | `BTVCustomNanoAOD_allPF` | All PF candidates (`PFCands`), BTV tagger inputs/outputs | Jet-substructure studies of light pseudoscalar *a* |
| **BPH NanoAOD** (`bphnano`) | `nanoAOD_customizeBPH` | Dimuon pairs, BPH tracks, V0s (K_S, Λ), B → K/Kshort/Lambda + ℓℓ | B-physics–style displaced-vertex reconstruction of *a* → μμ |

## Common Parameters

| Parameter | Value |
|-----------|-------|
| CMSSW release | `CMSSW_15_0_18` (`el9_amd64_gcc12`) |
| Global tag | `150X_mcRun3_2024_realistic_v2` |
| Era | `Run3_2024` |
| Step | NANO only (MiniAOD → NanoAOD) |
| Storage site | `T2_DE_DESY` |
| Output tier | `NANOAODSIM` |

## Quick Start

```bash
# 1. Set up CMSSW environment, generate PSet configs, initialise proxy
source setup.sh

# 2. Edit mass points in submit.sh
#    Set the REPROCESS_POINTS array with "mass:timestamp" entries
vi submit.sh

# 3. Dry run — generates CRAB configs, lists input files
./submit.sh --format btvnano
./submit.sh --format bphnano

# 4. Submit to CRAB
./submit.sh --format btvnano --submit
./submit.sh --format bphnano --submit

# 5. Monitor jobs (mrCrabs)
./call_mrCrabs.sh              # status overview
./call_mrCrabs.sh --resubmit   # auto-resubmit failed jobs
```

## Files

| File | Description |
|------|-------------|
| `setup.sh` | Sets up `CMSSW_15_0_18`, generates both `btvnano_cfg.py` and `bphnano_cfg.py` via cmsDriver, initialises grid proxy + CRAB |
| `submit.sh` | Unified submission script — use `--format btvnano` or `--format bphnano` to select the NanoAOD flavour |
| `btvnano_cfg.py` | Auto-generated cmsDriver config for BTV NanoAOD (created by `setup.sh`) |
| `bphnano_cfg.py` | Auto-generated cmsDriver config for BPH NanoAOD (created by `setup.sh`) |
| `crab_btvnano_*.py` | Per-mass-point CRAB configs for BTV NanoAOD (created by `submit.sh`) |
| `crab_bphnano_*.py` | Per-mass-point CRAB configs for BPH NanoAOD (created by `submit.sh`) |

## Configuration

### Mass points

Edit the `REPROCESS_POINTS` array in `submit.sh`:

```bash
REPROCESS_POINTS=(
    "1.0:260220_232829"
    "2.0:260220_232845"
)
```

Each entry is `"mass_GeV:crab_timestamp"`. The timestamp is the directory name created by the original CRAB task under the campaign directory on the storage element. You can find it with:

```bash
XROOTD="root://dcache-cms-xrootd.desy.de:1094"
CAMPAIGN="RunIII2024Summer24"
xrdfs $XROOTD ls /store/user/$USER/ggH_HZa_signals/$CAMPAIGN/ggH_HZa_mA1_0GeV/$CAMPAIGN/
```

### cmsDriver commands

Both configs are generated automatically by `setup.sh`:

**BTV NanoAOD (allPF):**
```bash
cmsDriver.py \
    --python_filename btvnano_cfg.py \
    --eventcontent NANOAODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_btv_cff.BTVCustomNanoAOD_allPF \
    --datatier NANOAODSIM \
    --filein "file:dummy.root" --fileout "file:btvnano_output.root" \
    --conditions 150X_mcRun3_2024_realistic_v2 \
    --step NANO --geometry DB:Extended --era Run3_2024 \
    --mc --nThreads 4 -n -1 --no_exec
```

**BPH NanoAOD:**
```bash
cmsDriver.py \
    --python_filename bphnano_cfg.py \
    --eventcontent NANOAODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_bph_cff.nanoAOD_customizeBPH \
    --datatier NANOAODSIM \
    --filein "file:dummy.root" --fileout "file:bphnano_output.root" \
    --conditions 150X_mcRun3_2024_realistic_v2 \
    --step NANO --geometry DB:Extended --era Run3_2024 \
    --mc --nThreads 4 -n -1 --no_exec
```

## Monitoring

```bash
# Check status (replace <campaign_tag> with the appropriate tag)
# BTV: RunIII2024Summer24BTVNanoAllPF
# BPH: RunIII2024Summer24BPHNano
crab status -d crab_projects_<campaign_tag>/<task_dir>

# Resubmit failed jobs
crab resubmit -d crab_projects_<campaign_tag>/<task_dir>

# List output files
XROOTD="root://dcache-cms-xrootd.desy.de:1094"
xrdfs $XROOTD ls /store/user/$USER/ggH_HZa_signals/RunIII2024Summer24/<sample>/<campaign_tag>/
```

## NanoAOD Content Details

### BTV NanoAOD (`btvnano`)

Adds to standard NanoAOD:
- **`PFCands`** — all packed PF candidates with full tracking info (pt, eta, phi, dxy, dz, track quality)
- **`JetPFCands`** / **`FatJetPFCands`** — jet-constituent association tables
- **`JetSVs`** / **`FatJetSVs`** — secondary vertex association
- Extended jet tagger inputs/outputs (DeepJet, ParticleNet, UParT, RobustParT)

### BPH NanoAOD (`bphnano`)

Adds to standard NanoAOD:
- **`BPHGenPart`** — gen-level B-hadron decay chains
- **`MuonBPH`** — extended muon collection with BPH-specific variables
- **`MuMu`** — opposite-sign dimuon pairs with vertex fit
- **`tracksBPH`** — selected tracks for B-meson reconstruction
- **`DiTrack`** — track pairs (φ → KK, ρ → ππ, etc.)
- **`V0`** — K_S → ππ and Λ → pπ candidates
- **`BToKMuMu`**, **`BToTrkTrkMuMu`**, **`BToKshortMuMu`**, **`LambdabToLambdaMuMu`**, **`BToChargedKstar`**, **`XibToXi`** — fully reconstructed B-hadron decay chains

## Notes

- Uses `CMSSW_15_0_18` (not 15_1_0) to avoid a `PackedGenParticle::unpack()` segfault present in newer releases.
- The CRAB `Analysis` plugin is used (not `PrivateMC`) since we are reading existing files, not generating new events.
- Each MiniAOD file is processed in a separate CRAB job (`FileBased` splitting, 1 file per job).
- The BPH NanoAOD customisation (`nanoAOD_customizeBPH`) is defined in [`PhysicsTools/NanoAOD/custom_bph_cff`](https://github.com/cms-sw/cmssw/blob/master/PhysicsTools/NanoAOD/python/custom_bph_cff.py) and loads collections from [`PhysicsTools/BPHNano`](https://github.com/cms-sw/cmssw/tree/master/PhysicsTools/BPHNano).
- The `BTVCustomNanoAOD_allPF` customisation adds the `PFCands` branch required for data-driven jet-substructure studies of the light pseudoscalar *a*.
