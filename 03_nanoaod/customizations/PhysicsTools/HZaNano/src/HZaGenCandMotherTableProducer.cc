#include "FWCore/Framework/interface/global/EDProducer.h"
#include "FWCore/Framework/interface/Event.h"
#include "FWCore/ParameterSet/interface/ParameterSet.h"
#include "FWCore/ParameterSet/interface/ConfigurationDescriptions.h"
#include "FWCore/ParameterSet/interface/ParameterSetDescription.h"
#include "FWCore/Utilities/interface/Exception.h"

#include "DataFormats/NanoAOD/interface/FlatTable.h"
#include "DataFormats/Common/interface/View.h"
#include "DataFormats/Common/interface/Association.h"
#include "DataFormats/Candidate/interface/Candidate.h"
#include "DataFormats/PatCandidates/interface/PackedGenParticle.h"
#include "DataFormats/HepMCCandidate/interface/GenParticle.h"
#include "DataFormats/Math/interface/deltaR.h"

#include "PhysicsTools/JetMCUtils/interface/CandMCTag.h"

#include <vector>
#include <cmath>

class HZaGenCandMotherTableProducer : public edm::global::EDProducer<> {
public:
  explicit HZaGenCandMotherTableProducer(edm::ParameterSet const &params)
      : objName_(params.getParameter<std::string>("objName")),
        branchName_(params.getParameter<std::string>("branchName")),
        src_(consumes<edm::View<pat::PackedGenParticle>>(params.getParameter<edm::InputTag>("src"))),
        candMap_(consumes<edm::Association<reco::GenParticleCollection>>(params.getParameter<edm::InputTag>("mcMap"))),
        genPartsToken_(consumes<reco::GenParticleCollection>(params.getParameter<edm::InputTag>("genparticles"))) {
    produces<nanoaod::FlatTable>();
  }

  ~HZaGenCandMotherTableProducer() override = default;

  void produce(edm::StreamID, edm::Event &iEvent, const edm::EventSetup &) const override {
    edm::Handle<edm::View<pat::PackedGenParticle>> cands;
    iEvent.getByToken(src_, cands);
    const unsigned int ncand = cands->size();

    edm::Handle<edm::Association<reco::GenParticleCollection>> map;
    iEvent.getByToken(candMap_, map);

    edm::Handle<reco::GenParticleCollection> genParts;
    iEvent.getByToken(genPartsToken_, genParts);

    auto tab = std::make_unique<nanoaod::FlatTable>(ncand, objName_, false, true);

    std::vector<int> key(ncand, -1), fromB(ncand, 0), fromC(ncand, 0);
    for (unsigned int i = 0; i < ncand; ++i) {
      const auto &cand = cands->at(i);
      key[i] = robustMotherIndex(cand, *map, *genParts);
      fromB[i] = isFromB(cand);
      fromC[i] = isFromC(cand);
    }

    tab->addColumn<int>(branchName_ + "MotherIdx", key, "Mother index into GenPart list");
    tab->addColumn<uint8_t>("isFromB", fromB, "Is from B hadron: no: 0, any: 1, final: 2");
    tab->addColumn<uint8_t>("isFromC", fromC, "Is from C hadron: no: 0, any: 1, final: 2");
    iEvent.put(std::move(tab));
  }

  static void fillDescriptions(edm::ConfigurationDescriptions &descriptions) {
    edm::ParameterSetDescription desc;
    desc.add<std::string>("objName", "GenCands");
    desc.add<std::string>("branchName", "GenPart");
    desc.add<edm::InputTag>("src", edm::InputTag("packedGenParticles"));
    desc.add<edm::InputTag>("mcMap", edm::InputTag("finalGenParticles"));
    desc.add<edm::InputTag>("genparticles", edm::InputTag("finalGenParticles"));
    descriptions.add("hzaGenCandMotherTable", desc);
  }

private:
  int robustMotherIndex(const pat::PackedGenParticle &cand,
                        const edm::Association<reco::GenParticleCollection> &map,
                        const reco::GenParticleCollection &genParts) const {
    reco::GenParticleRef motherRef = cand.motherRef();

    while (motherRef.isNonnull()) {
      reco::GenParticleRef match;
      try {
        match = map[motherRef];
      } catch (cms::Exception const &) {
        match = reco::GenParticleRef();
      }

      if (match.isNonnull()) {
        return static_cast<int>(match.key());
      }

      const reco::Candidate *momCand = motherRef.get();
      if (momCand != nullptr) {
        const int fallback = findClosestGenPart(*momCand, genParts);
        if (fallback >= 0) {
          return fallback;
        }
      }

      if (motherRef->numberOfMothers() == 0)
        break;
      motherRef = motherRef->motherRef();
    }

    return -1;
  }

  int findClosestGenPart(const reco::Candidate &cand, const reco::GenParticleCollection &genParts) const {
    const float maxDR2 = 1e-6f;
    const float maxRelPt = 0.05f;

    int best = -1;
    float bestDR2 = maxDR2;

    for (size_t i = 0; i < genParts.size(); ++i) {
      const auto &gp = genParts[i];
      if (gp.pdgId() != cand.pdgId())
        continue;

      const float dr2 = reco::deltaR2(cand.eta(), cand.phi(), gp.eta(), gp.phi());
      if (dr2 > bestDR2)
        continue;

      if (gp.pt() > 0.f) {
        const float relPt = std::abs(cand.pt() - gp.pt()) / gp.pt();
        if (relPt > maxRelPt)
          continue;
      }

      best = static_cast<int>(i);
      bestDR2 = dr2;
    }

    return best;
  }

  bool isFinalB(const reco::Candidate &particle) const {
    if (!CandMCTagUtils::hasBottom(particle))
      return false;

    const unsigned int npart = particle.numberOfDaughters();
    for (size_t i = 0; i < npart; ++i) {
      if (CandMCTagUtils::hasBottom(*particle.daughter(i)))
        return false;
    }
    return true;
  }

  int isFromB(const reco::Candidate &particle) const {
    int fromB = 0;
    const unsigned int npart = particle.numberOfMothers();
    for (size_t i = 0; i < npart; ++i) {
      const reco::Candidate &mom = *particle.mother(i);
      if (CandMCTagUtils::hasBottom(mom)) {
        fromB = isFinalB(mom) ? 2 : 1;
        break;
      }
      fromB = isFromB(mom);
    }
    return fromB;
  }

  bool isFinalC(const reco::Candidate &particle) const {
    if (!CandMCTagUtils::hasCharm(particle))
      return false;

    const unsigned int npart = particle.numberOfDaughters();
    for (size_t i = 0; i < npart; ++i) {
      if (CandMCTagUtils::hasCharm(*particle.daughter(i)))
        return false;
    }
    return true;
  }

  int isFromC(const reco::Candidate &particle) const {
    int fromC = 0;
    const unsigned int npart = particle.numberOfMothers();
    for (size_t i = 0; i < npart; ++i) {
      const reco::Candidate &mom = *particle.mother(i);
      if (CandMCTagUtils::hasCharm(mom)) {
        fromC = isFinalC(mom) ? 2 : 1;
        break;
      }
      fromC = isFromC(mom);
    }
    return fromC;
  }

  const std::string objName_;
  const std::string branchName_;
  const edm::EDGetTokenT<edm::View<pat::PackedGenParticle>> src_;
  const edm::EDGetTokenT<edm::Association<reco::GenParticleCollection>> candMap_;
  const edm::EDGetTokenT<reco::GenParticleCollection> genPartsToken_;
};

#include "FWCore/Framework/interface/MakerMacros.h"
DEFINE_FWK_MODULE(HZaGenCandMotherTableProducer);
