import 'package:sqflite/sqflite.dart';

import '../domain/entities.dart';

/// Bundled offline emergency guides (seed content for T010, format per
/// `assets/guides/README.md`). All three languages mandatory (FR-009).
/// Never fetched from a network (FR-012).
const List<EmergencyProtocolGuide> kSeedGuides = [
  EmergencyProtocolGuide(
    slug: 'flood-basics',
    crisisType: CrisisType.flood,
    title: LocalizedText(
      en: 'Flood Basics',
      tl: 'Mga Batas sa Baha',
      ceb: 'Mga Pag-angkon sa Baha',
    ),
    body: LocalizedText(
      en:
          'Move to higher ground immediately. Do not walk or swim through '
          'moving water. Stay away from downed power lines. Follow official '
          'evacuation orders from your barangay.',
      tl:
          'Pumunta agad sa mataas na lugar. Huwag maglakad o lumangoy sa '
          'malakas na daloy ng tubig. Ilayo sa mga nahulog na kable ng '
          'kuryente. Sundin ang opisyal na utos ng paglikas ng barangay.',
      ceb:
          'Dali sa taas nga lugar. Ayaw paglakat o paglangoy sa daghan nga '
          'tubig. Layo sa mga nahulog nga kable sa kuryente. Sunod sa opisyal '
          'nga paglikas sa barangay.',
    ),
  ),
  EmergencyProtocolGuide(
    slug: 'flood-go-bag',
    crisisType: CrisisType.flood,
    title: LocalizedText(
      en: '72-Hour Go-Bag',
      tl: '72-Hour na Go-Bag',
      ceb: '72-Hour nga Go-Bag',
    ),
    body: LocalizedText(
      en:
          'Pack water (3L/person), canned food, flashlight, batteries, '
          'first-aid kit, prescription medicines, copies of documents in a '
          'waterproof bag, cash, whistle, and a phone charger/power bank.',
      tl:
          'Maghanda ng tubig (3L/tao), de-lata, flashlight, baterya, '
          'first-aid kit, mga gamot, kopya ng mga dokumento sa waterproof na '
          'supot, pera, sipol, at charger/power bank.',
      ceb:
          'Andama nga tubig (3L/katawo), de-lata, flashlight, baterya, '
          'first-aid kit, mga tambal, kopya sa mga dokumento sa waterproof '
          'nga bag, kwarta, sipol, ug charger/power bank.',
    ),
  ),
  EmergencyProtocolGuide(
    slug: 'fire-response',
    crisisType: CrisisType.fire,
    title: LocalizedText(
      en: 'House Fire Response',
      tl: 'Tugon sa Sunog sa Bahay',
      ceb: 'Tubag sa Kalayo sa Balay',
    ),
    body: LocalizedText(
      en:
          'Get out low and fast; feel doors before opening. Call the fire '
          'department from outside. Never go back inside. If clothes catch '
          'fire: stop, drop, and roll.',
      tl:
          'Lumabas nang nakayuko at mabilis. I-feel ang mga pinto bago buksan. '
          'Tawag sa bumbero mula sa labas. Huwag bumalik sa loob. Kung nasunog '
          'ang damit: huminto, gumulong, at mag-ikot.',
      ceb:
          'Gawas nga mubukog ug dali. Paminawa ang pultahan una abliha. '
          'Tawag sa bombero gawas. Ayaw pagbalik sulod. Kung nasunog ang '
          'sinina: undang, higda, ug lingkod.',
    ),
  ),
  EmergencyProtocolGuide(
    slug: 'security-lockdown',
    crisisType: CrisisType.security,
    title: LocalizedText(
      en: 'Lockdown & Security Threat',
      tl: 'Lockdown at Banta sa Seguridad',
      ceb: 'Lockdown ug Kalagot sa Seguridad',
    ),
    body: LocalizedText(
      en:
          'Stay inside a locked room with the door locked if possible. Silence '
          'phones. Stay away from windows. Wait for official all-clear before '
          'leaving.',
      tl:
          'Manatili sa loob ng silid na nakakandado kung maaari. Patayin ang '
          'ringtones ng telepono. Ilayo sa bintana. Maghintay ng opisyal na '
          'all-clear bago lumabas.',
      ceb:
          'Pabilin sa sulod nga kuwarto nga klarado kung mahimo. Patay ang '
          'tono sa telepono. Layo sa bintana. Hulat sa opisyal nga all-clear '
          'una mogawas.',
    ),
  ),
  EmergencyProtocolGuide(
    slug: 'blackout-basics',
    crisisType: CrisisType.blackout,
    title: LocalizedText(
      en: 'Blackout Essentials',
      tl: 'Mga Mahalaga sa Brownout',
      ceb: 'Mga Importante sa Brownout',
    ),
    body: LocalizedText(
      en:
          'Switch off major appliances to prevent surge damage. Use flashlights '
          'instead of candles. Keep the fridge closed. Charge power banks while '
          'power is on. Check on elderly neighbors.',
      tl:
          'Patayin ang mga malalaking appliance para maiwasan ang surge. '
          'Gamitin ang flashlight imbes na kandila. Huwag buksan ang ref. '
          'I-charge ang power bank habang may kuryente. Kulitin ang mga '
          'matatandang kapitbahay.',
      ceb:
          'Patara ang daghang appliance aron dili masunog sa surge. Gamiti ang '
          'flashlight imbes nga kandila. Ayaw abliha ang ref. Charge ang power '
          'bank samtang naay kuryente. Tan-awa ang tigulang mga silingan.',
    ),
  ),
  EmergencyProtocolGuide(
    slug: 'general-first-aid',
    crisisType: CrisisType.general,
    title: LocalizedText(
      en: 'First Aid Quick Guide',
      tl: 'Mabilis na Gabay sa First Aid',
      ceb: 'Dali nga Giya sa First Aid',
    ),
    body: LocalizedText(
      en:
          'For bleeding: apply firm direct pressure with clean cloth. For '
          'burns: cool with running water for 20 minutes. For sprains: rest, '
          'ice, compress, elevate. Call for professional help for anything '
          'serious.',
      tl:
          'Para sa pagdurugo: dumeretso ang presyon gamit ang malinis na tela. '
          'Para sa paso: palamigin ng tubig ng 20 minuto. Para sa sprain: '
          'pahinga, yelo, bintol, itaas. Tumawag ng tulong para sa seryoso.',
      ceb:
          'Para sa pag-agos sa dugo: pugson direkta gamit ang limpyo nga panapet. '
          'Para sa paso: bugnay sa nagagulay nga tubig sulod 20 minutos. Para '
          'sa sprain: pahulay, yelo, higpit, itaas. Tawag og tabang kung grabe.',
    ),
  ),
];

/// Seeds guides into the database if the table is empty (idempotent).
Future<void> seedGuidesIfEmpty(Database db) async {
  final count =
      (await db.rawQuery('SELECT COUNT(*) AS c FROM guides')).first['c'] as int;
  if (count > 0) return;
  final batch = db.batch();
  for (final guide in kSeedGuides) {
    batch.insert('guides', guide.toMap());
  }
  await batch.commit(noResult: true);
}
