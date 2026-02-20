#!/bin/bash

# CRAB submission script for ggH -> H -> Za signal production
# Submits jobs for multiple pseudoscalar mass points

set -e

# Configuration
MASS_POINTS=(0.5 0.75 1.0 1.5 2.0 2.5 3.0 3.5 4.0 8.0)  # GeV
NEVENTS_PER_JOB=1000
NJOBS=100
SITE="T2_CH_CERN"
STORAGE_SITE="/store/user/$USER/ggH_HZa_signals"
CAMPAIGN="RunIII2024Summer24"
GRIDPACK="gg_H_quark-mass-effects_el9_amd64_gcc12_CMSSW_13_3_0_ggH_M125.tgz"
FRAGMENT="ggH_HZa_fragment.py"

# Check environment
if [ -z "$CMSSW_BASE" ]; then
    echo "ERROR: CMSSW environment not set up!"
    echo "Please run: source ../setup.sh"
    exit 1
fi

# Check for valid grid proxy
voms-proxy-info --exists --valid 12:00
if [ $? -ne 0 ]; then
    echo "ERROR: Valid grid proxy required!"
    echo "Please run: voms-proxy-init -rfc -voms cms -valid 192:00"
    exit 1
fi

echo "========================================"
echo "CRAB Submission for ggH -> H -> Za"
echo "========================================"
echo "Campaign: ${CAMPAIGN}"
echo "Mass points: ${MASS_POINTS[@]}"
echo "Events per job: ${NEVENTS_PER_JOB}"
echo "Number of jobs: ${NJOBS}"
echo "Site: ${SITE}"
echo "Storage: ${STORAGE_SITE}"
echo ""

# Create CRAB configuration directory if needed
CRAB_CFG_DIR="../crab_configs"
mkdir -p "$CRAB_CFG_DIR"

# Function to create CRAB config for a given mass point
create_crab_config() {
    local mass=$1
    local mass_str=$(echo $mass | sed 's/\./_/g')
    local sample_name="ggH_HZa_mA${mass_str}GeV"
    local cfg_file="${CRAB_CFG_DIR}/crab_${sample_name}.py"
    
    cat > "$cfg_file" << EOF
from CRABClient.UserUtilities import config
config = config()

# General settings
config.General.requestName = '${sample_name}_${CAMPAIGN}'
config.General.workArea = 'crab_projects_${CAMPAIGN}'
config.General.transferOutputs = True
config.General.transferLogs = True

# Job type settings
config.JobType.pluginName = 'PrivateMC'
config.JobType.psetName = 'pset_dummy.py'  # Dummy, not used with scriptExe
config.JobType.scriptExe = '../scripts/exe_crab.sh'
config.JobType.inputFiles = ['../fragments/${FRAGMENT}',
                              '../../01_gridpacks/${GRIDPACK}']
config.JobType.outputFiles = ['RunIII2024Summer24NanoAODv15_${sample_name}.root']
config.JobType.maxMemoryMB = 8000
config.JobType.numCores = 4
config.JobType.maxJobRuntimeMin = 1200  # 20 hours

# Script arguments (job index provided by CRAB via \$CRAB_Id env var)
config.JobType.scriptArgs = [
    'nEvents=${NEVENTS_PER_JOB}',
    'nThreads=4',
    'sampleName=${sample_name}',
    'beginSeed=1000',
    'massPoint=${mass}',
    'gridpack=${GRIDPACK}'
]

# Data settings
config.Data.outputPrimaryDataset = '${sample_name}'
config.Data.splitting = 'EventBased'
config.Data.unitsPerJob = ${NEVENTS_PER_JOB}
config.Data.totalUnits = $((NEVENTS_PER_JOB * NJOBS))
config.Data.publication = True
config.Data.outputDatasetTag = '${CAMPAIGN}'

# Site settings
config.Site.storageSite = '${SITE}'
config.Data.outLFNDirBase = '${STORAGE_SITE}/${CAMPAIGN}'
EOF

    echo "Created CRAB config: $cfg_file"
}

# Create a dummy pset in scripts/ dir (CRAB resolves psetName relative to CWD)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat > "${SCRIPT_DIR}/pset_dummy.py" << 'EOF'
import FWCore.ParameterSet.Config as cms
process = cms.Process('DUMMY')
process.source = cms.Source("EmptySource")
process.maxEvents = cms.untracked.PSet(input=cms.untracked.int32(1))
process.options = cms.untracked.PSet(numberOfThreads=cms.untracked.uint32(4))
EOF

# Generate CRAB configs for all mass points
echo "Generating CRAB configurations..."
for mass in "${MASS_POINTS[@]}"; do
    create_crab_config $mass
done

echo ""
echo "========================================"
echo "CRAB configs generated!"
echo "========================================"
echo ""
echo "To submit all jobs, run:"
echo "  for cfg in ${CRAB_CFG_DIR}/crab_ggH_*.py; do"
echo "    crab submit \$cfg"
echo "  done"
echo ""
echo "Or submit individually:"
for mass in "${MASS_POINTS[@]}"; do
    mass_str=$(echo $mass | sed 's/\./_/g')
    echo "  crab submit ${CRAB_CFG_DIR}/crab_ggH_HZa_mA${mass_str}GeV.py"
done
echo ""
echo "Monitor with:"
echo "  crab status -d crab_projects_${CAMPAIGN}/crab_*"
echo ""

# Ask if user wants to submit now
read -p "Submit all jobs now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Submitting jobs..."
    for mass in "${MASS_POINTS[@]}"; do
        mass_str=$(echo $mass | sed 's/\./_/g')
        sample_name="ggH_HZa_mA${mass_str}GeV"
        echo ""
        echo "Submitting: ${sample_name}"
        crab submit "${CRAB_CFG_DIR}/crab_${sample_name}.py"
    done
    echo ""
    echo "All jobs submitted!"
else
    echo "Submission cancelled. Use the commands above to submit manually."
fi
