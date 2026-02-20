#!/bin/bash
#######################################################################
# Generate POWHEG gridpack for gg→H using HTCondor
#
# Prerequisites: run setup_cms_powheg.sh first to set up CMSSW and
#                compile POWHEG (stage 0).
#
# This script:
#   1. Cleans any old grids from a previous run
#   2. Copies powheg.input from this directory into the POWHEG workdir
#   3. Submits grid generation (stages 1,2,3) to HTCondor in parallel
#   4. Packages the gridpack tarball (stage 9)
#
# The powheg.input file in this directory is the single source of
# truth for all physics settings (beam energy, PDF, Higgs mass, etc.).
#
# Usage:
#   ./generate_gridpack.sh              # submit stages 1-3 to condor
#   ./generate_gridpack.sh --local      # run everything locally (~30-60 min)
#   ./generate_gridpack.sh --tarball    # only run stage 9 (after condor jobs finish)
#   ./generate_gridpack.sh --clean      # only clean old grids, don't submit
#
#######################################################################

set -e

# ── Configuration ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMSSW_VERSION="CMSSW_13_3_0"
SCRAM_ARCH="el9_amd64_gcc12"
PROCESS_NAME="gg_H_quark-mass-effects"
FOLDER_NAME="ggH_M125"
INPUT_CARD="powheg.input"

# HTCondor queue flavours for each stage
# espresso=20min, longlunch=2h, workday=8h, tomorrow=1d
QUEUE_STAGES="1:longlunch,2:longlunch,3:workday"
N_PARALLEL_JOBS=10
N_XGRID_ITER=5

# Derived paths
CMSSW_DIR="${SCRIPT_DIR}/${CMSSW_VERSION}"
POWHEG_BASE="${CMSSW_DIR}/src/genproductions/bin/Powheg"
POWHEG_WORK="${POWHEG_BASE}/${FOLDER_NAME}/POWHEG-BOX/${PROCESS_NAME}"
GRIDPACK_TARBALL="${PROCESS_NAME}_${SCRAM_ARCH}_${CMSSW_VERSION}_${FOLDER_NAME}.tgz"

# ── Parse arguments ─────────────────────────────────────────────────
MODE="condor"
for arg in "$@"; do
    case "$arg" in
        --local)   MODE="local" ;;
        --tarball) MODE="tarball" ;;
        --clean)   MODE="clean" ;;
        --help|-h)
            head -25 "$0" | grep '^#' | sed 's/^# *//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--local|--tarball|--clean|--help]"
            exit 1
            ;;
    esac
done

# ── Setup CMSSW environment ─────────────────────────────────────────
echo "=========================================="
echo "POWHEG Gridpack Generation"
echo "=========================================="
echo "Mode:    ${MODE}"
echo "CMSSW:   ${CMSSW_VERSION}"
echo "Process: ${PROCESS_NAME}"
echo "Folder:  ${FOLDER_NAME}"

# Check prerequisites
if [ ! -d "${CMSSW_DIR}" ]; then
    echo ""
    echo "ERROR: ${CMSSW_VERSION} not found. Run setup_cms_powheg.sh first."
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/${INPUT_CARD}" ]; then
    echo ""
    echo "ERROR: ${INPUT_CARD} not found in ${SCRIPT_DIR}"
    exit 1
fi

echo ""
echo "Setting up CMSSW environment..."
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=${SCRAM_ARCH}
cd "${CMSSW_DIR}/src"
eval $(scramv1 runtime -sh)

# Verify POWHEG was compiled (stage 0)
if [ ! -f "${POWHEG_WORK}/pwhg_main" ]; then
    echo ""
    echo "ERROR: pwhg_main not found at ${POWHEG_WORK}"
    echo "       Run setup_cms_powheg.sh and compile first (stage 0):"
    echo ""
    echo "  cd ${POWHEG_BASE}"
    echo "  python3 run_pwg_condor.py -p 0 -i ${INPUT_CARD} -m ${PROCESS_NAME} -f ${FOLDER_NAME}"
    exit 1
fi

# ── Print physics settings from input card ───────────────────────────
echo ""
echo "Physics settings from ${INPUT_CARD}:"
echo "  $(grep -E '^\s*ebeam1' "${SCRIPT_DIR}/${INPUT_CARD}")"
echo "  $(grep -E '^\s*ebeam2' "${SCRIPT_DIR}/${INPUT_CARD}")"
echo "  $(grep -E '^\s*hmass'  "${SCRIPT_DIR}/${INPUT_CARD}")"
echo "  $(grep -E '^\s*lhans1' "${SCRIPT_DIR}/${INPUT_CARD}")"
EBEAM=$(grep -oP '^\s*ebeam1\s+\K[0-9]+' "${SCRIPT_DIR}/${INPUT_CARD}")
SQRT_S=$(echo "2 * ${EBEAM}" | bc)
echo "  => sqrt(s) = ${SQRT_S} GeV"
echo "=========================================="

# ── Function: clean old grids ────────────────────────────────────────
clean_old_grids() {
    echo ""
    echo "[Clean] Removing old grid files from ${POWHEG_WORK}..."
    cd "${POWHEG_WORK}"
    rm -f pwg*grid*.dat pwg*ubound*.dat pwg*bound*.dat \
          pwg-stat.dat pwg-*-stat.dat pwgevents*.lhe \
          pwgborngrid.top pwg-btlgrid.top pwg-rmngrid.top pwghistnorms.top \
          FlavRegList bornequiv virtequiv realequivregions-* \
          pwgseeds.dat fort.18 \
          powheg.input.* 2>/dev/null || true
    echo "  Done."
}

# ── Function: copy input card ────────────────────────────────────────
copy_input_card() {
    echo ""
    echo "[Setup] Copying ${INPUT_CARD} to POWHEG working directories..."
    # Copy to the Powheg base (where run_pwg scripts expect it)
    cp "${SCRIPT_DIR}/${INPUT_CARD}" "${POWHEG_BASE}/${INPUT_CARD}"
    # Copy to the folder-level directory (used by tarball stage 9)
    cp "${SCRIPT_DIR}/${INPUT_CARD}" "${POWHEG_BASE}/${FOLDER_NAME}/${INPUT_CARD}"
    # Copy to the POWHEG working directory
    cp "${SCRIPT_DIR}/${INPUT_CARD}" "${POWHEG_WORK}/${INPUT_CARD}"
    echo "  Done."
}

# ── Function: patch gridpack tarball ─────────────────────────────────
# The genproductions tarball script (run_tar_*.sh) unconditionally appends
# rwl_file 'pwg-rwl.dat' and related reweighting parameters to powheg.input.
# Since we don't ship pwg-rwl.dat, this causes POWHEG to fail at runtime.
# This function removes those injected lines from the packaged powheg.input.
patch_gridpack() {
    local TARBALL="$1"
    echo ""
    echo "[Patch] Removing rwl_file from gridpack powheg.input..."
    local PATCHDIR=$(mktemp -d)
    cd "${PATCHDIR}"
    tar xzf "${TARBALL}"
    # Remove lines injected by run_tar_*.sh that reference missing rwl data
    sed -i '/^rwl_file/d'           powheg.input
    sed -i '/^rwl_group_events/d'   powheg.input
    sed -i '/^rwl_format_rwgt/d'    powheg.input
    sed -i '/^lhapdf6maxsets/d'     powheg.input
    # Re-add lhapdf6maxsets (needed) without rwl_file
    echo "lhapdf6maxsets 50" >> powheg.input
    tar czf "${TARBALL}" *
    cd /tmp && rm -rf "${PATCHDIR}"
    echo "  Done."
}

# ── Execute based on mode ────────────────────────────────────────────
cd "${POWHEG_BASE}"

case "${MODE}" in

    clean)
        clean_old_grids
        echo ""
        echo "Cleaned. No jobs submitted."
        ;;

    condor)
        echo ""
        echo "WARNING: The gg_H_quark-mass-effects process does NOT support"
        echo "         parallelstage/xgriditeration used by the condor approach."
        echo "         Use --local mode instead for this process."
        echo ""
        read -p "Continue anyway? [y/N] " REPLY
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            echo "Aborted. Use: $0 --local"
            exit 0
        fi
        clean_old_grids
        copy_input_card
        cd "${POWHEG_BASE}"
        echo ""
        echo "[Submit] Submitting grid generation to HTCondor (stages 1,2,3)..."
        echo "  Parallel jobs: ${N_PARALLEL_JOBS}"
        echo "  Xgrid iterations: ${N_XGRID_ITER}"
        echo "  Queue flavours: ${QUEUE_STAGES}"
        echo ""
        python3 ./run_pwg_parallel_condor.py \
            -p 123 \
            -i "${INPUT_CARD}" \
            -m "${PROCESS_NAME}" \
            -f "${FOLDER_NAME}" \
            -q "${QUEUE_STAGES}" \
            -j "${N_PARALLEL_JOBS}" \
            -x "${N_XGRID_ITER}"
        echo ""
        echo "=========================================="
        echo "Condor jobs submitted!"
        echo ""
        echo "Monitor with:"
        echo "  condor_q"
        echo ""
        echo "Check DAG status:"
        echo "  cat ${POWHEG_BASE}/run_${FOLDER_NAME}.dag.dagman.out"
        echo ""
        echo "When all jobs finish, create the tarball:"
        echo "  $0 --tarball"
        echo "=========================================="
        ;;

    local)
        clean_old_grids
        copy_input_card
        cd "${POWHEG_BASE}"
        echo ""
        echo "[Local] Running grid generation locally (this will take ~30-60 min)..."
        echo "  Started at: $(date)"
        echo ""

        # gg_H_quark-mass-effects does NOT support parallelstage/xgriditeration.
        # We must run pwhg_main sequentially to compute grids + upper bounds.
        cd "${POWHEG_WORK}"

        # Create a working copy of powheg.input with concrete values
        cp powheg.input powheg.input.bak
        sed -i 's/^numevts NEVENTS/numevts 500/' powheg.input
        sed -i 's/^iseed SEED/iseed 42/' powheg.input

        # Run POWHEG (pipe empty stdin to avoid interactive prompts)
        echo "" | time ./pwhg_main 2>&1 | tee pwhg_main_local.log
        PWHG_EXIT=$?

        # Restore original powheg.input
        mv powheg.input.bak powheg.input

        if [ ${PWHG_EXIT} -ne 0 ]; then
            echo "ERROR: pwhg_main exited with code ${PWHG_EXIT}"
            echo "Check log: ${POWHEG_WORK}/pwhg_main_local.log"
            exit 1
        fi

        echo ""
        echo "  Finished at: $(date)"

        # Verify that grid files were produced
        echo ""
        echo "[Verify] Checking for grid files in ${POWHEG_WORK}..."
        GRID_OK=true
        for GFILE in pwggrid.dat pwgubound.dat; do
            if [ -f "${POWHEG_WORK}/${GFILE}" ]; then
                echo "  ✓ ${GFILE} ($(du -h ${POWHEG_WORK}/${GFILE} | cut -f1))"
            else
                echo "  ✗ ${GFILE} MISSING"
                GRID_OK=false
            fi
        done
        # Also list any other pwg*.dat files produced
        echo "  All pwg*.dat files:"
        ls -lh "${POWHEG_WORK}"/pwg*.dat 2>/dev/null || echo "    (none)"

        if [ "${GRID_OK}" != "true" ]; then
            echo ""
            echo "ERROR: Grid files not produced. Check pwhg_main_local.log"
            exit 1
        fi

        # Copy grid files + pwhg_main to the folderName directory where
        # the tarball stage (run_pwg_condor.py -p 9) expects them.
        FOLDER_DIR="${POWHEG_BASE}/${FOLDER_NAME}"
        echo ""
        echo "[Copy] Copying grid files to ${FOLDER_DIR}..."
        cp -p "${POWHEG_WORK}"/pwg*.dat "${FOLDER_DIR}/"
        cp -p "${POWHEG_WORK}/pwhg_main" "${FOLDER_DIR}/"
        # Copy .top files if they exist (for validation plots)
        cp -p "${POWHEG_WORK}"/*.top "${FOLDER_DIR}/" 2>/dev/null || true
        echo "  Done."

        # Fall through to tarball creation
        cd "${POWHEG_BASE}"
        echo ""
        echo "[Tarball] Creating gridpack (stage 9)..."
        python3 ./run_pwg_condor.py \
            -p 9 \
            -i "${INPUT_CARD}" \
            -m "${PROCESS_NAME}" \
            -f "${FOLDER_NAME}"

        if [ -f "${POWHEG_BASE}/${GRIDPACK_TARBALL}" ]; then
            patch_gridpack "${POWHEG_BASE}/${GRIDPACK_TARBALL}"
            cp "${POWHEG_BASE}/${GRIDPACK_TARBALL}" "${SCRIPT_DIR}/${GRIDPACK_TARBALL}"
            echo ""
            echo "=========================================="
            echo "Gridpack ready!"
            echo "  ${SCRIPT_DIR}/${GRIDPACK_TARBALL}"
            ls -lh "${SCRIPT_DIR}/${GRIDPACK_TARBALL}"
            echo ""
            echo "Verify contents:"
            TMPDIR_CHECK=$(mktemp -d)
            cd "${TMPDIR_CHECK}" && tar xzf "${SCRIPT_DIR}/${GRIDPACK_TARBALL}" 2>/dev/null
            echo "  Grid files in tarball:"
            ls -lh pwg*.dat 2>/dev/null || echo "    (none — ERROR!)"
            echo "  Beam energy:"
            grep ebeam powheg.input 2>/dev/null || echo "    (could not verify)"
            cd /tmp && rm -rf "${TMPDIR_CHECK}"
            echo "=========================================="
        else
            echo "ERROR: Tarball not found at ${POWHEG_BASE}/${GRIDPACK_TARBALL}"
            exit 1
        fi
        ;;

    tarball)
        copy_input_card
        cd "${POWHEG_BASE}"
        echo ""
        echo "[Tarball] Creating gridpack (stage 9)..."
        cd "${POWHEG_BASE}"
        python3 ./run_pwg_condor.py \
            -p 9 \
            -i "${INPUT_CARD}" \
            -m "${PROCESS_NAME}" \
            -f "${FOLDER_NAME}"

        if [ -f "${POWHEG_BASE}/${GRIDPACK_TARBALL}" ]; then
            patch_gridpack "${POWHEG_BASE}/${GRIDPACK_TARBALL}"
            cp "${POWHEG_BASE}/${GRIDPACK_TARBALL}" "${SCRIPT_DIR}/${GRIDPACK_TARBALL}"
            echo ""
            echo "=========================================="
            echo "Gridpack ready!"
            echo "  ${SCRIPT_DIR}/${GRIDPACK_TARBALL}"
            ls -lh "${SCRIPT_DIR}/${GRIDPACK_TARBALL}"
            echo ""
            echo "Verify beam energy:"
            TMPDIR_CHECK=$(mktemp -d)
            cd "${TMPDIR_CHECK}" && tar xzf "${SCRIPT_DIR}/${GRIDPACK_TARBALL}" 2>/dev/null
            grep ebeam powheg.input 2>/dev/null || echo "  (could not verify)"
            cd /tmp && rm -rf "${TMPDIR_CHECK}"
            echo "=========================================="
        else
            echo "ERROR: Tarball not found at ${POWHEG_BASE}/${GRIDPACK_TARBALL}"
            exit 1
        fi
        ;;

esac
