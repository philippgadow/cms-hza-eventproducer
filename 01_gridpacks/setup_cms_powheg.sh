#!/bin/bash
#######################################################################
# Setup script for CMS POWHEG gridpack generation using genproductions
# Following official CMS workflow
#######################################################################

# Save original directory
ORIG_DIR=$(pwd)

# Configuration - modify as needed
# For Run 3 (NanoAODv15, MiniAODv6): Use CMSSW_13_X with el9 (native on lxplus9)
CMSSW_VERSION="CMSSW_13_3_0"
SCRAM_ARCH="el9_amd64_gcc12"
PROCESS_NAME="gg_H_quark-mass-effects"  # Official POWHEG-BOX process name
PREFERRED_NAME="ggH_M125"               # Your preferred working folder name
INPUT_CARD="powheg.input"

echo "=========================================="
echo "CMS POWHEG Setup for ggH Production"
echo "=========================================="
echo "CMSSW: ${CMSSW_VERSION}"
echo "Architecture: ${SCRAM_ARCH}"
echo "Process: ${PROCESS_NAME}"
echo "=========================================="

# Setup CMSSW environment
echo "Setting up CMSSW environment..."
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=${SCRAM_ARCH}

# Create CMSSW area if it doesn't exist
if [ ! -d "${CMSSW_VERSION}" ]; then
    echo "Creating CMSSW release..."
    scramv1 project CMSSW ${CMSSW_VERSION}
else
    echo "CMSSW release already exists"
fi

cd ${CMSSW_VERSION}/src
eval `scramv1 runtime -sh`

# Clone genproductions if not already present
if [ ! -d "genproductions" ]; then
    echo "Cloning genproductions repository..."
    git clone --depth=1 --single-branch https://github.com/cms-sw/genproductions.git
else
    echo "genproductions already cloned"
fi

cd genproductions/bin/Powheg

complete -r

# Copy input card to this directory
echo "Copying input card..."
cp ${ORIG_DIR}/${INPUT_CARD} .

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "You are now in: $(pwd)"
echo ""
echo "Next steps for gridpack generation:"
echo ""
echo "OPTION 1: Generate gridpack in one go (for simple processes)"
echo "-----------------------------------------------------------"
echo "python3 ./run_pwg_condor.py -p f -i ${INPUT_CARD} -m ${PROCESS_NAME} -f ${PREFERRED_NAME} -q longlunch -n 10000"
echo ""
echo "OPTION 2: Generate gridpack in steps (recommended for complex processes)"
echo "------------------------------------------------------------------------"
echo "# Step 1: Compile POWHEG (Stage 0)"
echo "python3 ./run_pwg_condor.py -p 0 -i ${INPUT_CARD} -m ${PROCESS_NAME} -f ${PREFERRED_NAME}"
echo ""
echo "# Step 2: Generate grids (Stages 1,2,3) - parallel mode"
echo "python3 ./run_pwg_parallel_condor.py -p 123 -i ${INPUT_CARD} -m ${PROCESS_NAME} -f ${PREFERRED_NAME} -q 1:longlunch,2:longlunch,3:tomorrow -j 10 -x 5"
echo ""
echo "# Step 3: Create gridpack tarball (Stage 9)"
echo "python3 ./run_pwg_condor.py -p 9 -i ${INPUT_CARD} -m ${PROCESS_NAME} -f ${PREFERRED_NAME}"
echo ""
echo "=========================================="
echo ""
echo "For local running (no batch), omit the -q option"
echo "For different Higgs masses, edit ${INPUT_CARD} and change the folder name (-f)"
echo ""
