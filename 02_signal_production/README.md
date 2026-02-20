# Signal Production: ggH → H → Za

CMS GEN-SIM production workflow for the rare Higgs decay H → Za, using POWHEG gridpacks with Pythia8 BSM decay configuration.

## Physics Process

```
pp → gg → H(125) → Z + a
                    │   └→ hadrons (m_a variable)
                    └→ ℓ⁺ℓ⁻ (e, μ, τ)
```

- **Production**: gg → H at NLO QCD with full top/bottom mass effects (POWHEG-BOX-V2)
- **Decay**: SM Higgs (PDG 25) forced to H → Z(23) + a(36) via Pythia8 `addChannel`
- **Z decay**: Z → e⁺e⁻, μ⁺μ⁻, τ⁺τ⁻
- **Mass points**: m_a = 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 8.0 GeV


## Prerequisites

- lxplus el9 nodes (lxplus9xx) or equivalent CERN computing
- Valid grid certificate + CMS VO membership
- Completed gridpack from `01_gridpacks/` (see `generate_gridpack.sh`)

## Quick Start

### 1. Setup

```bash
cd 02_signal_production
source setup.sh
```

On el9 (lxplus9xx) this runs natively. On older nodes it starts a `cmssw-el9` container — source setup.sh again after entering.

### 2. Local Test

```bash
cd scripts
./test_local.sh
```

Generates 10 events at m_a = 1.0 GeV through the full LHE → GEN → SIM chain.
Output: `test_*/ggH_HZa_mA1_0GeV_GEN-SIM.root`.


### 3. Full Chain (GEN-SIM → NanoAODv15)

```bash
cd scripts
./run_fullchain.sh --no-pileup    # Fast validation (no pileup)
./run_fullchain.sh                # With premixed pileup (needs grid proxy)
./run_fullchain.sh --skip-to 3    # Resume from step 3 (MiniAOD)
```

Runs 100 events through the complete CMS production chain:

| Step | Description | CMSSW | Global Tag |
|------|-------------|-------|------------|
| 0 | LHE + GEN + SIM | 14_0_19 | 140X_mcRun3_2024_realistic_v26 |
| 1 | DIGI + L1 + DIGI2RAW + HLT:2024v14 | 14_0_21 | 140X_mcRun3_2024_realistic_v26 |
| 2 | RAW2DIGI + RECO | 14_0_21 | 140X_mcRun3_2024_realistic_v26 |
| 3 | MiniAOD v6 (PAT) | 15_0_2 | 150X_mcRun3_2024_realistic_v2 |
| 4 | NanoAOD v15 (NANO) | 15_0_2 | 150X_mcRun3_2024_realistic_v2 |

### 4. CRAB Submission

```bash
cd scripts
./submit_crab.sh
```

Submits all 10 mass points (100 jobs × 1000 events = 100k events per mass point).

### 4. Monitoring

```bash
crab status -d crab_projects_RunIII2024Summer24/crab_*
crab resubmit crab_projects_RunIII2024Summer24/crab_<sample>
crab getlog crab_projects_RunIII2024Summer24/crab_<sample>
```

## Generator Fragment

The fragment (`fragments/ggH_HZa_fragment.py`) uses three placeholders replaced at runtime:
- `__GRIDPACK__` → absolute path to gridpack tarball
- `__MASS__` → pseudoscalar mass in GeV
- `__MASSMAX__` → Breit-Wigner upper window, set to max(2.0, 2 × m_a)

### Key Pythia8 Settings

```python
# BSM decay of SM Higgs — no LHE hack needed
'Higgs:useBSM = on',
'25:onMode = off',
'25:addChannel = 1 1.0 100 23 36',   # H → Z + a (BR = 100%)

# Z → leptons only
'23:onMode = off',
'23:onIfAny = 11 13 15',

# BSM pseudoscalar A0 — natural decays via ResonanceA0
'36:m0 = __MASS__',
'36:mWidth = 0.001',
'36:mMin = 0.001',
'36:mMax = __MASSMAX__',    # Set to max(2.0, 2 × m_a) at runtime
'36:onMode = on',           # Natural BRs computed by ResonanceA0

# POWHEG shower matching (1 Higgs in final state)
'POWHEG:nFinal = 1',
'POWHEG:veto = 1',
'POWHEG:vetoCount = 3',
'POWHEG:QEDveto = 2',
```

#### A0 Decay Branching Ratios

Pythia8's built-in `ResonanceA0` handler (PDG 36) dynamically computes partial widths, including the loop-induced a → gg channel (`meMode=103`). At m_a = 1 GeV:

| Channel | BR | meMode |
|---------|-----|--------|
| a → gg | ~84% | 103 (loop-induced) |
| a → μ⁺μ⁻ | ~16% | 0 (tree-level Yukawa) |
| a → dd̄ | ~0.1% | 0 |
| a → γγ | ~0.02% | 103 |

Validated with 100 events in NanoAOD (Feb 2026): 79% gg, 20% μμ, 1% dd̄ — statistically consistent with expected BRs.


## Production Parameters

| Parameter | Value |
|-----------|-------|
| CMSSW (GEN-SIM) | 14_0_19 |
| CMSSW (DIGI+HLT+RECO) | 14_0_21 |
| CMSSW (MiniAOD+NanoAOD) | 15_0_2 |
| Architecture | el9_amd64_gcc12 |
| Conditions (steps 0–2) | 140X_mcRun3_2024_realistic_v26 |
| Conditions (steps 3–4) | 150X_mcRun3_2024_realistic_v2 |
| HLT menu | 2024v14 |
| Beam spot | DBrealistic |
| Era | Run3_2024 |
| Premix pileup | Neutrino_E-10_gun / Premixlib2024 |
| PDF | NNPDF31_nnlo_as_0118 |
| Tune | CP5 |
| √s | 13.6 TeV (gridpack ebeam = 6800 GeV) |


## Customization

### Mass Points
Edit `scripts/submit_crab.sh`:
```bash
MASS_POINTS=(0.5 0.75 1.0 1.5 2.0 2.5 3.0 3.5 4.0 8.0)
```

### Z Decay Modes
Edit `fragments/ggH_HZa_fragment.py`:
```python
'23:onIfAny = 11 13',  # Only e and μ (exclude τ)
```

### Event Filters
Add after generator in the fragment:
```python
muonFilter = cms.EDFilter("MCParticlePairFilter",
    ParticleID1 = cms.untracked.vint32(13),
    ParticleID2 = cms.untracked.vint32(-13),
    MinPt = cms.untracked.vdouble(5.0, 5.0),
    MaxEta = cms.untracked.vdouble(2.5, 2.5),
    Status = cms.untracked.vint32(1, 1),
)
ProductionFilterSequence = cms.Sequence(generator * muonFilter)
```

## References

- [CMS GenProductions](https://github.com/cms-sw/genproductions)
- [CRAB3 User Guide](https://twiki.cern.ch/twiki/bin/view/CMSPublic/CRAB3)
- [POWHEG-BOX](https://powhegbox.mib.infn.it/)
- [Pythia 8](https://pythia.org/)
- POWHEG gg→H: [arXiv:1202.5475](https://arxiv.org/abs/1202.5475)
- ATLAS H→Za: [arXiv:2411.16361](https://arxiv.org/abs/2411.16361), [arXiv:2004.01678](https://arxiv.org/abs/2004.01678)
