#!/bin/bash
#
# Local test script for ggH -> H -> Za signal generation
# Tests the full chain: gridpack -> LHE -> GEN -> SIM
#

set -e  # Exit on error

# Configuration
MASS_POINT=1.0  # GeV (pseudoscalar mass)
NEVENTS=10      # Small number for quick test
NTHREADS=4
GRIDPACK_PATH="../../01_gridpacks/gg_H_quark-mass-effects_el9_amd64_gcc12_CMSSW_13_3_0_ggH_M125.tgz"
CMSSW_VERSION="CMSSW_14_0_19"

echo "========================================"
echo "Testing ggH -> H -> Za Signal Generation"
echo "========================================"
echo "Mass point: m_a = ${MASS_POINT} GeV"
echo "Events: ${NEVENTS}"
echo "Threads: ${NTHREADS}"
echo ""
echo "Using gridpack with pre-computed grids - should be fast!"
echo ""

# Check if we're in CMSSW environment
if [ -z "$CMSSW_BASE" ]; then
    echo "ERROR: CMSSW environment not set up!"
    echo "Please run: source ../setup.sh"
    exit 1
fi

# Check gridpack exists
if [ ! -f "$GRIDPACK_PATH" ]; then
    echo "ERROR: Gridpack not found at: $GRIDPACK_PATH"
    echo "Please check the gridpack location"
    exit 1
fi

# Get absolute paths BEFORE changing directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENT_PATH="$SCRIPT_DIR/../fragments/ggH_HZa_fragment.py"
GRIDPACK_ABS=$(cd "$(dirname "$GRIDPACK_PATH")" && pwd)/$(basename "$GRIDPACK_PATH")

# Create test output directory
TEST_DIR="test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Working directory: $(pwd)"
echo "Gridpack: $GRIDPACK_ABS"
echo ""

# Copy fragment to CMSSW
MASS_STR=$(echo $MASS_POINT | sed 's/\./_/g')
FRAGMENT_NAME="ggH_HZa_mA${MASS_STR}GeV"

echo "Step 1: Preparing fragment..."
mkdir -p $CMSSW_BASE/src/Configuration/GenProduction/python

cp "$FRAGMENT_PATH" \
   $CMSSW_BASE/src/Configuration/GenProduction/python/${FRAGMENT_NAME}.py

# Update gridpack path and pseudoscalar mass in fragment
sed -i "s|__GRIDPACK__|${GRIDPACK_ABS}|g" \
    $CMSSW_BASE/src/Configuration/GenProduction/python/${FRAGMENT_NAME}.py
sed -i "s|__MASS__|${MASS_POINT}|g" \
    $CMSSW_BASE/src/Configuration/GenProduction/python/${FRAGMENT_NAME}.py

cd $CMSSW_BASE/src
eval $(scram runtime -sh)
scram b -j ${NTHREADS}
cd -

echo ""
echo "Step 2: Running cmsDriver for LHE+GEN+SIM..."
echo ""

cmsDriver.py Configuration/GenProduction/python/${FRAGMENT_NAME}.py \
    --python_filename "test_ggH_HZa_mA${MASS_STR}GeV_cfg.py" \
    --eventcontent RAWSIM,LHE \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier GEN-SIM,LHE \
    --fileout "file:ggH_HZa_mA${MASS_STR}GeV_GEN-SIM.root" \
    --conditions 140X_mcRun3_2024_realistic_v26 \
    --beamspot DBrealistic \
    --step LHE,GEN,SIM \
    --geometry DB:Extended \
    --era Run3_2024 \
    --nThreads ${NTHREADS} \
    --customise_commands "process.source.numberEventsInLuminosityBlock=cms.untracked.uint32(100)" \
    --mc \
    -n ${NEVENTS} || exit $?

echo ""
echo "========================================"
echo "Test completed successfully!"
echo "========================================"
echo "Output file: ggH_HZa_mA${MASS_STR}GeV_GEN-SIM.root"
echo "Location: $(pwd)"
echo ""
echo "To inspect the output:"
echo "  edmDumpEventContent ggH_HZa_mA${MASS_STR}GeV_GEN-SIM.root"
echo ""
echo "To analyze decays:"
echo "  python3 << EOF"
echo "import uproot"
echo "import awkward as ak"
echo "events = uproot.open('ggH_HZa_mA${MASS_STR}GeV_GEN-SIM.root:Events')"
echo "genParticles = events.arrays(['recoGenParticles_genParticles__SIM.*'])"
echo "print(genParticles)"
echo "EOF"
