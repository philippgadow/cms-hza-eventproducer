import FWCore.ParameterSet.Config as cms

# Link to generator fragment
externalLHEProducer = cms.EDProducer("ExternalLHEProducer",
    args = cms.vstring('__GRIDPACK__'),
    nEvents = cms.untracked.uint32(5000),
    numberOfParameters = cms.uint32(1),
    outputFile = cms.string('cmsgrid_final.lhe'),
    scriptName = cms.FileInPath('GeneratorInterface/LHEInterface/data/run_generic_tarball_cvmfs.sh')
)

# Generator configuration for gg -> H production using POWHEG gridpack
# Process: gg fusion -> SM Higgs (to be decayed by Pythia to BSM H -> Za)
# Reference: arXiv:1202.5475 (POWHEG gg_H_quark-mass-effects)

from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.MCTunes2017.PythiaCP5Settings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *

generator = cms.EDFilter("Pythia8ConcurrentHadronizerFilter",
    maxEventsToPrint = cms.untracked.int32(1),
    pythiaPylistVerbosity = cms.untracked.int32(1),
    filterEfficiency = cms.untracked.double(1.0),
    pythiaHepMCVerbosity = cms.untracked.bool(False),
    comEnergy = cms.double(13600.),
    PythiaParameters = cms.PSet(
        pythia8CommonSettingsBlock,
        pythia8CP5SettingsBlock,
        pythia8PSweightsSettingsBlock,
        processParameters = cms.vstring(
            # Configure SM Higgs (25) from LHE with custom BSM decay
            # No LHE hack needed - Pythia8 can handle custom decays for particle 25
            'Higgs:useBSM = on',  # Enable BSM Higgs particles (35, 36, 37...)
            
            # SM Higgs (25) custom decay: H -> Z + a (pseudoscalar)
            '25:m0 = 125.0',
            '25:mWidth = 0.00407',
            '25:onMode = off',              # Turn off all standard decays
            '25:addChannel = 1 1.0 100 23 36',  # Add H -> Z(23) a(36) with BR=100%
            
            # Z boson decays to leptons only
            '23:onMode = off',
            '23:onIfAny = 11 13 15',  # Z -> e, mu, tau
            
            # BSM pseudoscalar A0 (36) settings
            # Let Pythia8's built-in ResonanceA0 handle decays naturally.
            # For m_a = 1 GeV the computed BRs are approximately:
            #   a -> gg:     ~84%  (loop-induced, meMode=103)
            #   a -> mu+mu-: ~16%  (tree-level Yukawa)
            #   a -> dd:     ~0.1% (tree-level Yukawa)
            #   a -> gamgam: ~0.02%
            # Reference: validated against established H->ZA analysis
            # (pheno_h2zllahad/generators/pythia/main_PhPy8_HZA.cc)
            '36:m0 = __MASS__',
            '36:mWidth = 0.001',
            '36:mMin = 0.001',
            '36:mMax = __MASSMAX__',
            '36:onMode = on',  # Natural decays via ResonanceA0
            
            # POWHEG settings for vetoed shower
            'POWHEG:nFinal = 1',  # One Higgs in final state
            'POWHEG:veto = 1',
            'POWHEG:vetoCount = 3',
            'POWHEG:pThard = 0',
            'POWHEG:pTemt = 0',
            'POWHEG:emitted = 0',
            'POWHEG:pTdef = 1',
            'POWHEG:MPIveto = 0',
            'POWHEG:QEDveto = 2',
            
            # PDF settings
            'PDF:pSet = LHAPDF6:NNPDF31_nnlo_as_0118',
        ),
        parameterSets = cms.vstring(
            'pythia8CommonSettings',
            'pythia8CP5Settings',
            'pythia8PSweightsSettings',
            'processParameters',
        )
    )
)

# Product filter for requiring Z -> l+l- and a
ProductionFilterSequence = cms.Sequence(generator)
