#!/bin/bash

# Setup script for btvNanoAllPF production (MiniAOD → NanoAOD)
# Reprocesses centrally-produced MiniAOD (MC backgrounds & data) into
# BTV NanoAOD with all PF candidates.
#
# Usage:
#   source setup.sh
#
# This sets up CMSSW_15_0_18, generates the btvnano_cfg.py cmsDriver config,
# and initialises the grid proxy + CRAB.

set -e

# ─── Configuration ────────────────────────────────────────────────────────────
RELEASE="CMSSW_15_0_18"
ARCH="el9_amd64_gcc12"
ERA="Run3_2024"
NTHREADS=4
# GT is set per-mode below (MC and data PSet generation)
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source /cvmfs/cms.cern.ch/cmsset_default.sh

# Check if we need el9 container
OS_VERSION=$(cat /etc/os-release | grep VERSION_ID | cut -d'"' -f2 | cut -d'.' -f1)

if [ -z "$SINGULARITY_NAME" ] && [ ! -d "/.singularity.d" ] && [ "$OS_VERSION" != "9" ]; then
    echo "============================================"
    echo "Detected OS version: el${OS_VERSION}"
    echo "Starting el9 singularity container..."
    echo "After entering, please source this script again:"
    echo "  source setup.sh"
    echo "============================================"
    cmssw-el9
    return 0 2>/dev/null || exit 0
fi

if [ "$OS_VERSION" == "9" ]; then
    echo "Running on native el9 — no container needed"
fi

echo "============================================"
echo "Setting up btvNanoAllPF environment (MC + data)"
echo "============================================"

export SCRAM_ARCH=$ARCH

# ─── Set up CMSSW ─────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"

if [ -r ${RELEASE}/src ]; then
    echo "CMSSW ${RELEASE} already exists"
else
    echo "Creating CMSSW ${RELEASE}..."
    scram p CMSSW $RELEASE
fi

cd ${RELEASE}/src
eval $(scram runtime -sh)

echo ""
echo "CMSSW environment set up successfully!"
echo "SCRAM_ARCH: $SCRAM_ARCH"
echo "CMSSW_BASE: $CMSSW_BASE"
echo ""

# ─── Generate cmsDriver config ───────────────────────────────────────────────
cd "$SCRIPT_DIR"

# ── MC PSet ───────────────────────────────────────────────────────────────────
GT_MC="150X_mcRun3_2024_realistic_v2"
PSET_MC="btvnano_mc_cfg.py"
if [ ! -f "$PSET_MC" ]; then
    echo "Generating MC cmsDriver config: ${PSET_MC} ..."
    cmsDriver.py \
        --python_filename "$PSET_MC" \
        --eventcontent NANOAODSIM \
        --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_btv_cff.BTVCustomNanoAOD_allPF \
        --datatier NANOAODSIM \
        --filein "file:dummy.root" \
        --fileout "file:btvnano_output.root" \
        --conditions $GT_MC \
        --step NANO \
        --geometry DB:Extended \
        --era $ERA \
        --mc \
        --nThreads $NTHREADS \
        -n -1 \
        --no_exec
    echo "  → ${SCRIPT_DIR}/${PSET_MC}"
else
    echo "MC PSet already exists: ${SCRIPT_DIR}/${PSET_MC}"
fi

# ── Data PSet ─────────────────────────────────────────────────────────────────
GT_DATA="150X_dataRun3_v2"
PSET_DATA="btvnano_data_cfg.py"
if [ ! -f "$PSET_DATA" ]; then
    echo "Generating data cmsDriver config: ${PSET_DATA} ..."
    cmsDriver.py \
        --python_filename "$PSET_DATA" \
        --eventcontent NANOAOD \
        --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_btv_cff.BTVCustomNanoAOD_allPF \
        --datatier NANOAOD \
        --filein "file:dummy.root" \
        --fileout "file:btvnano_output.root" \
        --conditions $GT_DATA \
        --step NANO \
        --geometry DB:Extended \
        --era $ERA \
        --data \
        --nThreads $NTHREADS \
        -n -1 \
        --no_exec
    echo "  → ${SCRIPT_DIR}/${PSET_DATA}"
else
    echo "Data PSet already exists: ${SCRIPT_DIR}/${PSET_DATA}"
fi

echo ""

# ─── Grid proxy + CRAB ───────────────────────────────────────────────────────
echo "============================================"
echo "Setting up grid proxy..."
echo "============================================"

# DESY-specific grid environment
if [ -r /cvmfs/grid.desy.de/etc/profile.d/grid-ui-env.sh ]; then
    echo "Sourcing DESY grid environment"
    source /cvmfs/grid.desy.de/etc/profile.d/grid-ui-env.sh
fi

source /cvmfs/cms.cern.ch/common/crab-setup.sh
voms-proxy-init -rfc -voms cms -valid 192:00

echo ""
echo "============================================"
echo "Setup complete!"
echo "============================================"
echo ""
echo "You are now in: $PWD"
echo ""
echo "Next steps:"
echo "  1. Check datasets_mc.txt / datasets_data.txt for the dataset lists"
echo "  2. Dry run MC:   ./submit.sh"
echo "  3. Submit MC:    ./submit.sh --submit"
echo "  4. Dry run data: ./submit.sh --data"
echo "  5. Submit data:  ./submit.sh --data --submit"
echo ""
