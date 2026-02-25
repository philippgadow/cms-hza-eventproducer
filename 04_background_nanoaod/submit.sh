#!/bin/bash

# Submit btvNanoAllPF reprocessing jobs for background MC via CRAB
# Reads centrally-produced MiniAOD datasets listed in datasets.txt and
# produces BTV NanoAOD with all PF candidates.
#
# Usage:
#   ./submit.sh                   # dry run — generate configs only
#   ./submit.sh --submit          # generate configs and submit to CRAB
#   ./submit.sh --dataset-file custom.txt   # use a different dataset list

set -e

# ─── Configuration ────────────────────────────────────────────────────────────
NTHREADS=4
GT="150X_mcRun3_2024_realistic_v2"

CAMPAIGN_TAG="RunIII2024Summer24BTVNanoAllPF"
SITE="T2_DE_DESY"
STORAGE_BASE="/store/user/$USER/HZa_backgrounds/${CAMPAIGN_TAG}"

PSET_NAME="btvnano_cfg.py"
OUTPUT_FILE="btvnano_output.root"
FILES_PER_JOB=5        # MiniAOD files per CRAB job
MAX_RUNTIME=600         # minutes (10 hours)
MAX_MEMORY=4000         # MB
# ──────────────────────────────────────────────────────────────────────────────

# ─── Parse arguments ─────────────────────────────────────────────────────────
DATASET_FILE="datasets.txt"
AUTO_SUBMIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --submit)
            AUTO_SUBMIT=true
            shift
            ;;
        --dataset-file)
            DATASET_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: ./submit.sh [--submit] [--dataset-file FILE]"
            echo ""
            echo "Options:"
            echo "  --submit              Submit CRAB jobs (default: dry run only)"
            echo "  --dataset-file FILE   Path to dataset list (default: datasets.txt)"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: ./submit.sh [--submit] [--dataset-file FILE]"
            exit 1
            ;;
    esac
done

# ─── Sanity checks ───────────────────────────────────────────────────────────
if [ -z "$CMSSW_BASE" ]; then
    echo "ERROR: CMSSW environment not set up!"
    echo "Please run first:  source setup.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSET="${SCRIPT_DIR}/${PSET_NAME}"

if [ ! -f "$PSET" ]; then
    echo "ERROR: PSet not found: $PSET"
    echo "Please run first:  source setup.sh"
    exit 1
fi

if [ ! -f "$DATASET_FILE" ]; then
    echo "ERROR: Dataset file not found: $DATASET_FILE"
    exit 1
fi

voms-proxy-info --exists --valid 12:00
if [ $? -ne 0 ]; then
    echo "ERROR: Valid grid proxy required!"
    echo "Please run: voms-proxy-init -rfc -voms cms -valid 192:00"
    exit 1
fi

echo ""
echo "    (\/)  (\/)   "
echo "    ( o    o)    Mr. CRABs says:"
echo "     \\    //     \"Money money money!\""
echo "      \\  //      \"Submit those jobs!\""
echo "    ===\\//===    "
echo "   /  /    \\  \\  "
echo "  /  / \\  / \\  \\ "
echo "     /  \\/  \\    "
echo ""
echo "========================================"
echo "Background btvNanoAllPF Reprocessing"
echo "========================================"
echo "CMSSW:   $(basename $CMSSW_BASE)"
echo "GT:      ${GT}"
echo "Site:    ${SITE}"
echo "Storage: ${STORAGE_BASE}"
echo "PSet:    ${PSET}"
echo "Datasets: ${DATASET_FILE}"
echo ""

# ─── Create output directory for CRAB configs ────────────────────────────────
CRAB_DIR="${SCRIPT_DIR}/crab_configs"
mkdir -p "$CRAB_DIR"

# ─── Process each dataset ────────────────────────────────────────────────────
N_TOTAL=0
N_OK=0
N_FAIL=0

while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    line=$(echo "$line" | sed 's/#.*//' | xargs)
    [ -z "$line" ] && continue

    MINI_DATASET="$line"
    N_TOTAL=$((N_TOTAL + 1))

    # Extract the primary dataset name (first field between slashes)
    PRIMARY=$(echo "$MINI_DATASET" | cut -d'/' -f2)

    echo "----------------------------------------"
    echo "[$N_TOTAL] $PRIMARY"
    echo "  MiniAOD: $MINI_DATASET"

    # Verify the dataset path looks valid
    if [[ "$MINI_DATASET" != /* ]] || [[ "$MINI_DATASET" != */MINIAODSIM ]]; then
        echo "  WARNING: Does not look like a valid MiniAOD path — skipping!"
        N_FAIL=$((N_FAIL + 1))
        continue
    fi

    # Build a clean request name from the primary dataset name
    # Truncate to 100 chars (CRAB limit) and remove problematic characters
    REQUEST_NAME=$(echo "${PRIMARY}" | sed 's/[^a-zA-Z0-9_-]/_/g' | cut -c1-100)
    REQUEST_NAME="${REQUEST_NAME}_${CAMPAIGN_TAG}"
    # CRAB request names max 100 chars
    REQUEST_NAME=$(echo "$REQUEST_NAME" | cut -c1-100)

    # Create CRAB config
    CRAB_CFG="${CRAB_DIR}/crab_${PRIMARY}.py"
    cat > "$CRAB_CFG" << EOF
from CRABClient.UserUtilities import config
config = config()

# General
config.General.requestName = '${REQUEST_NAME}'
config.General.workArea = 'crab_projects_${CAMPAIGN_TAG}'
config.General.transferOutputs = True
config.General.transferLogs = True

# Job type — Analysis plugin reads MiniAOD, produces btvNanoAllPF
config.JobType.pluginName = 'Analysis'
config.JobType.psetName = '${PSET}'
config.JobType.outputFiles = ['${OUTPUT_FILE}']
config.JobType.maxMemoryMB = ${MAX_MEMORY}
config.JobType.numCores = ${NTHREADS}
config.JobType.maxJobRuntimeMin = ${MAX_RUNTIME}

# Data — centrally produced MiniAOD from DBS
config.Data.inputDataset = '${MINI_DATASET}'
config.Data.inputDBS = 'global'
config.Data.splitting = 'FileBased'
config.Data.unitsPerJob = ${FILES_PER_JOB}
config.Data.outputDatasetTag = '${CAMPAIGN_TAG}'
config.Data.publication = False

# Site
config.Site.storageSite = '${SITE}'
config.Data.outLFNDirBase = '${STORAGE_BASE}'
EOF

    echo "  Config:  ${CRAB_CFG}"
    N_OK=$((N_OK + 1))

    if $AUTO_SUBMIT; then
        echo "  Submitting..."
        crab submit "$CRAB_CFG"
    fi
    echo ""

done < "$DATASET_FILE"

echo "========================================"
echo "Summary: ${N_OK}/${N_TOTAL} configs created, ${N_FAIL} failed"
echo "========================================"

if [ $N_FAIL -eq 0 ]; then
    echo "  🦀 Mr. CRABs: \"I like money! All ${N_OK} datasets ready!\""
else
    echo "  🦀 Mr. CRABs: \"You're spending all me money! ${N_FAIL} failed!\""
fi
echo ""

if ! $AUTO_SUBMIT; then
    echo ""
    echo "Configs written to: ${CRAB_DIR}/"
    echo ""
    echo "To submit all jobs:"
    echo "  ./submit.sh --submit"
    echo ""
    echo "To submit individually:"
    echo "  crab submit ${CRAB_DIR}/crab_<dataset>.py"
fi
