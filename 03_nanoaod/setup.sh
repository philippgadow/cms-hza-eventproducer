#!/bin/bash

# Setup script for custom NanoAOD reprocessing (BTV, HZa, and BPH NanoAOD)
# Reprocesses existing MiniAOD files into specialised NanoAOD formats.
#
# Usage:
#   source setup.sh
#
# This sets up CMSSW_15_0_18, installs the local HZa NanoAOD customisation,
# generates the cmsDriver configs, and initialises the grid proxy + CRAB.

# Important: this script is typically sourced.
# Do not enable `set -e` in the caller's interactive shell, otherwise
# non-zero returns from completion helpers can terminate the terminal.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -e
fi

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
echo "Setting up NanoAOD reprocessing environment"
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

# ─── Install local HZa NanoAOD customisation ─────────────────────────────────
CUSTOM_SRC="${SCRIPT_DIR}/customizations/PhysicsTools/HZaNano"
CUSTOM_DST="${CMSSW_BASE}/src/PhysicsTools/HZaNano"

if [ -d "$CUSTOM_SRC" ]; then
    echo "Installing local HZa NanoAOD customisation into CMSSW..."
    mkdir -p "${CMSSW_BASE}/src/PhysicsTools"
    rm -rf "$CUSTOM_DST"
    cp -r "$CUSTOM_SRC" "$CUSTOM_DST"
    echo "Building local CMSSW python package..."
    scram b -j $NTHREADS
    cd "$SCRIPT_DIR"
    echo "  → Installed: ${CUSTOM_DST}"
    echo ""
else
    echo "WARNING: Local HZa NanoAOD customisation not found at ${CUSTOM_SRC}"
    echo ""
fi

# ─── Generate cmsDriver configs ──────────────────────────────────────────────
cd "$SCRIPT_DIR"

# 1. BTV NanoAOD (allPF) — full PF candidates for jet-substructure studies
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

# 2. HZa NanoAOD — BTV allPF plus extended H->Za gen truth ancestry
PSET_HZA="hzanano_cfg.py"
if [ ! -f "$PSET_HZA" ]; then
    echo "Generating cmsDriver config: ${PSET_HZA} ..."
    cmsDriver.py \
        --python_filename "$PSET_HZA" \
        --eventcontent NANOAODSIM \
        --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_btv_cff.BTVCustomNanoAOD_allPF,PhysicsTools/HZaNano/custom_hza_cff.HZaCustomNanoAOD \
        --datatier NANOAODSIM \
        --filein "file:dummy.root" \
        --fileout "file:hzanano_output.root" \
        --conditions $GT \
        --step NANO \
        --geometry DB:Extended \
        --era $ERA \
        --mc \
        --nThreads $NTHREADS \
        -n -1 \
        --no_exec
    echo "  → ${SCRIPT_DIR}/${PSET_HZA}"
else
    echo "PSet already exists: ${SCRIPT_DIR}/${PSET_HZA}"
fi

# 3. BPH NanoAOD — B-physics collections (dimuon, tracks, V0s, B→K/Kshort/Lambda)
PSET_BPH="bphnano_cfg.py"
if [ ! -f "$PSET_BPH" ]; then
    echo "Generating cmsDriver config: ${PSET_BPH} ..."
    cmsDriver.py \
        --python_filename "$PSET_BPH" \
        --eventcontent NANOAODSIM \
        --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_bph_cff.nanoAOD_customizeBPH \
        --datatier NANOAODSIM \
        --filein "file:dummy.root" \
        --fileout "file:bphnano_output.root" \
        --conditions $GT \
        --step NANO \
        --geometry DB:Extended \
        --era $ERA \
        --mc \
        --nThreads $NTHREADS \
        -n -1 \
        --no_exec
    echo "  → ${SCRIPT_DIR}/${PSET_BPH}"
else
    echo "PSet already exists: ${SCRIPT_DIR}/${PSET_BPH}"
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
echo "Available NanoAOD formats:"
echo "  btvnano  — BTV NanoAOD with all PF candidates (PFCands)"
echo "  hzanano  — BTV NanoAOD + extended H→Za gen truth ancestry"
echo "  bphnano  — BPH NanoAOD with B-physics collections (MuMu, tracks, V0s, ...)"
echo ""
echo "Next steps:"
echo "  1. Edit REPROCESS_POINTS in submit.sh for the mass points you want"
echo "  2. Dry run:   ./submit.sh --format hzanano"
echo "  3. Submit:    ./submit.sh --format hzanano --submit"
echo ""
