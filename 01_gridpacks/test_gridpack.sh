#!/bin/bash

# Test POWHEG gridpack using CMS framework (cmsDriver)
# This is the proper way to test gridpacks - through the CMS event generation chain
# Usage: ./test_gridpack.sh [number_of_events]

set -e

NEVENTS=${1:-10}
GRIDPACK="/afs/cern.ch/work/p/pgadow/cms/analysis/hza/signals/01_gridpacks/CMSSW_13_3_0/src/genproductions/bin/Powheg/gg_H_quark-mass-effects_el9_amd64_gcc12_CMSSW_13_3_0_ggH_M125.tgz"

echo "========================================"
echo "POWHEG Gridpack Test via CMS Framework"
echo "========================================"
echo "Gridpack: $(basename $GRIDPACK)"
echo "Events to generate: $NEVENTS"
echo ""

# Check gridpack exists
if [ ! -f "$GRIDPACK" ]; then
    echo "✗ ERROR: Gridpack not found!"
    echo "Expected: $GRIDPACK"
    exit 1
fi
echo "✓ Gridpack found"

# Create test directory
TESTDIR="test_cms_$(date +%Y%m%d_%H%M%S)"
mkdir -p $TESTDIR
cd $TESTDIR
echo "✓ Test directory: $(pwd)"
echo ""

# Setup CMSSW environment
echo "Setting up CMSSW environment..."
export SCRAM_ARCH=el9_amd64_gcc12
source /cvmfs/cms.cern.ch/cmsset_default.sh

# Use existing CMSSW or create new one
CMSSW_BASE_DIR="/afs/cern.ch/work/p/pgadow/cms/analysis/hza/signals/01_gridpacks/CMSSW_13_3_0"
if [ -d "$CMSSW_BASE_DIR" ]; then
    cd $CMSSW_BASE_DIR/src
    eval $(scramv1 runtime -sh)
    echo "✓ Using existing CMSSW_13_3_0"
else
    cd ..
    scramv1 project CMSSW CMSSW_13_3_0
    cd CMSSW_13_3_0/src
    eval $(scramv1 runtime -sh)
    echo "✓ Created CMSSW_13_3_0"
fi

# Create generator fragment in CMSSW
mkdir -p Configuration/GenProduction/python
cd Configuration/GenProduction/python

echo ""
echo "Creating generator fragment..."
cat > test_ggH_fragment.py << 'EOF'
import FWCore.ParameterSet.Config as cms

externalLHEProducer = cms.EDProducer("ExternalLHEProducer",
    args = cms.vstring('__GRIDPACK__'),
    nEvents = cms.untracked.uint32(5000),
    numberOfParameters = cms.uint32(1),
    outputFile = cms.string('cmsgrid_final.lhe'),
    scriptName = cms.FileInPath('GeneratorInterface/LHEInterface/data/run_generic_tarball_cvmfs.sh')
)
EOF

# Update gridpack path in fragment
sed -i "s|__GRIDPACK__|$GRIDPACK|g" test_ggH_fragment.py
echo "✓ Fragment created at Configuration/GenProduction/python/test_ggH_fragment.py"

# Build CMSSW to register the fragment
scram b -j 4
eval $(scramv1 runtime -sh)
echo "✓ CMSSW built"

# Go back to test directory
WORK_DIR="/afs/cern.ch/work/p/pgadow/cms/analysis/hza/signals/01_gridpacks/$TESTDIR"
cd $WORK_DIR
echo ""

# Run cmsDriver to generate LHE events
echo "Running cmsDriver (LHE generation)..."
echo "This will unpack the gridpack and generate $NEVENTS events"
echo "With pre-computed grids, this should take ~1-2 minutes"
echo "----------------------------------------"

cmsDriver.py Configuration/GenProduction/python/test_ggH_fragment.py \
    --python_filename test_lhe_cfg.py \
    --eventcontent LHE \
    --datatier LHE \
    --fileout file:test_output.root \
    --conditions auto:mc \
    --step LHE \
    --no_exec \
    --mc \
    -n $NEVENTS || { echo "✗ cmsDriver failed"; exit 1; }

echo ""
echo "✓ Configuration created"
echo "Running LHE generation..."
cmsRun test_lhe_cfg.py 2>&1 | tee cmsRun.log

echo "----------------------------------------"
echo ""

# Check output
echo "========================================"
echo "Results"
echo "========================================"

# Check for LHE file in the output
if [ -f "cmsgrid_final.lhe" ]; then
    NEVENTS_GENERATED=$(grep -c "<event>" cmsgrid_final.lhe || echo 0)
    if [ $NEVENTS_GENERATED -gt 0 ]; then
        echo "✓ SUCCESS! Generated $NEVENTS_GENERATED events"
        echo ""
        echo "Output files:"
        ls -lh cmsgrid_final.lhe test_output.root 2>/dev/null
        echo ""
        echo "First event preview:"
        echo "--------------------"
        awk '/<event>/,/<\/event>/ {print; if (/<\/event>/) exit}' cmsgrid_final.lhe | head -15
        echo ""
        echo "✓ Gridpack is working correctly!"
        echo ""
        echo "Test directory: $(pwd)"
    else
        echo "✗ ERROR: LHE file created but contains no events"
        exit 1
    fi
else
    echo "✗ ERROR: No LHE file generated"
    echo "Check cmsRun.log for details"
    exit 1
fi

echo "========================================"
