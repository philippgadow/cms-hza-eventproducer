#!/bin/bash -x

# CRAB execution script for ggH -> H -> Za production

# ─── Campaign configuration ──────────────────
ARCH="el9_amd64_gcc12"

RELEASE_GS="CMSSW_14_0_19"          # LHE + GEN + SIM
RELEASE_DR="CMSSW_14_0_21"          # DIGI + HLT + RECO
RELEASE_MINI="CMSSW_15_0_2"         # MiniAOD + NanoAOD
RELEASE_BTVNANO="CMSSW_15_0_18"     # BTV NanoAOD (allPF)

GT_GS="140X_mcRun3_2024_realistic_v26"
GT_DR="140X_mcRun3_2024_realistic_v26"
GT_MINI="150X_mcRun3_2024_realistic_v2"

ERA="Run3_2024"
HLT_MENU="2024v14"
PREMIX_DATASET="/Neutrino_E-10_gun/RunIIISummer24PrePremix-Premixlib2024_140X_mcRun3_2024_realistic_v26-v1/PREMIX"

CAMPAIGN_GS="RunIII2024Summer24wmLHEGS"
CAMPAIGN_DR="RunIII2024Summer24DRPremix"
CAMPAIGN_RECO="RunIII2024Summer24RECO"
CAMPAIGN_MINI="RunIII2024Summer24MiniAODv6"
CAMPAIGN_NANO="RunIII2024Summer24NanoAODv15"
CAMPAIGN_BTVNANO="RunIII2024Summer24BTVNanoAllPF"
# ─────────────────────────────────────────────────────────────────────────────

JOBINDEX=${CRAB_Id:-0}  # provided by CRAB runtime environment

# Parse key=value arguments (CRAB prepends jobId as $1, so use key-based parsing)
for arg in "$@"; do
    case "$arg" in
        nEvents=*)    NEVENTS="${arg#*=}" ;;
        nThreads=*)   NTHREAD="${arg#*=}" ;;
        sampleName=*) NAME="${arg#*=}" ;;
        beginSeed=*)  BEGINSEED="${arg#*=}" ;;
        massPoint=*)  MASS_POINT="${arg#*=}" ;;
        gridpack=*)   GRIDPACK="${arg#*=}" ;;
    esac
done
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
export SCRAM_ARCH=$ARCH
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=$RELEASE_GS

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
  --python_filename "${CAMPAIGN_GS}_${NAME}_cfg.py" \
  --eventcontent RAWSIM,LHE \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier GEN-SIM,LHE \
  --fileout "file:${CAMPAIGN_GS}_${NAME}_${JOBINDEX}.root" \
  --conditions $GT_GS \
  --beamspot DBrealistic \
  --step LHE,GEN,SIM \
  --geometry DB:Extended \
  --era $ERA \
  --nThreads $NTHREAD \
  --customise_commands "process.source.numberEventsInLuminosityBlock=cms.untracked.uint32(1000)\\nprocess.source.firstLuminosityBlock=cms.untracked.uint32(${LUMISTART})\\nprocess.source.firstEvent=cms.untracked.uint64(${EVENTSTART})\\nprocess.RandomNumberGeneratorService.externalLHEProducer.initialSeed=${SEED}" \
  --mc \
  -n $NEVENTS || exit $?

ls -lh *.root

############ DIGIPremix ############
export SCRAM_ARCH=$ARCH
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=$RELEASE_DR

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
  --python_filename "${CAMPAIGN_DR}_${NAME}_cfg.py" \
  --eventcontent PREMIXRAW \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier GEN-SIM-RAW \
  --filein "file:${CAMPAIGN_GS}_${NAME}_${JOBINDEX}.root" \
  --fileout "file:${CAMPAIGN_DR}_${NAME}_${JOBINDEX}.root" \
  --pileup_input "dbs:$PREMIX_DATASET" \
  --conditions $GT_DR \
  --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:$HLT_MENU \
  --procModifiers premix_stage2 \
  --geometry DB:Extended \
  --datamix PreMix \
  --era $ERA \
  --runUnscheduled \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

ls -lh *.root

############ RECO (AOD) ############
export SCRAM_ARCH=$ARCH
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=$RELEASE_DR

cd $RELEASE/src
eval $(scram runtime -sh)
cd $WORKDIR

echo ""
echo "Running cmsDriver for RECO step..."
echo ""

cmsDriver.py \
  --python_filename "${CAMPAIGN_RECO}_${NAME}_cfg.py" \
  --eventcontent AODSIM \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier AODSIM \
  --filein "file:${CAMPAIGN_DR}_${NAME}_${JOBINDEX}.root" \
  --fileout "file:${CAMPAIGN_RECO}_${NAME}_${JOBINDEX}.root" \
  --conditions $GT_DR \
  --step RAW2DIGI,L1Reco,RECO,RECOSIM \
  --geometry DB:Extended \
  --era $ERA \
  --runUnscheduled \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

ls -lh *.root

############ MiniAOD + NanoAOD ############
export SCRAM_ARCH=$ARCH
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=$RELEASE_MINI

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
  --python_filename "${CAMPAIGN_MINI}_${NAME}_cfg.py" \
  --eventcontent MINIAODSIM \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier MINIAODSIM \
  --filein "file:${CAMPAIGN_RECO}_${NAME}_${JOBINDEX}.root" \
  --fileout "file:${CAMPAIGN_MINI}_${NAME}_${JOBINDEX}.root" \
  --conditions $GT_MINI \
  --step PAT \
  --geometry DB:Extended \
  --era $ERA \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

echo ""
echo "Running cmsDriver for NanoAODv15 step..."
echo ""

cmsDriver.py \
  --python_filename "${CAMPAIGN_NANO}_${NAME}_cfg.py" \
  --eventcontent NANOAODSIM \
  --customise Configuration/DataProcessing/Utils.addMonitoring \
  --datatier NANOAODSIM \
  --filein "file:${CAMPAIGN_MINI}_${NAME}_${JOBINDEX}.root" \
  --fileout "file:${CAMPAIGN_NANO}_${NAME}_${JOBINDEX}.root" \
  --conditions $GT_MINI \
  --step NANO \
  --geometry DB:Extended \
  --era $ERA \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

ls -lh *.root

############ BTV NanoAOD (allPF) ############
# Produces NanoAOD with full PF candidate collection for a reconstruction
export SCRAM_ARCH=$ARCH
source /cvmfs/cms.cern.ch/cmsset_default.sh
export RELEASE=$RELEASE_BTVNANO

if [ -r $RELEASE/src ]; then
  echo "Release $RELEASE already exists"
else
  scram p CMSSW $RELEASE
fi

cd $RELEASE/src
eval $(scram runtime -sh)
cd $WORKDIR

echo ""
echo "Running cmsDriver for BTV NanoAOD (allPF) step..."
echo ""

cmsDriver.py \
  --python_filename "${CAMPAIGN_BTVNANO}_${NAME}_cfg.py" \
  --eventcontent NANOAODSIM \
  --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/custom_btv_cff.BTVCustomNanoAOD_allPF \
  --datatier NANOAODSIM \
  --filein "file:${CAMPAIGN_MINI}_${NAME}_${JOBINDEX}.root" \
  --fileout "file:${CAMPAIGN_BTVNANO}_${NAME}_${JOBINDEX}.root" \
  --conditions $GT_MINI \
  --step NANO \
  --geometry DB:Extended \
  --era $ERA \
  --mc \
  --nThreads $NTHREAD \
  -n $NEVENTS || exit $?

ls -lh *.root

# Clean up intermediate files to save transfer bandwidth
rm -f ${CAMPAIGN_GS}_${NAME}_${JOBINDEX}.root
rm -f ${CAMPAIGN_DR}_${NAME}_${JOBINDEX}.root
rm -f ${CAMPAIGN_RECO}_${NAME}_${JOBINDEX}.root

# Rename to fixed output names expected by CRAB config
mv ${CAMPAIGN_MINI}_${NAME}_${JOBINDEX}.root ${CAMPAIGN_MINI}_${NAME}.root
mv ${CAMPAIGN_NANO}_${NAME}_${JOBINDEX}.root ${CAMPAIGN_NANO}_${NAME}.root
mv ${CAMPAIGN_BTVNANO}_${NAME}_${JOBINDEX}.root ${CAMPAIGN_BTVNANO}_${NAME}.root

echo ""
echo "========================================"
echo "Production completed successfully!"
echo "========================================"
echo "Output files:"
ls -lh ${CAMPAIGN_MINI}_${NAME}.root ${CAMPAIGN_NANO}_${NAME}.root ${CAMPAIGN_BTVNANO}_${NAME}.root

# Create a valid FrameworkJobReport.xml for CRAB
# (scriptExe jobs need this so CRAB can parse the job outcome and stage out output)
MINIAOD_FILE="${CAMPAIGN_MINI}_${NAME}.root"
NANOAOD_FILE="${CAMPAIGN_NANO}_${NAME}.root"
BTVNANO_FILE="${CAMPAIGN_BTVNANO}_${NAME}.root"
cat > FrameworkJobReport.xml << XMLEOF
<FrameworkJobReport>
<File>
  <LFN/>
  <PFN>${MINIAOD_FILE}</PFN>
  <Catalog/>
  <ModuleLabel>MiniAODoutput</ModuleLabel>
  <GUID>$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")</GUID>
  <OutputModuleClass>PoolOutputModule</OutputModuleClass>
  <TotalEvents>${NEVENTS}</TotalEvents>
  <BranchHash>0</BranchHash>
  <Runs>
  </Runs>
  <Inputs>
  </Inputs>
</File>
<File>
  <LFN/>
  <PFN>${NANOAOD_FILE}</PFN>
  <Catalog/>
  <ModuleLabel>NanoAODoutput</ModuleLabel>
  <GUID>$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")</GUID>
  <OutputModuleClass>PoolOutputModule</OutputModuleClass>
  <TotalEvents>${NEVENTS}</TotalEvents>
  <BranchHash>0</BranchHash>
  <Runs>
  </Runs>
  <Inputs>
  </Inputs>
</File>
<File>
  <LFN/>
  <PFN>${BTVNANO_FILE}</PFN>
  <Catalog/>
  <ModuleLabel>BTVNanoAODoutput</ModuleLabel>
  <GUID>$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")</GUID>
  <OutputModuleClass>PoolOutputModule</OutputModuleClass>
  <TotalEvents>${NEVENTS}</TotalEvents>
  <BranchHash>0</BranchHash>
  <Runs>
  </Runs>
  <Inputs>
  </Inputs>
</File>
<ReadBranches>
</ReadBranches>
<PerformanceReport>
  <PerformanceSummary Metric="StorageStatistics">
    <Metric Name="Parameter-untracked-bool-enabled" Value="true"/>
    <Metric Name="Parameter-untracked-bool-stats" Value="true"/>
    <Metric Name="Parameter-untracked-string-cacheHint" Value="application-only"/>
    <Metric Name="Parameter-untracked-string-readHint" Value="auto-detect"/>
    <Metric Name="stat-num-events" Value="${NEVENTS}"/>
  </PerformanceSummary>
</PerformanceReport>
<GeneratorInfo>
</GeneratorInfo>
</FrameworkJobReport>
XMLEOF

echo "FrameworkJobReport.xml created for CRAB"
