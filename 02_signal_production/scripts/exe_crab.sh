#!/bin/bash -x

# CRAB execution script for ggH -> H -> Za production
# Adapted from cms-vbf-hcc-eventproducer for BSM signal generation

JOBINDEX=${1##*=}     # hard coded by crab
NEVENTS=${2##*=}      # ordered by crab.py script
NTHREAD=${3##*=}      # ordered by crab.py script
NAME=${4##*=}         # ordered by crab.py script (e.g., ggH_HZa_mA1p0GeV)
BEGINSEED=${5##*=}
MASS_POINT=${6##*=}   # pseudoscalar mass in GeVGRIDPACK=${7##*=}     # gridpack tarball filename
LUMISTART=$((${BEGINSEED} + ${JOBINDEX}))
EVENTSTART=$(((${BEGINSEED} + ${JOBINDEX}) * NEVENTS))
SEED=$((((${BEGINSEED} + ${JOBINDEX})) * NTHREAD * 4 + 1001))

WORKDIR=$(pwd)

echo "========================================"
echo "ggH -> H -> Za Signal Production"
echo "========================================"
echo "Job index: ${JOBINDEX}"
echo "Events: ${NEVENTS}"
echo "Threads: ${NTHREAD}"
echo "Sample: ${NAME}"
echo "Pseudoscalar mass: ${MASS_POINT} GeV"
echo "Seed: ${SEED}"
echo ""

############ LHE+GEN+SIM ############
export SCRAM_ARCH=el9_amd64_gcc12
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=CMSSW_14_0_19

if [ -r $RELEASE/src ]; then
  echo "Release $RELEASE already exists"
else
  scram p CMSSW $RELEASE
fi

cd $RELEASE/src
eval $(scram runtime -sh)

# Copy the fragment (CRAB transfers inputFiles flat to $WORKDIR)
mkdir -pv $CMSSW_BASE/src/Configuration/GenProduction/python
cp $WORKDIR/ggH_HZa_fragment.py $CMSSW_BASE/src/Configuration/GenProduction/python/${NAME}.py

# Replace placeholders in the fragment
GRIDPACK_PATH="$WORKDIR/$GRIDPACK"
MASS_MAX=$(python3 -c "print(max(2.0, 2.0 * ${MASS_POINT}))")
sed -i "s|__GRIDPACK__|${GRIDPACK_PATH}|g" $CMSSW_BASE/src/Configuration/GenProduction/python/${NAME}.py
sed -i "s|__MASS__|${MASS_POINT}|g"         $CMSSW_BASE/src/Configuration/GenProduction/python/${NAME}.py
sed -i "s|__MASSMAX__|${MASS_MAX}|g"        $CMSSW_BASE/src/Configuration/GenProduction/python/${NAME}.py

if [ ! -f "$CMSSW_BASE/src/Configuration/GenProduction/python/${NAME}.py" ]; then
  echo "Fragment copy failed"
  exit 1
fi

scram b -j $NTHREAD
eval $(scram runtime -sh)

cd $WORKDIR

echo ""
echo "Running cmsDriver for LHE+GEN+SIM step..."
echo ""

# Run the generation chain
cmsDriver.py Configuration/GenProduction/python/${NAME}.py \
  --python_filename "RunIII2024Summer24wmLHEGS_${NAME}_cfg.py" \
  --eventcontent RAWSIM,LHE \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier GEN-SIM,LHE \
  --fileout "file:RunIII2024Summer24wmLHEGS_${NAME}_${JOBINDEX}.root" \
  --conditions 140X_mcRun3_2024_realistic_v26 \
  --beamspot DBrealistic \
  --step LHE,GEN,SIM \
  --geometry DB:Extended \
  --era Run3_2024 \
  --nThreads $NTHREAD \
  --customise_commands "process.source.numberEventsInLuminosityBlock=cms.untracked.uint32(1000)\\nprocess.source.firstLuminosityBlock=cms.untracked.uint32(${LUMISTART})\\nprocess.source.firstEvent=cms.untracked.uint64(${EVENTSTART})\\nprocess.RandomNumberGeneratorService.externalLHEProducer.initialSeed=${SEED}" \
  --mc \
  -n $NEVENTS || exit $?

ls -lh *.root

############ DIGIPremix ############
export SCRAM_ARCH=el9_amd64_gcc12
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=CMSSW_14_0_21

if [ -r $RELEASE/src ]; then
  echo "Release $RELEASE already exists"
else
  scram p CMSSW $RELEASE
fi

cd $RELEASE/src
eval $(scram runtime -sh)
cd $WORKDIR

echo ""
echo "Running cmsDriver for DIGIPremix step..."
echo ""

cmsDriver.py \
  --python_filename "RunIII2024Summer24DRPremix_${NAME}_cfg.py" \
  --eventcontent PREMIXRAW \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier GEN-SIM-RAW \
  --filein "file:RunIII2024Summer24wmLHEGS_${NAME}_${JOBINDEX}.root" \
  --fileout "file:RunIII2024Summer24DRPremix_${NAME}_${JOBINDEX}.root" \
  --pileup_input "dbs:/Neutrino_E-10_gun/RunIIISummer24PrePremix-Premixlib2024_140X_mcRun3_2024_realistic_v26-v1/PREMIX" \
  --conditions 140X_mcRun3_2024_realistic_v26 \
  --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:2024v14 \
  --procModifiers premix_stage2 \
  --geometry DB:Extended \
  --datamix PreMix \
  --era Run3_2024 \
  --runUnscheduled \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

ls -lh *.root

############ RECO (AOD) ############
export SCRAM_ARCH=el9_amd64_gcc12
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=CMSSW_14_0_21

cd $RELEASE/src
eval $(scram runtime -sh)
cd $WORKDIR

echo ""
echo "Running cmsDriver for RECO step..."
echo ""

cmsDriver.py \
  --python_filename "RunIII2024Summer24RECO_${NAME}_cfg.py" \
  --eventcontent AODSIM \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier AODSIM \
  --filein "file:RunIII2024Summer24DRPremix_${NAME}_${JOBINDEX}.root" \
  --fileout "file:RunIII2024Summer24RECO_${NAME}_${JOBINDEX}.root" \
  --conditions 140X_mcRun3_2024_realistic_v26 \
  --step RAW2DIGI,L1Reco,RECO,RECOSIM \
  --geometry DB:Extended \
  --era Run3_2024 \
  --runUnscheduled \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

ls -lh *.root

############ MiniAOD + NanoAOD ############
export SCRAM_ARCH=el9_amd64_gcc12
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=CMSSW_15_0_2

if [ -r $RELEASE/src ]; then
  echo "Release $RELEASE already exists"
else
  scram p CMSSW $RELEASE
fi

cd $RELEASE/src
eval $(scram runtime -sh)
cd $WORKDIR

echo ""
echo "Running cmsDriver for MiniAODv6 step..."
echo ""

cmsDriver.py \
  --python_filename "RunIII2024Summer24MiniAODv6_${NAME}_cfg.py" \
  --eventcontent MINIAODSIM \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier MINIAODSIM \
  --filein "file:RunIII2024Summer24RECO_${NAME}_${JOBINDEX}.root" \
  --fileout "file:RunIII2024Summer24MiniAODv6_${NAME}_${JOBINDEX}.root" \
  --conditions 150X_mcRun3_2024_realistic_v2 \
  --step PAT \
  --geometry DB:Extended \
  --era Run3_2024,run3_miniAOD_MesonGamma \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

echo ""
echo "Running cmsDriver for NanoAODv15 step..."
echo ""

cmsDriver.py \
  --python_filename "RunIII2024Summer24NanoAODv15_${NAME}_cfg.py" \
  --eventcontent NANOAODSIM \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier NANOAODSIM \
  --filein "file:RunIII2024Summer24MiniAODv6_${NAME}_${JOBINDEX}.root" \
  --fileout "file:RunIII2024Summer24NanoAODv15_${NAME}_${JOBINDEX}.root" \
  --conditions 150X_mcRun3_2024_realistic_v2 \
  --step NANO \
  --geometry DB:Extended \
  --era Run3_2024,run3_nanoAOD_164 \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

ls -lh *.root

# Clean up intermediate files to save transfer bandwidth
rm -f RunIII2024Summer24wmLHEGS_${NAME}_${JOBINDEX}.root
rm -f RunIII2024Summer24DRPremix_${NAME}_${JOBINDEX}.root
rm -f RunIII2024Summer24RECO_${NAME}_${JOBINDEX}.root
rm -f RunIII2024Summer24MiniAODv6_${NAME}_${JOBINDEX}.root

echo ""
echo "========================================"
echo "Production completed successfully!"
echo "========================================"
echo "Output file:"
ls -lh RunIII2024Summer24NanoAODv15_${NAME}_${JOBINDEX}.root
