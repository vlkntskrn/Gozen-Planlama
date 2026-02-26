
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;


TimeOfDay? parseHHMM(String s) {
  // Accepts HH:MM (24h). Returns null if invalid.
  final parts = s.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23) return null;
  if (m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);


DateTime? _parseExcelDateLocal(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return DateUtils.dateOnly(v);
  // excel package sometimes returns xl.Data with .value; caller should pass raw .value
  if (v is num) {
    // Excel serial date (days since 1899-12-30)
    final base = DateTime(1899, 12, 30);
    return DateUtils.dateOnly(base.add(Duration(days: v.floor())));
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  // Try dd.MM.yyyy or dd/MM/yyyy
  final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    return DateUtils.dateOnly(DateTime(y, mo, d));
  }
  return null;
}

TimeOfDay? _parseExcelTimeLocal(dynamic v) {
  if (v == null) return null;
  if (v is TimeOfDay) return v;
  if (v is DateTime) return TimeOfDay(hour: v.hour, minute: v.minute);
  if (v is num) {
    // Excel serial time as fraction of day
    final totalMinutes = (v * 24 * 60).round();
    final h = (totalMinutes ~/ 60) % 24;
    final m = totalMinutes % 60;
    return TimeOfDay(hour: h, minute: m);
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  // accept HH:MM or H:MM
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h >= 0 && h <= 23 && mi >= 0 && mi <= 59) return TimeOfDay(hour: h, minute: mi);
  }
  return parseHHMM(s);
}

}

void main() {
  runApp(const GozenApp());
}

class GozenApp extends StatelessWidget {
  const GozenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppStoreScope(
      store: AppStore()..seedDemo(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Gozen Planlama',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const HomePage(),
      ),
    );
  }
}

enum AppRole { admin, supervisor, agent }
enum TitleType { airsider, interviewer, teamLeader, tarmacTeamLeader }
enum Gender { male, female }
enum RequestType { off, sabah, gunduz, aksam, gece }

String appRoleLabel(AppRole r) {
  switch (r) {
    case AppRole.admin:
      return 'Admin';
    case AppRole.supervisor:
      return 'Supervisor';
    case AppRole.agent:
      return 'Agent';
  }
}

String titleLabel(TitleType t) {
  switch (t) {
    case TitleType.airsider:
      return 'Airsider';
    case TitleType.interviewer:
      return 'Interviewer';
    case TitleType.teamLeader:
      return 'Team Leader';
    case TitleType.tarmacTeamLeader:
      return 'Tarmac Team Leader';
  }
}

String genderLabel(Gender g) => g == Gender.male ? 'Erkek' : 'Kadın';

String requestTypeLabel(RequestType t) {
  switch (t) {
    case RequestType.off:
      return 'OFF';
    case RequestType.sabah:
      return 'Sabah';
    case RequestType.gunduz:
      return 'Gündüz';
    case RequestType.aksam:
      return 'Akşam';
    case RequestType.gece:
      return 'Gece';
  }
}

List<String> skillsForTitle(TitleType t) {
  switch (t) {
    case TitleType.airsider:
      return const ['BA CHUTE', 'APIS'];
    case TitleType.interviewer:
      return const ['Doc. Check'];
    case TitleType.teamLeader:
    case TitleType.tarmacTeamLeader:
      return const [];
  }
}

class PersonConstraints {
  bool geceYok;
  bool gunduzYok;
  bool sabahYok;
  int maxVardiyaSaat;
  String note;

  PersonConstraints({
    this.geceYok = false,
    this.gunduzYok = false,
    this.sabahYok = false,
    this.maxVardiyaSaat = 12,
    this.note = '',
  });
}

class Person {
  final String id;
  String name;
  AppRole appRole;
  TitleType title;
  Gender gender;
  List<String> skills;
  bool active;
  PersonConstraints constraints;

  Person({
    required this.id,
    required this.name,
    required this.appRole,
    required this.title,
    required this.gender,
    required this.skills,
    required this.active,
    required this.constraints,
  });
}

class StaffRequest {
  final String id;
  final String personId;
  DateTime date;
  RequestType type;
  bool managerApproved;
  String note;

  StaffRequest({
    required this.id,
    required this.personId,
    required this.date,
    required this.type,
    this.managerApproved = false,
    this.note = '',
  });
}

class FlightItem {
  final String id;
  DateTime date;
  String flightNo;
  String destination;
  TimeOfDay std;
  TimeOfDay? sta;

  FlightItem({
    required this.id,
    required this.date,
    required this.flightNo,
    required this.destination,
    required this.std,
    this.sta,
  });
}


enum FlightPosition {
  checkinInterviewer,
  checkinTeamLeader,
  checkinSupervisor,
  checkinApis,
  gateTeamLeader,
  gateDocCheck,
  gatePaxId,
  gateSearch1,
  gateSearch2,
  gateObserver,
  gateApis,
  ramp,
  back,
  jetty,
  chute,
  baggageEscort,
  catering,
  barcode,
  cargo,
  cargoEscort,
  acSearch,
  tarmacTeamLeader,
  extraAirsiderBuffer,
}


String positionLabel(FlightPosition p) {
  switch (p) {
    case FlightPosition.checkinInterviewer:
      return 'Check-in Interviewer';
    case FlightPosition.checkinTeamLeader:
      return 'Check-in Team Leader';
    case FlightPosition.checkinSupervisor:
      return 'Check-in Supervisor';
    case FlightPosition.checkinApis:
      return 'Check-in APIS';
    case FlightPosition.gateTeamLeader:
      return 'Gate Team Leader';
    case FlightPosition.gateDocCheck:
      return 'Gate Doc. Check';
    case FlightPosition.gatePaxId:
      return 'Gate Pax ID';
    case FlightPosition.gateSearch1:
      return 'Gate Search 1';
    case FlightPosition.gateSearch2:
      return 'Gate Search 2';
    case FlightPosition.gateObserver:
      return 'Gate Observer';
    case FlightPosition.gateApis:
      return 'Gate APIS';
    case FlightPosition.ramp:
      return 'Ramp';
    case FlightPosition.back:
      return 'Back';
    case FlightPosition.jetty:
      return 'Jetty';
    case FlightPosition.chute:
      return 'Chute';
    case FlightPosition.baggageEscort:
      return 'Baggage Escort';
    case FlightPosition.catering:
      return 'Catering';
    case FlightPosition.barcode:
      return 'Barcode';
    case FlightPosition.cargo:
      return 'Cargo';
    case FlightPosition.cargoEscort:
      return 'Cargo Escort';
    case FlightPosition.acSearch:
      return 'A/C Search';
    case FlightPosition.tarmacTeamLeader:
      return 'Tarmac Team Leader';
    case FlightPosition.extraAirsiderBuffer:
      return 'Extra Airsider (No-show)';
  }
}


class FlightNeed {
  final String id;
  final String flightId;
  FlightPosition position;
  int requiredCount;

  // Basit kural alanları (V1)
  TitleType requiredTitle;
  Gender? requiredGender; // null = fark etmez
  String? requiredSkill; // null = yok

  // Vardiya önerisi (V1)
  String? shiftCode;
  TimeOfDay? shiftStart;
  TimeOfDay? shiftEnd;

  FlightNeed({
    required this.id,
    required this.flightId,
    required this.position,
    required this.requiredCount,
    required this.requiredTitle,
    this.requiredGender,
    this.requiredSkill,
    this.shiftCode,
    this.shiftStart,
    this.shiftEnd,
  });
}


class _NeedTemplate {
  final FlightPosition pos;
  final String necessity; // MUST / IF AVAIBLE
  final int count;
  final TitleType? title;
  final Gender? gender; // null = fark etmez
  final String? skill;

  const _NeedTemplate({
    required this.pos,
    required this.necessity,
    required this.count,
    this.title,
    this.gender,
    this.skill,
  });
}

const Map<String, List<_NeedTemplate>> kIataNeedTemplates = {
  // Gate olmayan IATA'lar (OR / X3 / BLX / TB): sadece Ramp/Back/Jetty + Tarmac TL
  'OR': [
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],
  'X3': [
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],
  'BLX': [
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],
  'TB': [
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],

  // 6B (Excel'de Nordic) - gate yok olarak belirtilmişti, aynı şablon
  '6B': [
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],

  // UK gate + airside setleri
  'LS': [
    _NeedTemplate(pos: FlightPosition.gateTeamLeader, necessity: 'MUST', count: 1, title: TitleType.teamLeader),
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.gateObserver, necessity: 'IF AVAIBLE', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.chute, necessity: 'MUST', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],
  'FHY': [
    _NeedTemplate(pos: FlightPosition.gateTeamLeader, necessity: 'MUST', count: 1, title: TitleType.teamLeader),
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.gateObserver, necessity: 'IF AVAIBLE', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.chute, necessity: 'MUST', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],
  'BA': [
    _NeedTemplate(pos: FlightPosition.gateTeamLeader, necessity: 'MUST', count: 1, title: TitleType.teamLeader, skill: 'Doc. Check'),
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.gateObserver, necessity: 'IF AVAIBLE', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.chute, necessity: 'MUST', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.baggageEscort, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],
  'TK': [
    _NeedTemplate(pos: FlightPosition.gateTeamLeader, necessity: 'MUST', count: 1, title: TitleType.teamLeader),
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.gateObserver, necessity: 'IF AVAIBLE', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.jetty, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.chute, necessity: 'MUST', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.baggageEscort, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],

  // XQ ve TOM: CHUTE YOK (kilit)
  'XQ': [
    _NeedTemplate(pos: FlightPosition.gateTeamLeader, necessity: 'MUST', count: 1, title: TitleType.teamLeader),
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.gateObserver, necessity: 'IF AVAIBLE', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],
  'TOM': [
    _NeedTemplate(pos: FlightPosition.gateTeamLeader, necessity: 'MUST', count: 1, title: TitleType.teamLeader),
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.gateObserver, necessity: 'IF AVAIBLE', count: 1, title: TitleType.airsider),
    _NeedTemplate(pos: FlightPosition.ramp, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.back, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.tarmacTeamLeader, necessity: 'MUST', count: 1, title: TitleType.tarmacTeamLeader),
  ],

  // Diğer gate-only IATA'lar (gate ekibi)
  'EW': [
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
    _NeedTemplate(pos: FlightPosition.gateObserver, necessity: 'IF AVAIBLE', count: 1, title: TitleType.airsider),
  ],
  'OS': [
    _NeedTemplate(pos: FlightPosition.gateTeamLeader, necessity: 'MUST', count: 1, title: TitleType.teamLeader),
    _NeedTemplate(pos: FlightPosition.gatePaxId, necessity: 'MUST', count: 1, title: TitleType.interviewer),
    _NeedTemplate(pos: FlightPosition.gateSearch1, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.male),
    _NeedTemplate(pos: FlightPosition.gateSearch2, necessity: 'MUST', count: 1, title: TitleType.airsider, gender: Gender.female),
  ],
};




class RulesConfig {
  int requestLimit15Days = 5;
  int maxConsecutiveWorkDays = 6;
  int maxConsecutive12hDays = 2;
  int maxConsecutiveNightDays = 2;
  int minRestHoursBetweenShifts = 11;

  // Off hedefleri (15 gün)
  int offTargetAirsiderInterviewer = 3;
  int offTargetTeamLeaderTarmac = 4;

  bool extraAirsiderPerShift = true;
  bool alternateExtraAirsiderGender = true;
  Gender startExtraAirsiderGender = Gender.male;
  bool gateObserverMust = true;
}

class AppStore extends ChangeNotifier {
  final List<Person> persons = [];
  final List<StaffRequest> requests = [];
  final List<FlightItem> flights = [];
  final List<FlightNeed> needs = [];
  final RulesConfig rules = RulesConfig();

  Gender _nextExtraGender = Gender.male;

  int _id = 0;
  String nextId() => (++_id).toString();

  void seedDemo() {
    _nextExtraGender = rules.startExtraAirsiderGender;
    persons.addAll([
      Person(
        id: nextId(),
        name: 'Ahmet Yılmaz',
        appRole: AppRole.agent,
        title: TitleType.airsider,
        gender: Gender.male,
        skills: ['APIS'],
        active: true,
        constraints: PersonConstraints(),
      ),
      Person(
        id: nextId(),
        name: 'Ayşe Demir',
        appRole: AppRole.agent,
        title: TitleType.airsider,
        gender: Gender.female,
        skills: ['BA CHUTE'],
        active: true,
        constraints: PersonConstraints(),
      ),
      Person(
        id: nextId(),
        name: 'Can Kaya',
        appRole: AppRole.supervisor,
        title: TitleType.interviewer,
        gender: Gender.male,
        skills: ['Doc. Check'],
        active: true,
        constraints: PersonConstraints(maxVardiyaSaat: 8),
      ),
    ]);
    notifyListeners();
  }

  void addOrUpdatePerson(Person p) {
    final i = persons.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      persons[i] = p;
    } else {
      persons.add(p);
    }
    notifyListeners();
  }

  void togglePersonActive(String id) {
    final p = persons.firstWhere((e) => e.id == id);
    p.active = !p.active;
    notifyListeners();
  }

  void deletePerson(String id) {
    persons.removeWhere((e) => e.id == id);
    requests.removeWhere((e) => e.personId == id);
    notifyListeners();
  }

  int requestsIn15Days(String personId, DateTime centerDate) {
    final start = DateUtils.dateOnly(centerDate.subtract(const Duration(days: 14)));
    final end = DateUtils.dateOnly(centerDate);
    return requests.where((r) {
      final d = DateUtils.dateOnly(r.date);
      return r.personId == personId &&
          !d.isBefore(start) &&
          !d.isAfter(end);
    }).length;
  }

  String? canAddRequest(String personId, DateTime date, {String? editingId}) {
    final count = requests.where((r) {
      if (editingId != null && r.id == editingId) return false;
      final start = DateUtils.dateOnly(date.subtract(const Duration(days: 14)));
      final d = DateUtils.dateOnly(r.date);
      return r.personId == personId &&
          !d.isBefore(start) &&
          !d.isAfter(DateUtils.dateOnly(date));
    }).length;
    if (count >= rules.requestLimit15Days) {
      return '15 günde talep limiti aşıldı (${rules.requestLimit15Days})';
    }
    return null;
  }

  void addOrUpdateRequest(StaffRequest r) {
    final i = requests.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      requests[i] = r;
    } else {
      requests.add(r);
    }
    requests.sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
  }

  void deleteRequest(String id) {
    requests.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void addOrUpdateFlight(FlightItem f) {
    final i = flights.indexWhere((e) => e.id == f.id);
    if (i >= 0) {
      flights[i] = f;
    } else {
      flights.add(f);
    }
    flights.sort((a, b) {
      final d = DateUtils.dateOnly(a.date).compareTo(DateUtils.dateOnly(b.date));
      if (d != 0) return d;
      return _todMinutes(a.std).compareTo(_todMinutes(b.std));
    });

    // Kullanıcıya göstermeden otomatik ihtiyaç + vardiya önerisi üret
    generateNeedsForFlight(f.id);
    suggestShiftsForFlight(f.id);
  }

  void deleteFlight(String id) {
    flights.removeWhere((e) => e.id == id);
    needs.removeWhere((n) => n.flightId == id);
    notifyListeners();
  }


List<FlightNeed> needsForFlight(String flightId) {
  return needs.where((n) => n.flightId == flightId).toList()
    ..sort((a, b) => a.position.index.compareTo(b.position.index));
}

void setNeedCount(String needId, int count) {
  final i = needs.indexWhere((e) => e.id == needId);
  if (i < 0) return;
  needs[i].requiredCount = count.clamp(0, 99);
  notifyListeners();
}


void generateNeedsForFlight(String flightId) {
  // Excel kural setinden gömülü IATA şablonlarına göre ihtiyaç üretir.
  needs.removeWhere((n) => n.flightId == flightId);

  FlightItem? flight;
  for (final f in flights) {
    if (f.id == flightId) {
      flight = f;
      break;
    }
  }
  if (flight == null) {
    notifyListeners();
    return;
  }

  final iata = _extractIata(flight.flightNo);
  final templates = kIataNeedTemplates[iata];

  if (templates == null) {
    // Fallback: sadece temel Gate Search + Gate Observer (rule'a göre)
    needs.add(FlightNeed(
      id: nextId(),
      flightId: flightId,
      position: FlightPosition.gateSearch1,
      requiredCount: 1,
      requiredTitle: TitleType.airsider,
    ));
    needs.add(FlightNeed(
      id: nextId(),
      flightId: flightId,
      position: FlightPosition.gateSearch2,
      requiredCount: 1,
      requiredTitle: TitleType.airsider,
    ));
    if (rules.gateObserverMust) {
      needs.add(FlightNeed(
        id: nextId(),
        flightId: flightId,
        position: FlightPosition.gateObserver,
        requiredCount: 1,
        requiredTitle: TitleType.airsider,
      ));
    }
    notifyListeners();
    return;
  }

  for (final t in templates) {
    final nec = t.necessity.toUpperCase().trim();

    // IF AVAIBLE sadece Gate Observer için; MUST değilse gateObserverMust'a göre al.
    if (nec.startsWith('IF')) {
      if (!(t.pos == FlightPosition.gateObserver && rules.gateObserverMust)) {
        continue;
      }
    } else if (nec != 'MUST') {
      continue;
    }

    needs.add(FlightNeed(
      id: nextId(),
      flightId: flightId,
      position: t.pos,
      requiredCount: t.count,
      requiredTitle: t.title ?? TitleType.airsider,
      requiredGender: t.gender,
      requiredSkill: t.skill,
    ));
  }

  notifyListeners();
}

String _extractIata(String flightNo) {
  final m = RegExp(r'^[A-Za-z]+').firstMatch(flightNo.trim());
  return (m?.group(0) ?? '').toUpperCase();
}





  int _todMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  

// Vardiya kodu + saat önerisi (V1)
void suggestShiftsForFlight(String flightId) {
  FlightItem? flight;
  for (final f in flights) {
    if (f.id == flightId) {
      flight = f;
      break;
    }
  }
  if (flight == null) return;

  final code0 = _suggestShiftCode(flight.std);

for (final n in needs.where((e) => e.flightId == flightId)) {
  // Default: STD'den 60 dk önce başla, 8 saat sür.
  // Ramp/Back/Jetty için min 2:00 (120 dk) offset kuralı uygulanır.
  final start = _addMinutes(flight.std, _startOffsetMinutesForPosition(n.position));
  final end = _addMinutes(start, 8 * 60); // default 8 saat

  n.shiftCode = code0;
  n.shiftStart = start;
  n.shiftEnd = end;
}

  if (rules.extraAirsiderPerShift) {
    final exists = needs.any((n) => n.flightId == flightId && n.position == FlightPosition.extraAirsiderBuffer);
    if (!exists) {
      final extraGender = _nextExtraGender;
      final start = _addMinutes(flight.std, _startOffsetMinutesForPosition(FlightPosition.extraAirsiderBuffer));
      final end = _addMinutes(start, 8 * 60);
      needs.add(FlightNeed(
        id: nextId(),
        flightId: flightId,
        position: FlightPosition.extraAirsiderBuffer,
        requiredCount: 1,
        requiredTitle: TitleType.airsider,
        requiredGender: extraGender,
        shiftCode: code0,
        shiftStart: start,
        shiftEnd: end,
      ));

      if (rules.alternateExtraAirsiderGender) {
        _nextExtraGender = (extraGender == Gender.male) ? Gender.female : Gender.male;
      }
    }
  }

  notifyListeners();
}


int _startOffsetMinutesForPosition(FlightPosition p) {
  switch (p) {
    case FlightPosition.ramp:
    case FlightPosition.back:
    case FlightPosition.jetty:
      return -120; // 2:00
    default:
      return -60;
  }
}

String _suggestShiftCode(TimeOfDay std) {
  final h = std.hour;
  if (h < 10) return 'V';
  if (h < 16) return 'V1';
  if (h < 22) return 'V3';
  return 'V7';
}

TimeOfDay _addMinutes(TimeOfDay t, int minutes) {
  final total = t.hour * 60 + t.minute + minutes;
  final wrapped = ((total % (24 * 60)) + (24 * 60)) % (24 * 60);
  return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
}

void notifyRulesChanged() => notifyListeners();
}

class AppStoreScope extends InheritedNotifier<AppStore> {
  const AppStoreScope({super.key, required AppStore store, required Widget child})
      : super(notifier: store, child: child);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStoreScope>();
    return scope!.notifier!;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardPage(),
      PersonListPage(),
      RequestsPage(),
      FlightsPage(),
      RulesPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Gozen Planlama')),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Personel'),
          NavigationDestination(icon: Icon(Icons.event_note), label: 'Talepler'),
          NavigationDestination(icon: Icon(Icons.flight), label: 'Uçuş'),
          NavigationDestination(icon: Icon(Icons.rule), label: 'Kurallar'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  int _count(AppStore store, TitleType t, {Gender? g}) {
    return store.persons.where((p) {
      return p.active && p.title == t && (g == null || p.gender == g);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    final cards = <MapEntry<String, int>>[
      MapEntry('Erkek Airsider', _count(store, TitleType.airsider, g: Gender.male)),
      MapEntry('Kadın Airsider', _count(store, TitleType.airsider, g: Gender.female)),
      MapEntry('Interviewer', _count(store, TitleType.interviewer)),
      MapEntry('Tarmac Team Leader', _count(store, TitleType.tarmacTeamLeader)),
      MapEntry('Team Leader', _count(store, TitleType.teamLeader)),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Özet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...cards.map((e) => Card(
              child: ListTile(
                title: Text(e.key),
                trailing: Text(e.value.toString(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Uçuş: ${store.flights.length} • Personel: ${store.persons.where((p) => p.active).length} • Talepler: ${store.requests.length}',
            ),
          ),
        ),
      ],
    );
  }
}

class PersonListPage extends StatelessWidget {
  const PersonListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: store.persons.length,
        itemBuilder: (_, i) {
          final p = store.persons[i];
          return Card(
            child: ListTile(
              title: Text('${p.name} (${titleLabel(p.title)})'),
              subtitle: Text(
                '${genderLabel(p.gender)} • ${appRoleLabel(p.appRole)}'
                '${p.skills.isEmpty ? "" : " • ${p.skills.join(", ")}"}'
                '${p.active ? "" : " • PASİF"}',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PersonEditorPage(person: p)),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'toggle') store.togglePersonActive(p.id);
                  if (v == 'delete') store.deletePerson(p.id);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'toggle', child: Text(p.active ? 'Pasif yap' : 'Aktif yap')),
                  const PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PersonEditorPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Personel Ekle'),
      ),
    );
  }
}

class PersonEditorPage extends StatefulWidget {
  final Person? person;
  const PersonEditorPage({super.key, this.person});

  @override
  State<PersonEditorPage> createState() => _PersonEditorPageState();
}

class _PersonEditorPageState extends State<PersonEditorPage> {
  final nameCtl = TextEditingController();
  final noteCtl = TextEditingController();

  AppRole appRole = AppRole.agent;
  TitleType title = TitleType.airsider;
  Gender gender = Gender.male;
  final Set<String> selectedSkills = {};
  bool active = true;

  bool geceYok = false;
  bool gunduzYok = false;
  bool sabahYok = false;
  int maxSaat = 12;

  @override
  void initState() {
    super.initState();
    final p = widget.person;
    if (p != null) {
      nameCtl.text = p.name;
      appRole = p.appRole;
      title = p.title;
      gender = p.gender;
      selectedSkills.addAll(p.skills);
      active = p.active;
      geceYok = p.constraints.geceYok;
      gunduzYok = p.constraints.gunduzYok;
      sabahYok = p.constraints.sabahYok;
      maxSaat = p.constraints.maxVardiyaSaat;
      noteCtl.text = p.constraints.note;
    }
  }

  @override
  void dispose() {
    nameCtl.dispose();
    noteCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    final availableSkills = skillsForTitle(title);
    selectedSkills.removeWhere((s) => !availableSkills.contains(s));

    return Scaffold(
      appBar: AppBar(title: Text(widget.person == null ? 'Personel Ekle' : 'Personel Düzenle')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Ad Soyad')),
          const SizedBox(height: 8),
          DropdownButtonFormField<AppRole>(
            value: appRole,
            items: AppRole.values
                .map((e) => DropdownMenuItem(value: e, child: Text(appRoleLabel(e))))
                .toList(),
            onChanged: (v) => setState(() => appRole = v!),
            decoration: const InputDecoration(labelText: 'App Rolü'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TitleType>(
            value: title,
            items: TitleType.values
                .map((e) => DropdownMenuItem(value: e, child: Text(titleLabel(e))))
                .toList(),
            onChanged: (v) => setState(() => title = v!),
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<Gender>(
            value: gender,
            items: Gender.values
                .map((e) => DropdownMenuItem(value: e, child: Text(genderLabel(e))))
                .toList(),
            onChanged: (v) => setState(() => gender = v!),
            decoration: const InputDecoration(labelText: 'Gender'),
          ),
          const SizedBox(height: 12),
          const Text('Skills'),
          if (availableSkills.isEmpty)
            const Text('Bu title için skill yok.')
          else
            Wrap(
              spacing: 8,
              children: availableSkills.map((s) {
                final selected = selectedSkills.contains(s);
                return FilterChip(
                  label: Text(s),
                  selected: selected,
                  onSelected: (v) => setState(() => v ? selectedSkills.add(s) : selectedSkills.remove(s)),
                );
              }).toList(),
            ),
          const SizedBox(height: 4),
          const Text("Skill listesi title'a göre gösterilir.",
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const Divider(height: 24),
          const Text('Kısıtlar', style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(
            value: geceYok,
            onChanged: (v) => setState(() => geceYok = v),
            title: const Text('Gece yok'),
            dense: true,
          ),
          SwitchListTile(
            value: gunduzYok,
            onChanged: (v) => setState(() => gunduzYok = v),
            title: const Text('Gündüz yok'),
            dense: true,
          ),
          SwitchListTile(
            value: sabahYok,
            onChanged: (v) => setState(() => sabahYok = v),
            title: const Text('Sabah yok'),
            dense: true,
          ),
          DropdownButtonFormField<int>(
            value: maxSaat,
            items: const [8, 10, 12]
                .map((e) => DropdownMenuItem(value: e, child: Text('$e saat')))
                .toList(),
            onChanged: (v) => setState(() => maxSaat = v!),
            decoration: const InputDecoration(labelText: 'Maks vardiya süresi'),
          ),
          const SizedBox(height: 8),
          TextField(controller: noteCtl, decoration: const InputDecoration(labelText: 'Kısıt notu')),
          SwitchListTile(
            value: active,
            onChanged: (v) => setState(() => active = v),
            title: const Text('Aktif'),
            dense: true,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (nameCtl.text.trim().isEmpty) return;
              final person = Person(
                id: widget.person?.id ?? store.nextId(),
                name: nameCtl.text.trim(),
                appRole: appRole,
                title: title,
                gender: gender,
                skills: selectedSkills.toList(),
                active: active,
                constraints: PersonConstraints(
                  geceYok: geceYok,
                  gunduzYok: gunduzYok,
                  sabahYok: sabahYok,
                  maxVardiyaSaat: maxSaat,
                  note: noteCtl.text.trim(),
                ),
              );
              store.addOrUpdatePerson(person);
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: store.requests.length,
        itemBuilder: (_, i) {
          final r = store.requests[i];
          final p = store.persons.where((e) => e.id == r.personId).isNotEmpty
              ? store.persons.firstWhere((e) => e.id == r.personId)
              : null;
          return Card(
            child: ListTile(
              title: Text('${p?.name ?? "Silinmiş"} • ${requestTypeLabel(r.type)}'),
              subtitle: Text('${_fmtDate(r.date)}${r.managerApproved ? " • Müdür onaylı" : ""}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RequestEditorPage(request: r)),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => store.deleteRequest(r.id),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RequestEditorPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Talep Ekle'),
      ),
    );
  }
}

class RequestEditorPage extends StatefulWidget {
  final StaffRequest? request;
  const RequestEditorPage({super.key, this.request});

  @override
  State<RequestEditorPage> createState() => _RequestEditorPageState();
}

class _RequestEditorPageState extends State<RequestEditorPage> {
  String? personId;
  DateTime date = DateUtils.dateOnly(DateTime.now());
  RequestType type = RequestType.off;
  bool managerApproved = false;

  @override
  void initState() {
    super.initState();
    final r = widget.request;
    if (r != null) {
      personId = r.personId;
      date = DateUtils.dateOnly(r.date);
      type = r.type;
      managerApproved = r.managerApproved;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.request == null ? 'Talep Ekle' : 'Talep Düzenle')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          DropdownButtonFormField<String>(
            value: personId,
            items: store.persons
                .where((p) => p.active)
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                .toList(),
            onChanged: (v) => setState(() => personId = v),
            decoration: const InputDecoration(labelText: 'Personel'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tarih'),
            subtitle: Text(_fmtDate(date)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
                initialDate: date,
              );
              if (picked != null) setState(() => date = DateUtils.dateOnly(picked));
            },
          ),
          DropdownButtonFormField<RequestType>(
            value: type,
            items: RequestType.values
                .map((e) => DropdownMenuItem(value: e, child: Text(requestTypeLabel(e))))
                .toList(),
            onChanged: (v) => setState(() => type = v!),
            decoration: const InputDecoration(labelText: 'Talep Tipi'),
          ),
          SwitchListTile(
            value: managerApproved,
            onChanged: (v) => setState(() => managerApproved = v),
            title: const Text('Müdür onaylı'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          if (personId != null)
            Text('15 gün içinde talep: ${store.requestsIn15Days(personId!, date)} / ${store.rules.requestLimit15Days}'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (personId == null) return;
              final err = store.canAddRequest(personId!, date, editingId: widget.request?.id);
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                return;
              }
              store.addOrUpdateRequest(StaffRequest(
                id: widget.request?.id ?? store.nextId(),
                personId: personId!,
                date: date,
                type: type,
                managerApproved: managerApproved,
              ));
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}


class FlightsPage extends StatelessWidget {
  const FlightsPage({super.key});


  DateTime? _parseExcelDateLocal(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateUtils.dateOnly(v);
    if (v is num) {
      // Excel serial date (days since 1899-12-30)
      final base = DateTime(1899, 12, 30);
      return DateUtils.dateOnly(base.add(Duration(days: v.toInt())));
    }
    if (v is String) {
      final s = v.trim();
      // Accept dd.MM.yyyy or yyyy-MM-dd
      final m1 = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(s);
      if (m1 != null) {
        final d = int.parse(m1.group(1)!);
        final mo = int.parse(m1.group(2)!);
        final y = int.parse(m1.group(3)!);
        return DateUtils.dateOnly(DateTime(y, mo, d));
      }
      final m2 = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
      if (m2 != null) {
        final y = int.parse(m2.group(1)!);
        final mo = int.parse(m2.group(2)!);
        final d = int.parse(m2.group(3)!);
        return DateUtils.dateOnly(DateTime(y, mo, d));
      }
    }
    return null;
  }

  TimeOfDay? _parseExcelTimeLocal(dynamic v) {
    if (v == null) return null;
    if (v is TimeOfDay) return v;
    if (v is DateTime) return TimeOfDay(hour: v.hour, minute: v.minute);
    if (v is num) {
      // Excel time fraction of day
      final minutes = (v * 24 * 60).round();
      final h = (minutes ~/ 60) % 24;
      final m = minutes % 60;
      return TimeOfDay(hour: h, minute: m);
    }
    if (v is String) {
      final s = v.trim();
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
      if (m != null) {
        final h = int.parse(m.group(1)!);
        final mi = int.parse(m.group(2)!);
        if (h >= 0 && h <= 23 && mi >= 0 && mi <= 59) {
          return TimeOfDay(hour: h, minute: mi);
        }
      }
    }
    return null;
  }

  Future<void> _importFlights(BuildContext context, AppStore store) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya okunamadı.')),
      );
      return;
    }

    try {
      final excel = xl.Excel.decodeBytes(bytes);
      final sheetName = excel.sheets.keys.contains('Sayfa1') ? 'Sayfa1' : excel.sheets.keys.first;
      final sheet = excel.sheets[sheetName]!;
      DateTime? currentDate;

      int imported = 0;
      for (final row in sheet.rows) {
        if (row.isEmpty) continue;

        final aVal = row.length > 0 ? row[0]?.value : null;
        final bVal = row.length > 1 ? row[1]?.value : null;
        final cVal = row.length > 2 ? row[2]?.value : null;
        final dVal = row.length > 3 ? row[3]?.value : null;
        final eVal = row.length > 4 ? row[4]?.value : null;

        // Header line: date in column A (sometimes) or B.
        final dateCandidate = _parseExcelDateLocal(aVal) ?? _parseExcelDateLocal(bVal);
        if (dateCandidate != null) {
          currentDate = dateCandidate;
          continue;
        }

        // Flight rows: A=FlightNo, B=Dest, E=STD (HH:MM)
        final flightNo = (aVal ?? '').toString().trim();
        final dest = (bVal ?? '').toString().trim();

        final std = _parseExcelTimeLocal(eVal);
        if (currentDate != null && flightNo.isNotEmpty && dest.isNotEmpty && std != null) {
          store.addOrUpdateFlight(FlightItem(
            id: store.nextId(),
            date: currentDate,
            flightNo: flightNo.toUpperCase(),
            destination: dest.toUpperCase(),
            std: std,
            sta: null,
          ));
          imported++;
          continue;
        }

        // Some sheets may keep STD in D column; try fallback
        final std2 = std ?? _parseExcelTimeLocal(dVal) ?? _parseExcelTimeLocal(cVal);
        if (currentDate != null && flightNo.isNotEmpty && dest.isNotEmpty && std2 != null) {
          store.addOrUpdateFlight(FlightItem(
            id: store.nextId(),
            date: currentDate,
            flightNo: flightNo.toUpperCase(),
            destination: dest.toUpperCase(),
            std: std2,
            sta: null,
          ));
          imported++;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İçe aktarılan uçuş: $imported')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel okuma hatası: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: store.flights.length,
        itemBuilder: (_, i) {
          final f = store.flights[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.flight_takeoff),
              title: Text('${f.flightNo} • ${f.destination}'),
              subtitle: Text('${_fmtDate(f.date)} • STD ${_fmtTod(f.std)}${f.sta != null ? " • STA ${_fmtTod(f.sta!)}" : ""}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FlightEditorPage(flight: f)),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => store.deleteFlight(f.id),
              ),
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'importFlights',
            onPressed: () => _importFlights(context, store),
            icon: const Icon(Icons.upload_file),
            label: const Text('Excel Yükle'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'addFlight',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FlightEditorPage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Uçuş Ekle'),
          ),
        ],
      ),
    );
  }
}

class FlightEditorPage extends StatefulWidget {
  final FlightItem? flight;
  const FlightEditorPage({super.key, this.flight});

  @override
  State<FlightEditorPage> createState() => _FlightEditorPageState();
}

class _FlightEditorPageState extends State<FlightEditorPage> {
  DateTime date = DateUtils.dateOnly(DateTime.now());
  final flightNoCtl = TextEditingController();
  final destCtl = TextEditingController();
  final stdCtl = TextEditingController(text: '09:00');
  final staCtl = TextEditingController(text: '11:00');

  @override
  void initState() {
    super.initState();
    final f = widget.flight;
    if (f != null) {
      date = DateUtils.dateOnly(f.date);
      flightNoCtl.text = f.flightNo;
      destCtl.text = f.destination;
      stdCtl.text = _fmtTod(f.std);
      staCtl.text = f.sta == null ? '' : _fmtTod(f.sta!);
    }
  }

  @override
  void dispose() {
    flightNoCtl.dispose();
    destCtl.dispose();
    stdCtl.dispose();
    staCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.flight == null ? 'Uçuş Ekle' : 'Uçuş Düzenle')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tarih'),
            subtitle: Text(_fmtDate(date)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
                initialDate: date,
              );
              if (picked != null) setState(() => date = DateUtils.dateOnly(picked));
            },
          ),
          TextField(controller: flightNoCtl, decoration: const InputDecoration(labelText: 'Uçuş No')),
          const SizedBox(height: 8),
          TextField(controller: destCtl, decoration: const InputDecoration(labelText: 'Destinasyon')),
          const SizedBox(height: 8),
          TextField(
  controller: stdCtl,
  decoration: const InputDecoration(
    labelText: 'STD (HH:MM)',
    hintText: '09:30',
  ),
  keyboardType: TextInputType.datetime,
),
const SizedBox(height: 8),
TextField(
  controller: staCtl,
  decoration: const InputDecoration(
    labelText: 'STA (opsiyonel, HH:MM)',
    hintText: '11:15',
  ),
  keyboardType: TextInputType.datetime,
),
const SizedBox(height: 12),

          FilledButton(
            onPressed: () {
              if (flightNoCtl.text.trim().isEmpty || destCtl.text.trim().isEmpty) return;
              final stdParsed = parseHHMM(stdCtl.text.trim());
              if (stdParsed == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('STD formatı HH:MM olmalı')));
                return;
              }
              final staText = staCtl.text.trim();
              final staParsed = staText.isEmpty ? null : parseHHMM(staText);
              if (staText.isNotEmpty && staParsed == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('STA formatı HH:MM olmalı')));
                return;
              }
              store.addOrUpdateFlight(FlightItem(
                id: widget.flight?.id ?? store.nextId(),
                date: date,
                flightNo: flightNoCtl.text.trim().toUpperCase(),
                destination: destCtl.text.trim().toUpperCase(),
                std: stdParsed,
                sta: staParsed,
              ));
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}


class FlightNeedsPage extends StatelessWidget {
  final FlightItem flight;
  const FlightNeedsPage({super.key, required this.flight});

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    final items = store.needsForFlight(flight.id);

    return Scaffold(
      appBar: AppBar(
        title: Text('İhtiyaçlar • ${flight.flightNo}'),
        actions: [
            IconButton(
              tooltip: 'Vardiya öner',
              onPressed: () => store.suggestShiftsForFlight(flight.id),
              icon: const Icon(Icons.schedule),
            ),

          TextButton.icon(
            onPressed: () {
              store.generateNeedsForFlight(flight.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('İhtiyaçlar üretildi')),
              );
            },
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Üret'),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Text('Henüz ihtiyaç yok. Sağ üstten "Üret" ile oluştur.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final n = items[i];
                final tags = <String>[
                  titleLabel(n.requiredTitle),
                  if (n.requiredGender != null) genderLabel(n.requiredGender!),
                  if (n.requiredSkill != null) n.requiredSkill!,
                ];
                return Card(
                  child: ListTile(
                    title: Text(positionLabel(n.position)),
                    subtitle: Text(tags.join(' • ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: n.requiredCount > 0
                              ? () => store.setNeedCount(n.id, n.requiredCount - 1)
                              : null,
                        ),
                        Text(
                          n.requiredCount.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => store.setNeedCount(n.id, n.requiredCount + 1),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}



class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    final r = store.rules;

    Widget rowCounter(String label, int value, void Function(int) setVal,
        {int min = 0, int max = 20}) {
      return Card(
        child: ListTile(
          title: Text(label),
          subtitle: Text('$value'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              onPressed: value > min ? () => setState(() => setVal(value - 1)) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            IconButton(
              onPressed: value < max ? () => setState(() => setVal(value + 1)) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ]),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        rowCounter('15 günde talep limiti', r.requestLimit15Days, (v) {
          r.requestLimit15Days = v;
          store.notifyRulesChanged();
        }),
        rowCounter('Üst üste çalışma günü', r.maxConsecutiveWorkDays, (v) {
          r.maxConsecutiveWorkDays = v;
          store.notifyRulesChanged();
        }, min: 1, max: 15),
        rowCounter('Üst üste 12 saat günü', r.maxConsecutive12hDays, (v) {
          r.maxConsecutive12hDays = v;
          store.notifyRulesChanged();
        }, min: 1, max: 7),
        rowCounter('Üst üste gece günü', r.maxConsecutiveNightDays, (v) {
          r.maxConsecutiveNightDays = v;
          store.notifyRulesChanged();
        }, min: 1, max: 7),
        rowCounter('Min dinlenme saati', r.minRestHoursBetweenShifts, (v) {
          r.minRestHoursBetweenShifts = v;
          store.notifyRulesChanged();
        }, min: 8, max: 16),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: r.extraAirsiderPerShift,
                onChanged: (v) => setState(() {
                  r.extraAirsiderPerShift = v;
                  store.notifyRulesChanged();
                }),
                title: const Text('Her vardiyada +1 ekstra Airsider'),
              ),
              SwitchListTile(
                value: r.alternateExtraAirsiderGender,
                onChanged: (v) => setState(() {
                  r.alternateExtraAirsiderGender = v;
                  store.notifyRulesChanged();
                }),
                title: const Text('Ekstra Airsider cinsiyet dönüşümlü'),
              ),
              ListTile(
                title: const Text('Başlangıç ekstra cinsiyet'),
                trailing: DropdownButton<Gender>(
                  value: r.startExtraAirsiderGender,
                  items: Gender.values
                      .map((g) => DropdownMenuItem(value: g, child: Text(genderLabel(g))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    r.startExtraAirsiderGender = v!;
                    store.notifyRulesChanged();
                  }),
                ),
              ),
              SwitchListTile(
                value: r.gateObserverMust,
                onChanged: (v) => setState(() {
                  r.gateObserverMust = v;
                  store.notifyRulesChanged();
                }),
                title: const Text('Gate Observer MUST'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _fmtTod(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';