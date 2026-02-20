#!/bin/bash

# Setup script for ggH -> H -> Za signal production in CMS
# Combines POWHEG gridpack with Pythia8 for BSM Higgs decay

source /cvmfs/cms.cern.ch/cmsset_default.sh

# Check if we need el9 container
OS_VERSION=$(cat /etc/os-release | grep VERSION_ID | cut -d'"' -f2 | cut -d'.' -f1)

# Check if we're inside the singularity container OR running on el9 natively
if [ -z "$SINGULARITY_NAME" ] && [ ! -d "/.singularity.d" ] && [ "$OS_VERSION" != "9" ]; then
  echo "============================================"
  echo "Detected OS version: el${OS_VERSION}"
  echo "Starting el9 singularity container..."
  echo "After entering, please source this script again:"
  echo "  source setup.sh"
  echo "============================================"
  cmssw-el9  # Use el9 to match gridpack architecture
  return 0 2>/dev/null || exit 0
fi

if [ "$OS_VERSION" == "9" ]; then
  echo "Running on native el9 - no container needed"
fi

echo "============================================"
echo "Setting up ggH -> Za signal production"
echo "============================================"

# Set the CMSSW release (must support el9_amd64_gcc12)
export CMSSW_VERSION=CMSSW_14_0_19
export SCRAM_ARCH=el9_amd64_gcc12

if [ -r ${CMSSW_VERSION}/src ]; then
  echo "CMSSW ${CMSSW_VERSION} already exists"
else
  echo "Creating CMSSW ${CMSSW_VERSION}..."
  cmsrel ${CMSSW_VERSION}
fi

cd ${CMSSW_VERSION}/src
cmsenv

echo ""
echo "CMSSW environment set up successfully!"
echo "SCRAM_ARCH: $SCRAM_ARCH"
echo "CMSSW_BASE: $CMSSW_BASE"
echo ""

# Create necessary directories in CMSSW
mkdir -p Configuration/GenProduction/python

# Setup grid proxy for CRAB
echo "============================================"
echo "Setting up grid proxy..."
echo "============================================"

# only on DESY 
if [ -r /cvmfs/grid.desy.de/etc/profile.d/grid-ui-env.sh ]; then
    echo "Sourcing DESY grid environment"
    source /cvmfs/grid.desy.de/etc/profile.d/grid-ui-env.sh
fi

# Setup CRAB
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
echo "1. For local testing:"
echo "   cd ../../scripts && ./test_local.sh"
echo ""
echo "2. For CRAB submission:"
echo "   cd ../../scripts && ./submit_crab.sh"
echo ""
echo "Gridpack location:"
echo "  ../01_gridpacks/gg_H_quark-mass-effects_el9_amd64_gcc12_CMSSW_13_3_0_ggH_M125.tgz"
echo ""
