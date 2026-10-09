import '../domain/entities.dart';

/// Situation-specific skeleton checklists (FR-006, T016).
///
/// Stage-1 template steps render in ≤2s; the LLM enrichment may refine or
/// reorder them later (merge in T027 preserves user done-state). Max 3 steps
/// per the spec's "3-step action checklist" target; all three languages are
/// present up-front so the US6 language switch is instant.
class TemplateChecklists {
  const TemplateChecklists();

  /// Returns three prioritized, crisis-specific steps (origin: template).
  List<LocalizedText> forCrisis(CrisisType type) {
    switch (type) {
      case CrisisType.flood:
        return const [
          LocalizedText(
            en: 'Turn off the main electrical breaker.',
            tl: 'Patayin ang pangunahing switch ng kuryente (main breaker).',
            ceb: 'Patara ang main nga switch sa kuryente (main breaker).',
          ),
          LocalizedText(
            en: 'Grab your 72-hour emergency go-bag and vital documents.',
            tl: 'Kunin ang 72-hour emergency go-bag at mahahalagang dokumento.',
            ceb: 'Kuha ang 72-hour emergency go-bag ug mahinungdanong mga dokumento.',
          ),
          LocalizedText(
            en: 'Move family to high ground or the barangay hall.',
            tl: 'Ilipat ang pamilya sa mataas na lugar o barangay hall.',
            ceb: 'Lipat ang pamilya sa taas nga lugar o barangay hall.',
          ),
        ];
      case CrisisType.fire:
        return const [
          LocalizedText(
            en: 'Get out low and fast; call the fire department from outside.',
            tl: 'Lumabas nang mabilis at nakayuko; tumawag sa bumbero mula sa labas.',
            ceb: 'Gawas nga dali ug mubukog; tawag sa bombero gawas.',
          ),
          LocalizedText(
            en: 'Close doors behind you to slow the smoke.',
            tl: 'Isara ang mga pinto sa likod mo para bumagal ang usok.',
            ceb: 'Sirad ang mga pultahan sa likod aron hinay ang aso.',
          ),
          LocalizedText(
            en: 'Assemble at the family meeting point away from the building.',
            tl: 'Magpulong sa meeting point ng pamilya na malayo sa gusali.',
            ceb: 'Himutang sa meeting point sa pamilya layo sa building.',
          ),
        ];
      case CrisisType.security:
        return const [
          LocalizedText(
            en: 'Lock doors and silence your phone.',
            tl: 'Ikandado ang mga pinto at patayin ang ringtones ng telepono.',
            ceb: 'Klarado ang mga pultahan ug patara ang tono sa telepono.',
          ),
          LocalizedText(
            en: 'Stay away from windows; keep out of sight.',
            tl: 'Ilayo sa bintana; huwag ipakita ang sarili.',
            ceb: 'Layo sa bintana; ayaw ipakita ang kaugalingon.',
          ),
          LocalizedText(
            en: 'Wait for the official all-clear before leaving.',
            tl: 'Maghintay ng opisyal na all-clear bago lumabas.',
            ceb: 'Hulat sa opisyal nga all-clear una mogawas.',
          ),
        ];
      case CrisisType.blackout:
        return const [
          LocalizedText(
            en: 'Switch off major appliances to prevent surge damage.',
            tl: 'Patayin ang malalaking appliance para maiwasan ang surge.',
            ceb: 'Patara ang daghang appliance aron dili masunog sa surge.',
          ),
          LocalizedText(
            en: 'Use flashlights, not candles; keep the fridge closed.',
            tl: 'Gamitin ang flashlight imbes kandila; huwag buksan ang ref.',
            ceb: 'Gamiti ang flashlight imbes kandila; ayaw abliha ang ref.',
          ),
          LocalizedText(
            en: 'Charge power banks now and check on elderly neighbors.',
            tl: 'I-charge ang power bank ngayon at kulitin ang matatandang kapitbahay.',
            ceb: 'Charge ang power bank karon ug tan-awa ang tigulang silingan.',
          ),
        ];
      case CrisisType.general:
        return const [
          LocalizedText(
            en: 'Read the full notice and share it only from official sources.',
            tl: 'Basahin ang buong anunsyo at ibahagi lang mula sa opisyal na pinagmulan.',
            ceb: 'Basaha ang tibuok pahibalo ug ipaambit gikan sa opisyal nga tinubdan.',
          ),
          LocalizedText(
            en: 'Prepare essentials: water, meds, documents, charged phones.',
            tl: 'Ihanda ang mahahalaga: tubig, gamot, dokumento, charged na telepono.',
            ceb: 'Andama ang mahinungdanon: tubig, tambal, dokumento, charged nga telepono.',
          ),
          LocalizedText(
            en: 'Verify details with the barangay hotline before acting.',
            tl: 'Kumpirmahin ang detalye sa barangay hotline bago kumilos.',
            ceb: 'Kompirmaha ang detalye sa barangay hotline una kumilos.',
          ),
        ];
    }
  }
}
