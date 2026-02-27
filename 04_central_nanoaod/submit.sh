#!/bin/bash

# Submit btvNanoAllPF reprocessing jobs via CRAB
# Reads centrally-produced MiniAOD datasets and produces BTV NanoAOD with all
# PF candidates.  Supports both MC (MINIAODSIM) and data (MINIAOD).
#
# Usage:
#   ./submit.sh                           # dry run — MC datasets
#   ./submit.sh --data                    # dry run — data datasets
#   ./submit.sh --submit                  # generate configs and submit MC
#   ./submit.sh --data --submit           # generate configs and submit data
#   ./submit.sh --dataset-file custom.txt # use a custom dataset list

set -e

# ─── Configuration ────────────────────────────────────────────────────────────
NTHREADS=4

# MC settings
GT_MC="150X_mcRun3_2024_realistic_v2"
CAMPAIGN_TAG_MC="RunIII2024Summer24BTVNanoAllPF"
PSET_MC="btvnano_mc_cfg.py"

# Data settings
GT_DATA="150X_dataRun3_v2"
CAMPAIGN_TAG_DATA="Run2024BTVNanoAllPF"
PSET_DATA="btvnano_data_cfg.py"
LUMI_MASK="/eos/user/c/cmsdqm/www/CAF/certification/Collisions24/Cert_Collisions2024_378981_386951_Golden.json"

# Common settings
SITE="T2_DE_DESY"
OUTPUT_FILE="btvnano_output.root"
FILES_PER_JOB=5        # MiniAOD files per CRAB job (MC, FileBased)
LUMIS_PER_JOB=50        # Lumisections per CRAB job (data, LumiBased)
MAX_RUNTIME=600         # minutes (10 hours)
MAX_MEMORY=4000         # MB
# ──────────────────────────────────────────────────────────────────────────────

# ─── Strip rucio from PATH (avoids harmless traceback) ───────────────────────
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v rucio | tr '\n' ':' | sed 's/:$//')

# ─── Parse arguments ─────────────────────────────────────────────────────────
DATASET_FILE=""
AUTO_SUBMIT=false
MODE=""  # "mc" or "data", auto-detected if not set

while [[ $# -gt 0 ]]; do
    case "$1" in
        --submit)
            AUTO_SUBMIT=true
            shift
            ;;
        --data)
            MODE="data"
            shift
            ;;
        --mc)
            MODE="mc"
            shift
            ;;
        --dataset-file)
            DATASET_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: ./submit.sh [--mc|--data] [--submit] [--dataset-file FILE]"
            echo ""
            echo "Options:"
            echo "  --mc                  Process MC datasets (default)"
            echo "  --data                Process data datasets"
            echo "  --submit              Submit CRAB jobs (default: dry run only)"
            echo "  --dataset-file FILE   Path to dataset list (overrides default)"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: ./submit.sh [--mc|--data] [--submit] [--dataset-file FILE]"
            exit 1
            ;;
    esac
done

# Default mode
if [ -z "$MODE" ]; then
    MODE="mc"
fi

# Default dataset file based on mode
if [ -z "$DATASET_FILE" ]; then
    if [ "$MODE" == "data" ]; then
        DATASET_FILE="datasets_data.txt"
    else
        DATASET_FILE="datasets_mc.txt"
    fi
fi

# Set mode-dependent variables
if [ "$MODE" == "data" ]; then
    GT="$GT_DATA"
    CAMPAIGN_TAG="$CAMPAIGN_TAG_DATA"
    PSET_NAME="$PSET_DATA"
    STORAGE_BASE="/store/user/$USER/HZa_data/${CAMPAIGN_TAG}"
    SPLITTING="LumiBased"
    UNITS_PER_JOB=$LUMIS_PER_JOB
else
    GT="$GT_MC"
    CAMPAIGN_TAG="$CAMPAIGN_TAG_MC"
    PSET_NAME="$PSET_MC"
    STORAGE_BASE="/store/user/$USER/HZa_backgrounds/${CAMPAIGN_TAG}"
    SPLITTING="FileBased"
    UNITS_PER_JOB=$FILES_PER_JOB
fi

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

if ! voms-proxy-info --exists --valid 12:00 2>/dev/null; then
    echo "ERROR: Valid grid proxy required!"
    echo "Please run: voms-proxy-init -rfc -voms cms -valid 192:00"
    exit 1
fi

# ─── Lumi mask check (data only) ─────────────────────────────────────────────
if [ "$MODE" == "data" ]; then
    if [ ! -f "$LUMI_MASK" ]; then
        echo "WARNING: Golden JSON not found at: $LUMI_MASK"
        echo "  Data jobs will run without a lumi mask!"
        echo "  Press Ctrl-C to abort, or wait 5 seconds to continue..."
        sleep 5
    fi
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
echo "btvNanoAllPF Reprocessing — ${MODE^^}"
echo "========================================"
echo "Mode:    ${MODE}"
echo "CMSSW:   $(basename $CMSSW_BASE)"
echo "GT:      ${GT}"
echo "Site:    ${SITE}"
echo "Storage: ${STORAGE_BASE}"
echo "PSet:    ${PSET_NAME}"
echo "Datasets: ${DATASET_FILE}"
if [ "$MODE" == "data" ]; then
    echo "Splitting: ${SPLITTING} (${UNITS_PER_JOB} lumi sections/job)"
    echo "Lumi mask: ${LUMI_MASK}"
else
    echo "Splitting: ${SPLITTING} (${UNITS_PER_JOB} files/job)"
fi
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

    # Extract the primary dataset name and era/campaign
    PRIMARY=$(echo "$MINI_DATASET" | cut -d'/' -f2)
    ERA_CAMPAIGN=$(echo "$MINI_DATASET" | cut -d'/' -f3)

    echo "----------------------------------------"
    echo "[$N_TOTAL] $PRIMARY — $ERA_CAMPAIGN"
    echo "  Input: $MINI_DATASET"

    # Verify the dataset path looks valid
    if [[ "$MINI_DATASET" != /* ]]; then
        echo "  WARNING: Does not look like a valid dataset path — skipping!"
        N_FAIL=$((N_FAIL + 1))
        continue
    fi

    # Check MC vs data consistency
    if [ "$MODE" == "data" ] && [[ "$MINI_DATASET" == */MINIAODSIM ]]; then
        echo "  WARNING: Looks like MC (MINIAODSIM) but running in --data mode — skipping!"
        N_FAIL=$((N_FAIL + 1))
        continue
    fi
    if [ "$MODE" == "mc" ] && [[ "$MINI_DATASET" != */MINIAODSIM ]]; then
        echo "  WARNING: Looks like data (MINIAOD) but running in --mc mode — skipping!"
        N_FAIL=$((N_FAIL + 1))
        continue
    fi

    # Build a clean request name (CRAB limit: 100 chars)
    REQUEST_NAME=$(echo "${PRIMARY}_${ERA_CAMPAIGN}" | sed 's/[^a-zA-Z0-9_-]/_/g' | cut -c1-100)

    # Create CRAB config
    CRAB_CFG="${CRAB_DIR}/crab_${PRIMARY}_$(echo ${ERA_CAMPAIGN} | sed 's/[^a-zA-Z0-9_-]/_/g').py"

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

# Data
config.Data.inputDataset = '${MINI_DATASET}'
config.Data.inputDBS = 'global'
config.Data.splitting = '${SPLITTING}'
config.Data.unitsPerJob = ${UNITS_PER_JOB}
config.Data.outputDatasetTag = '${CAMPAIGN_TAG}'
config.Data.publication = False
EOF

    # Add lumi mask for data
    if [ "$MODE" == "data" ] && [ -f "$LUMI_MASK" ]; then
        cat >> "$CRAB_CFG" << EOF
config.Data.lumiMask = '${LUMI_MASK}'
EOF
    fi

    cat >> "$CRAB_CFG" << EOF

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
echo "  Mode: ${MODE}"
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
    echo "  ./submit.sh $([ "$MODE" == 'data' ] && echo '--data ')--submit"
    echo ""
    echo "To submit individually:"
    echo "  crab submit ${CRAB_DIR}/crab_<dataset>.py"
fi
