import FWCore.ParameterSet.Config as cms
from PhysicsTools.NanoAOD.common_cff import Var


def _append_unique_select(process, statements):
    existing = list(process.finalGenParticles.select)
    for statement in statements:
        if statement not in existing:
            process.finalGenParticles.select.append(statement)


def HZaCustomNanoAOD(process):
    if not hasattr(process, "finalGenParticles"):
        raise RuntimeError("HZaCustomNanoAOD requires process.finalGenParticles; run NanoAOD customization first")
    if not hasattr(process, "btvGenTable"):
        raise RuntimeError(
            "HZaCustomNanoAOD requires BTVCustomNanoAOD_allPF first so that GenPart/PFCands/GenCands are available"
        )

    # Use mergedGenParticles to retain a fuller hadronized truth history in GenPart.
    # (Safe here because we replace BTV's fragile genCandMotherTable producer.)
    process.finalGenParticles.src = cms.InputTag("mergedGenParticles")

    # Extend finalGenParticles to retain full H→Za decay chain and hadronized pions
    _append_unique_select(
        process,
        [
            "keep++ abs(pdgId) == 25",  # Higgs
            "keep++ abs(pdgId) == 23",  # Z boson
            "keep++ abs(pdgId) == 36",  # pseudoscalar a
            "keep abs(pdgId) == 111",  # pi0
            "keep abs(pdgId) == 211",  # pi+/pi-
        ],
    )

    process.btvGenTable.doc = cms.string(
        "interesting gen particles, extended for H->Za signal truth with full Higgs/Z/a decay chain"
    )
    process.btvGenTable.variables.charge = Var("charge", int, doc="Electric charge")

    process.genCandsTable.doc = cms.string(
        "Final-state gen particles, including all packed daughters for H->Za signal events"
    )
    process.genCandMCMatchTable.docString = cms.string(
        "MC matching to status==1 genCands, usable together with the extended H->Za GenPart ancestry"
    )

    # Replace BTV's fragile GenCandMotherTableProducer with a robust variant that
    # still writes the same flat-table columns (including GenCands_genPartMotherIdx).
    # The custom producer catches InvalidReference cases and falls back to a
    # kinematic match in finalGenParticles.
    if hasattr(process, "genCandMotherTable"):
        old_gen_cand_mother_table = process.genCandMotherTable

        process.genCandMotherTable = cms.EDProducer(
            "HZaGenCandMotherTableProducer",
            objName=old_gen_cand_mother_table.objName,
            branchName=old_gen_cand_mother_table.branchName,
            src=old_gen_cand_mother_table.src,
            mcMap=old_gen_cand_mother_table.mcMap,
            genparticles=cms.InputTag("finalGenParticles"),
        )

        if hasattr(process, "btvGenTask"):
            process.btvGenTask.remove(old_gen_cand_mother_table)
            process.btvGenTask.add(process.genCandMotherTable)

    return process
