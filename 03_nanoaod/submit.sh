#!/bin/bash

# Submit custom NanoAOD reprocessing jobs via CRAB
# Reads existing MiniAOD files and produces specialised NanoAOD formats.
#
# Supported formats:
#   btvnano  — BTV NanoAOD with all PF candidates (PFCands)
#   bphnano  — BPH NanoAOD with B-physics collections (MuMu, tracks, V0s, ...)
#
# Usage:
#   ./submit.sh --format btvnano             # dry run
#   ./submit.sh --format bphnano --submit    # generate configs and submit

set -e

# ─── Configuration ────────────────────────────────────────────────────────────
NTHREADS=4
GT="150X_mcRun3_2024_realistic_v2"

CAMPAIGN="RunIII2024Summer24"
SITE="T2_DE_DESY"
STORAGE_BASE="/store/user/$USER/ggH_HZa_signals/${CAMPAIGN}"
XROOTD="root://dcache-cms-xrootd.desy.de:1094"

# Mass points to reprocess and their CRAB task timestamps
# Format: "mass_GeV:timestamp_dir"
# Find timestamps with:
#   xrdfs $XROOTD ls /store/user/$USER/ggH_HZa_signals/$CAMPAIGN/<sample>/$CAMPAIGN/
REPROCESS_POINTS=(
    "1.0:260220_232829"
)
# ──────────────────────────────────────────────────────────────────────────────

# ─── Parse arguments ─────────────────────────────────────────────────────────
FORMAT=""
AUTO_SUBMIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --submit)
            AUTO_SUBMIT=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./submit.sh --format <btvnano|bphnano> [--submit]"
            echo ""
            echo "Options:"
            echo "  --format <fmt>  NanoAOD format: btvnano or bphnano (required)"
            echo "  --submit        Submit CRAB jobs (default: dry run only)"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: ./submit.sh --format <btvnano|bphnano> [--submit]"
            exit 1
            ;;
    esac
done

if [ -z "$FORMAT" ]; then
    echo "ERROR: --format is required"
    echo "Usage: ./submit.sh --format <btvnano|bphnano> [--submit]"
    exit 1
fi

# ─── Format-specific settings ────────────────────────────────────────────────
case "$FORMAT" in
    btvnano)
        PSET_NAME="btvnano_cfg.py"
        OUTPUT_FILE="btvnano_output.root"
        CAMPAIGN_TAG="RunIII2024Summer24BTVNanoAllPF"
        CRAB_PREFIX="crab_btvnano"
        FORMAT_LABEL="BTV NanoAOD (allPF)"
        ;;
    bphnano)
        PSET_NAME="bphnano_cfg.py"
        OUTPUT_FILE="bphnano_output.root"
        CAMPAIGN_TAG="RunIII2024Summer24BPHNano"
        CRAB_PREFIX="crab_bphnano"
        FORMAT_LABEL="BPH NanoAOD"
        ;;
    *)
        echo "ERROR: Unknown format '${FORMAT}'. Must be 'btvnano' or 'bphnano'."
        exit 1
        ;;
esac

# ─── Sanity checks ───────────────────────────────────────────────────────────
if [ -z "$CMSSW_BASE" ]; then
    echo "ERROR: CMSSW environment not set up!"
    echo "Please run first:  source setup.sh"
    exit 1
fi

voms-proxy-info --exists --valid 12:00
if [ $? -ne 0 ]; then
    echo "ERROR: Valid grid proxy required!"
    echo "Please run: voms-proxy-init -rfc -voms cms -valid 192:00"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSET="${SCRIPT_DIR}/${PSET_NAME}"

if [ ! -f "$PSET" ]; then
    echo "ERROR: PSet not found: $PSET"
    echo "Please run first:  source setup.sh"
    exit 1
fi

echo "========================================"
echo "${FORMAT_LABEL} Reprocessing"
echo "========================================"
echo "Format:  ${FORMAT}"
echo "CMSSW:   $(basename $CMSSW_BASE)"
echo "GT:      ${GT}"
echo "Site:    ${SITE}"
echo "Storage: ${STORAGE_BASE}"
echo "PSet:    ${PSET}"
echo ""

# ─── Process each mass point ─────────────────────────────────────────────────
for entry in "${REPROCESS_POINTS[@]}"; do
    MASS="${entry%%:*}"
    TIMESTAMP="${entry##*:}"
    MASS_STR=$(echo "$MASS" | sed 's/\./_/g')
    SAMPLE_NAME="ggH_HZa_mA${MASS_STR}GeV"
    INPUT_DIR="${STORAGE_BASE}/${SAMPLE_NAME}/${CAMPAIGN}/${TIMESTAMP}/0000"

    echo "----------------------------------------"
    echo "Mass point: m_a = ${MASS} GeV"
    echo "Sample:     ${SAMPLE_NAME}"
    echo "Input dir:  ${INPUT_DIR}"
    echo ""

    # List MiniAOD files via xrootd
    echo "Querying MiniAOD files..."
    MINIFILES=$(xrdfs $XROOTD ls "$INPUT_DIR" 2>/dev/null | grep "MiniAODv6" | sort)
    NFILES=$(echo "$MINIFILES" | wc -l)
    echo "Found ${NFILES} MiniAOD files"

    if [ "$NFILES" -eq 0 ]; then
        echo "WARNING: No MiniAOD files found — skipping ${SAMPLE_NAME}"
        continue
    fi

    # Build Python list of xrootd URLs
    PYLIST=$(echo "$MINIFILES" | while read -r f; do
        echo "    '${XROOTD}/${f}',"
    done)

    # Create CRAB config
    CRAB_CFG="${SCRIPT_DIR}/${CRAB_PREFIX}_${SAMPLE_NAME}.py"
    cat > "$CRAB_CFG" << EOF
from CRABClient.UserUtilities import config
config = config()

# General
config.General.requestName = '${SAMPLE_NAME}_${CAMPAIGN_TAG}'
config.General.workArea = 'crab_projects_${CAMPAIGN_TAG}'
config.General.transferOutputs = True
config.General.transferLogs = True

# Job type — Analysis plugin reads existing MiniAOD files
config.JobType.pluginName = 'Analysis'
config.JobType.psetName = '${PSET}'
config.JobType.outputFiles = ['${OUTPUT_FILE}']
config.JobType.maxMemoryMB = 4000
config.JobType.numCores = ${NTHREADS}
config.JobType.maxJobRuntimeMin = 360  # 6 hours (NANO step only)

# Data — one MiniAOD file per job
config.Data.userInputFiles = [
${PYLIST}
]
config.Data.splitting = 'FileBased'
config.Data.unitsPerJob = 1
config.Data.outputPrimaryDataset = '${SAMPLE_NAME}'
config.Data.outputDatasetTag = '${CAMPAIGN_TAG}'

# Site
config.Site.storageSite = '${SITE}'
config.Site.whitelist = ['${SITE}', 'T2_CH_CERN', 'T1_DE_KIT']
config.Data.outLFNDirBase = '${STORAGE_BASE}'
EOF

    echo "Created CRAB config: ${CRAB_CFG}"

    if $AUTO_SUBMIT; then
        echo "Submitting ${SAMPLE_NAME}..."
        crab submit "$CRAB_CFG"
    fi
    echo ""
done

echo "========================================"
echo "Done!"
echo "========================================"
if ! $AUTO_SUBMIT; then
    echo ""
    echo "To submit, either:"
    echo "  1) Re-run with --submit:  ./submit.sh --format ${FORMAT} --submit"
    echo "  2) Submit individually:"
    for entry in "${REPROCESS_POINTS[@]}"; do
        MASS="${entry%%:*}"
        MASS_STR=$(echo "$MASS" | sed 's/\./_/g')
        echo "     crab submit ${CRAB_PREFIX}_ggH_HZa_mA${MASS_STR}GeV.py"
    done
fi
