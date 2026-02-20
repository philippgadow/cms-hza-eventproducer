# CMS Signal Production for ggH → H → Za

Monte Carlo signal sample production for the rare Higgs boson decay H → Za at √s = 13.6 TeV, targeting the Z → ℓ⁺ℓ⁻ + a → hadrons final state.

## Workflow

```
01_gridpacks/           POWHEG NLO gridpack (gg → H) at √s = 13.6 TeV
      │                    ↓
02_signal_production/   CMS full chain via ExternalLHEProducer + Pythia8
                           H(125) → Z(23) + a(36)
                           Z → ℓℓ,  a → hadrons
                        LHE → GEN → SIM → DIGI → HLT → RECO → MiniAOD → NanoAOD
```

## Quick Start

```bash
# 1. Set up CMSSW environment
cd 02_signal_production
source setup.sh

# 2. Run local test (10 events, m_a = 1.0 GeV, GEN-SIM only)
cd scripts
./test_local.sh

# 3. Run full chain locally (100 events, GEN-SIM → NanoAODv15)
./run_fullchain.sh --no-pileup

# 4. Submit production to CRAB (all mass points)
./submit_crab.sh
```

## Technical Summary

| Component | Details |
|-----------|---------|
| POWHEG process | gg_H_quark-mass-effects (NLO QCD) |
| CMSSW (GEN-SIM) | 14_0_19 (el9_amd64_gcc12) |
| CMSSW (DIGI+HLT+RECO) | 14_0_21 (el9_amd64_gcc12) |
| CMSSW (MiniAOD+NanoAOD) | 15_0_2 (el9_amd64_gcc12) |
| Conditions (steps 0–2) | 140X_mcRun3_2024_realistic_v26, Run3_2024 |
| Conditions (steps 3–4) | 150X_mcRun3_2024_realistic_v2, Run3_2024 |
| PDF | NNPDF31_nnlo_as_0118 |
| Tune | CP5 |
| Higgs decay | `25:addChannel = 1 1.0 100 23 36` (H → Z + a) |
| a decay | Natural via Pythia8 `ResonanceA0` (`36:onMode = on`): ~84% gg, ~16% μμ at m_a = 1 GeV |
| Pseudoscalar | PDG 36, m_a = 0.5–8.0 GeV (10 mass points) |
| √s | 13.6 TeV (ebeam = 6800 GeV) |
| σ(gg→H) | ~27.4 pb (NLO, POWHEG) |
| Target | 100k events per mass point |


## References

- POWHEG gg→H with mass effects: [arXiv:1202.5475](https://arxiv.org/abs/1202.5475)
- ATLAS H→Za search: [arXiv:2411.16361](https://arxiv.org/abs/2411.16361)
- CMS GenProductions: https://github.com/cms-sw/genproductions
- POWHEG-BOX: https://powhegbox.mib.infn.it/

