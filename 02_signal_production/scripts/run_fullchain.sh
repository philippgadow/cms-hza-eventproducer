#!/bin/bash
#
# Local full-chain production: ggH → H → Za
#
# Steps:
#   0) LHE + GEN + SIM             (CMSSW_14_0_19)
#   1) DIGI + Premix + L1 + HLT    (CMSSW_14_0_21)
#   2) RECO → AOD                  (CMSSW_14_0_21)
#   3) MiniAOD v6                  (CMSSW_15_0_2)
#   4) NanoAOD v15                 (CMSSW_15_0_2)
#   5) BTV NanoAOD allPF           (CMSSW_15_1_0)
#
# Usage:
#   source ../setup.sh   # set up CMSSW_14_0_19 environment first
#   ./run_fullchain.sh [--no-pileup] [--skip-to N]
#
# Options:
#   --no-pileup   Skip pileup premixing (much faster, for chain validation)
#   --skip-to N   Skip to step N (0-4), using existing intermediate files
#

set -e

# ─── Configuration ───────────────────────────────────────────────────────────
MASS_POINT=1.0          # pseudoscalar mass (GeV)
NEVENTS=100
NTHREADS=4
SEED=12345

GRIDPACK_REL="../../01_gridpacks/gg_H_quark-mass-effects_el9_amd64_gcc12_CMSSW_13_3_0_ggH_M125.tgz"

# Campaign naming
CAMPAIGN_GS="RunIII2024Summer24wmLHEGS"
CAMPAIGN_DR="RunIII2024Summer24DRPremix"
CAMPAIGN_MINI="RunIII2024Summer24MiniAODv6"
CAMPAIGN_NANO="RunIII2024Summer24NanoAODv15"
CAMPAIGN_BTVNANO="RunIII2024Summer24BTVNanoAllPF"

# CMSSW releases and global tags
CMSSW_GS="CMSSW_14_0_19"
CMSSW_DR="CMSSW_14_0_21"
CMSSW_MINI="CMSSW_15_0_2"
CMSSW_BTVNANO="CMSSW_15_0_18"

GT_GS="140X_mcRun3_2024_realistic_v26"
GT_DR="140X_mcRun3_2024_realistic_v26"
GT_MINI="150X_mcRun3_2024_realistic_v2"

PREMIX_DATASET="/Neutrino_E-10_gun/RunIIISummer24PrePremix-Premixlib2024_140X_mcRun3_2024_realistic_v26-v1/PREMIX"

# ─── Parse options ───────────────────────────────────────────────────────────
USE_PILEUP=true
SKIP_TO=0

for arg in "$@"; do
    case $arg in
        --no-pileup) USE_PILEUP=false ;;
        --skip-to)   shift; SKIP_TO=$1 ;;
        --skip-to=*) SKIP_TO="${arg#*=}" ;;
    esac
done

# ─── Resolve paths before cd ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENT_SRC="$SCRIPT_DIR/../fragments/ggH_HZa_fragment.py"
GRIDPACK_ABS="$(cd "$(dirname "$SCRIPT_DIR/$GRIDPACK_REL")" && pwd)/$(basename "$GRIDPACK_REL")"
BASEDIR="$SCRIPT_DIR/.."

MASS_STR=$(echo $MASS_POINT | sed 's/\./_/g')
SAMPLE="ggH_HZa_mA${MASS_STR}GeV"

# Output file names
FILE_GS="${CAMPAIGN_GS}_${SAMPLE}.root"
FILE_DR="${CAMPAIGN_DR}_${SAMPLE}.root"
FILE_RECO="${CAMPAIGN_DR}_RECO_${SAMPLE}.root"
FILE_MINI="${CAMPAIGN_MINI}_${SAMPLE}.root"
FILE_NANO="${CAMPAIGN_NANO}_${SAMPLE}.root"
FILE_BTVNANO="${CAMPAIGN_BTVNANO}_${SAMPLE}.root"

# ─── Create working directory ────────────────────────────────────────────────
WORKDIR="$SCRIPT_DIR/fullchain_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Full-Chain Local Production: ggH → H → Za                 ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Mass point : m_a = ${MASS_POINT} GeV"
echo "║  Events     : ${NEVENTS}"
echo "║  Threads    : ${NTHREADS}"
echo "║  Pileup     : ${USE_PILEUP}"
echo "║  Skip to    : step ${SKIP_TO}"
echo "║  Working dir: $(pwd)"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ─── Helper to set up a CMSSW release ────────────────────────────────────────
setup_cmssw() {
    local RELEASE=$1
    source /cvmfs/cms.cern.ch/cmsset_default.sh
    export SCRAM_ARCH=el9_amd64_gcc12

    if [ ! -d "$BASEDIR/$RELEASE/src" ]; then
        echo "  Creating $RELEASE ..."
        pushd "$BASEDIR" > /dev/null
        scram p CMSSW "$RELEASE"
        popd > /dev/null
    fi

    pushd "$BASEDIR/$RELEASE/src" > /dev/null
    eval $(scram runtime -sh)
    popd > /dev/null
    echo "  CMSSW_BASE = $CMSSW_BASE"
}


# ═════════════════════════════════════════════════════════════════════════════
# STEP 0: LHE + GEN + SIM
# ═════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_TO" -le 0 ]; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 0: LHE + GEN + SIM  ($CMSSW_GS)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
setup_cmssw "$CMSSW_GS"

# Install fragment
mkdir -p "$CMSSW_BASE/src/Configuration/GenProduction/python"
cp "$FRAGMENT_SRC" "$CMSSW_BASE/src/Configuration/GenProduction/python/${SAMPLE}.py"
sed -i "s|__GRIDPACK__|${GRIDPACK_ABS}|g" "$CMSSW_BASE/src/Configuration/GenProduction/python/${SAMPLE}.py"
sed -i "s|__MASS__|${MASS_POINT}|g"       "$CMSSW_BASE/src/Configuration/GenProduction/python/${SAMPLE}.py"
# Set mMax to 2x the mass (or at least 2 GeV) for the BW window
MASS_MAX=$(python3 -c "print(max(2.0, 2.0 * ${MASS_POINT}))")
sed -i "s|__MASSMAX__|${MASS_MAX}|g"      "$CMSSW_BASE/src/Configuration/GenProduction/python/${SAMPLE}.py"

pushd "$CMSSW_BASE/src" > /dev/null
scram b -j "$NTHREADS" 2>&1 | tail -3
popd > /dev/null

cmsDriver.py "Configuration/GenProduction/python/${SAMPLE}.py" \
    --python_filename "${CAMPAIGN_GS}_cfg.py" \
    --eventcontent RAWSIM,LHE \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier GEN-SIM,LHE \
    --fileout "file:${FILE_GS}" \
    --conditions "$GT_GS" \
    --beamspot DBrealistic \
    --step LHE,GEN,SIM \
    --geometry DB:Extended \
    --era Run3_2024 \
    --nThreads "$NTHREADS" \
    --customise_commands "process.source.numberEventsInLuminosityBlock=cms.untracked.uint32(100)\\nprocess.RandomNumberGeneratorService.externalLHEProducer.initialSeed=${SEED}" \
    --mc \
    -n "$NEVENTS" || exit $?

echo "  ✓ GEN-SIM done: $(ls -lh ${FILE_GS} | awk '{print $5}')"
echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1: DIGI + DATAMIX + L1 + DIGI2RAW + HLT
# ═════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_TO" -le 1 ]; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 1: DIGI + Premix + L1 + HLT  ($CMSSW_DR)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
setup_cmssw "$CMSSW_DR"

if [ "$USE_PILEUP" = true ]; then
    echo "  Using premixed pileup from: $PREMIX_DATASET"
    cmsDriver.py \
        --python_filename "${CAMPAIGN_DR}_step1_cfg.py" \
        --eventcontent PREMIXRAW \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --datatier GEN-SIM-RAW \
        --filein "file:${FILE_GS}" \
        --fileout "file:${FILE_DR}" \
        --pileup_input "dbs:${PREMIX_DATASET}" \
        --conditions "$GT_DR" \
        --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:2024v14 \
        --procModifiers premix_stage2 \
        --geometry DB:Extended \
        --datamix PreMix \
        --era Run3_2024 \
        --mc \
        --nThreads "$NTHREADS" \
        -n "$NEVENTS" || exit $?
else
    echo "  ⚠  Running WITHOUT pileup (--no-pileup mode)"
    cmsDriver.py \
        --python_filename "${CAMPAIGN_DR}_step1_cfg.py" \
        --eventcontent RAWSIM \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --datatier GEN-SIM-RAW \
        --filein "file:${FILE_GS}" \
        --fileout "file:${FILE_DR}" \
        --conditions "$GT_DR" \
        --step DIGI,L1,DIGI2RAW,HLT:2024v14 \
        --geometry DB:Extended \
        --era Run3_2024 \
        --mc \
        --nThreads "$NTHREADS" \
        -n "$NEVENTS" || exit $?
fi

echo "  ✓ DIGI+HLT done: $(ls -lh ${FILE_DR} | awk '{print $5}')"
echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2: RECO → AOD
# ═════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_TO" -le 2 ]; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 2: RECO → AOD  ($CMSSW_DR)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
setup_cmssw "$CMSSW_DR"

cmsDriver.py \
    --python_filename "${CAMPAIGN_DR}_step2_cfg.py" \
    --eventcontent AODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier AODSIM \
    --filein "file:${FILE_DR}" \
    --fileout "file:${FILE_RECO}" \
    --conditions "$GT_DR" \
    --step RAW2DIGI,L1Reco,RECO,RECOSIM \
    --geometry DB:Extended \
    --era Run3_2024 \
    --mc \
    --nThreads "$NTHREADS" \
    -n "$NEVENTS" || exit $?

echo "  ✓ RECO done: $(ls -lh ${FILE_RECO} | awk '{print $5}')"
echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3: MiniAOD v6
# ═════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_TO" -le 3 ]; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 3: MiniAOD v6  ($CMSSW_MINI)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
setup_cmssw "$CMSSW_MINI"

cmsDriver.py \
    --python_filename "${CAMPAIGN_MINI}_cfg.py" \
    --eventcontent MINIAODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier MINIAODSIM \
    --filein "file:${FILE_RECO}" \
    --fileout "file:${FILE_MINI}" \
    --conditions "$GT_MINI" \
    --step PAT \
    --geometry DB:Extended \
    --era Run3_2024 \
    --mc \
    --nThreads "$NTHREADS" \
    -n "$NEVENTS" || exit $?

echo "  ✓ MiniAOD done: $(ls -lh ${FILE_MINI} | awk '{print $5}')"
echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4: NanoAOD v15
# ═════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_TO" -le 4 ]; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 4: NanoAOD v15  ($CMSSW_MINI)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
setup_cmssw "$CMSSW_MINI"

cmsDriver.py \
    --python_filename "${CAMPAIGN_NANO}_cfg.py" \
    --eventcontent NANOAODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier NANOAODSIM \
    --filein "file:${FILE_MINI}" \
    --fileout "file:${FILE_NANO}" \
    --conditions "$GT_MINI" \
    --step NANO \
    --era Run3_2024 \
    --scenario pp \
    --mc \
    --nThreads "$NTHREADS" \
    -n "$NEVENTS" || exit $?

echo "  ✓ NanoAOD done: $(ls -lh ${FILE_NANO} | awk '{print $5}')"
echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5: BTV NanoAOD (allPF)
# ═════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_TO" -le 5 ]; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 5: BTV NanoAOD allPF  ($CMSSW_BTVNANO)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
setup_cmssw "$CMSSW_BTVNANO"

cmsDriver.py \
    --python_filename "${CAMPAIGN_BTVNANO}_cfg.py" \
    --eventcontent NANOAODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_btv_cff.BTVCustomNanoAOD_allPF \
    --datatier NANOAODSIM \
    --filein "file:${FILE_MINI}" \
    --fileout "file:${FILE_BTVNANO}" \
    --conditions "$GT_MINI" \
    --step NANO \
    --era Run3_2024 \
    --scenario pp \
    --mc \
    --nThreads "$NTHREADS" \
    -n "$NEVENTS" || exit $?

echo "  ✓ BTV NanoAOD done: $(ls -lh ${FILE_BTVNANO} | awk '{print $5}')"
echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Production Complete!                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Output files:                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
ls -lh *.root 2>/dev/null
echo ""
echo "Inspect NanoAOD:"
echo "  python3 -c \"import uproot; f=uproot.open('${FILE_NANO}'); print(f['Events'].keys()[:20])\""
echo ""
