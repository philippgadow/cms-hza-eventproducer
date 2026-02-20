# POWHEG Gridpack: gg → H

POWHEG-BOX-V2 gridpack for gluon-gluon fusion Higgs production with full top/bottom quark mass effects (NLO QCD), based on [arXiv:1202.5475](https://arxiv.org/abs/1202.5475).

## Gridpack

```
gg_H_quark-mass-effects_el9_amd64_gcc12_CMSSW_13_3_0_ggH_M125.tgz   (~522 KB)
```

Contains the POWHEG executable, pre-computed integration grids, input configuration, and CMS run wrappers.

### Gridpack contents
| File | Description |
|------|-------------|
| `pwhg_main` | Compiled POWHEG executable |
| `powheg.input` | Configuration with `NEVENTS`/`SEED` placeholders (substituted by `runcmsgrid.sh` at runtime) |
| `runcmsgrid.sh` | CMS run wrapper for `ExternalLHEProducer` |
| `pwggrid.dat` | Pre-computed importance-sampling integration grid |
| `pwgubound.dat` | Upper bounding function normalization |
| `pwgxgrid.dat` | x-grid data |
| `pwg-stat.dat` | Integration statistics |

## Physics Settings

| Parameter | Value |
|-----------|-------|
| Process | `gg_H_quark-mass-effects` |
| √s | 13.6 TeV (`ebeam1` = `ebeam2` = 6800 GeV) |
| m_H | 125 GeV |
| Γ_H | 0.00407 GeV |
| m_top | 172.5 GeV |
| m_bottom | 4.75 GeV |
| PDF | NNPDF31_nnlo_as_0118_mc_hessian_pdfas (LHAPDF ID 325300) |
| hdamp | 172.5 GeV |
| hdecaymode | −1 (stable Higgs — decayed by Pythia8) |
| hfact | 60 GeV (damping factor for high-pT radiation) |
| zerowidth | 0 (off-shell with Breit-Wigner) |
| bwshape | 3 (complex-pole scheme) |
| ew | 1 (electroweak corrections enabled) |
| runningscale | 1 (scales = Higgs virtuality) |
| σ(NLO) | ~29 pb |

The input card (`powheg.input`) follows the official CMS configuration from `genproductions/bin/Powheg/production/Run3/13p6TeV/Higgs/gg_H_quark-mass-effects_NNPDF31_13p6TeV/`.


## How to Generate the Gridpack

### 1. Setup and compile (once)
```bash
./setup_cms_powheg.sh
```
Creates CMSSW_13_3_0, clones genproductions, and prints the stage 0 (compilation) command:
```bash
cd CMSSW_13_3_0/src/genproductions/bin/Powheg
python3 run_pwg_condor.py -p 0 -i powheg.input -m gg_H_quark-mass-effects -f ggH_M125
```

### 2. Generate grids + create tarball
```bash
# Recommended: Run locally (~20-30 min)
./generate_gridpack.sh --local
```

The script cleans old grids, copies `powheg.input` into the working directory, runs `pwhg_main` to compute integration grids and upper bounds, verifies the grid files were produced, and packages the gridpack tarball.

> ⚠️ **Important**: The `gg_H_quark-mass-effects` process does **not** support POWHEG's `parallelstage`/`xgriditeration` parameters used by the condor parallel approach. The `--condor` mode (default) will warn about this. Always use `--local` for this process.

```bash
# Alternative: Submit to HTCondor (NOT recommended for this process)
./generate_gridpack.sh             # Will show a warning

# Only create tarball (if grids already exist)
./generate_gridpack.sh --tarball
```

The output tarball is copied to both the Powheg directory and `01_gridpacks/`.

### Other options
```bash
./generate_gridpack.sh --clean   # Only clean old grids, don't submit
./generate_gridpack.sh --help    # Show usage
```

## Validation

Test the gridpack through the full CMS event generation chain:
```bash
./test_gridpack.sh [nevents]     # default: 10 events
```

This creates a CMSSW fragment with `ExternalLHEProducer`, runs `cmsDriver.py` to produce an LHE step, and verifies events are generated.

## Key Parameters in `powheg.input`

### Placeholders (substituted at runtime)
```
numevts NEVENTS    ← replaced by runcmsgrid.sh
iseed SEED         ← replaced by runcmsgrid.sh
```
**Critical**: these must use the literal strings `NEVENTS` and `SEED`, and each keyword must appear exactly once (POWHEG errors on duplicates).

### Required for non-interactive running
```
compute_rwgt 0     ! reweighting disabled (no pwg-rwl.dat)
clobberlhe 1       ! allow POWHEG to create the LHE output file
```
Without `compute_rwgt 0`, POWHEG tries to read `pwgevents.lhe` for reweighting before it exists, causing the interactive prompt `enter name of event file`. Without `clobberlhe 1`, POWHEG cannot create the output file.

### gg_H_quark-mass-effects mandatory parameters
```
hdecaymode -1      ! stable Higgs (mandatory — POWHEG errors if absent)
massren 0          ! on-shell mass renormalization
model 0            ! Standard Model
gfermi 0.116637D-04
```

## References

- POWHEG gg→H with quark mass effects: [arXiv:1202.5475](https://arxiv.org/abs/1202.5475)
- POWHEG-BOX-V2: https://powhegbox.mib.infn.it/
- CMS genproductions: https://github.com/cms-sw/genproductions
