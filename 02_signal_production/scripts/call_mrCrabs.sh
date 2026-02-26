#!/bin/bash

# Check CRAB job status using mrCrabs
# Usage:
#   ./call_mrCrabs.sh                   # check all jobs
#   ./call_mrCrabs.sh --resubmit        # check and resubmit failed jobs

set -e

if [ -z "$CMSSW_BASE" ]; then
    echo "ERROR: CMSSW environment not set up!"
    echo "Please run first:  source setup.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MRCRABS="${REPO_DIR}/mrCrabs/mrCrabs.py"

# ─── Ensure mrCrabs submodule is available ────────────────────────────────────
if [ ! -f "$MRCRABS" ]; then
    echo "mrCrabs not found — initialising git submodule..."
    (cd "$REPO_DIR" && git submodule update --init mrCrabs)
    if [ ! -f "$MRCRABS" ]; then
        echo "ERROR: Failed to initialise mrCrabs submodule."
        exit 1
    fi
    echo ""
fi

# ─── Parse arguments ─────────────────────────────────────────────────────────
RESUBMIT=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resubmit)
            RESUBMIT="--resubmit"
            shift
            ;;
        -h|--help)
            echo "Usage: ./call_mrCrabs.sh [--resubmit] [-a CRAB_OPTION]"
            echo ""
            echo "Options:"
            echo "  --resubmit    Automatically resubmit failed jobs"
            echo "  -a OPTION     Pass additional crab options (e.g. -a '--maxjobruntime=2750')"
            exit 0
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# ─── Run mrCrabs ─────────────────────────────────────────────────────────────
echo ""
echo "   (\/)_(\/)  "
echo "   (=  o  o=)   🦀 Mr. CRABs is checking your jobs..."
echo "   (  >    < )  "
echo "    ---\"\"---   "
echo ""
python3 "$MRCRABS" $RESUBMIT "${EXTRA_ARGS[@]}" crab_projects_*/crab_*
