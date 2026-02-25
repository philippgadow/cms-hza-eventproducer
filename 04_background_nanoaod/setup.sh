#!/bin/bash

# Setup script for background btvNanoAllPF production (MiniAOD → NanoAOD)
# Reprocesses centrally-produced MiniAOD into BTV NanoAOD with all PF candidates.
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
GT="150X_mcRun3_2024_realistic_v2"
ERA="Run3_2024"
NTHREADS=4
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
echo "Setting up background btvNanoAllPF environment"
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

PSET_BTV="btvnano_cfg.py"
if [ ! -f "$PSET_BTV" ]; then
    echo "Generating cmsDriver config: ${PSET_BTV} ..."
    cmsDriver.py \
        --python_filename "$PSET_BTV" \
        --eventcontent NANOAODSIM \
        --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_btv_cff.BTVCustomNanoAOD_allPF \
        --datatier NANOAODSIM \
        --filein "file:dummy.root" \
        --fileout "file:btvnano_output.root" \
        --conditions $GT \
        --step NANO \
        --geometry DB:Extended \
        --era $ERA \
        --mc \
        --nThreads $NTHREADS \
        -n -1 \
        --no_exec
    echo "  → ${SCRIPT_DIR}/${PSET_BTV}"
else
    echo "PSet already exists: ${SCRIPT_DIR}/${PSET_BTV}"
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
echo "  1. Check datasets.txt for the list of NanoAOD datasets"
echo "  2. Dry run:   ./submit.sh"
echo "  3. Submit:    ./submit.sh --submit"
echo ""
