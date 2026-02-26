
import 'dart:math';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const GozenApp());

class GozenApp extends StatelessWidget {
  const GozenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppStoreScope(
      store: AppStore(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Gozen Planlama',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const HomePage(),
      ),
    );
  }
}

// ------------------------ MODELS ------------------------

enum TitleType { airsider, interviewer, teamLeader, tarmacTeamLeader }
enum Gender { male, female }

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

class Person {
  final String id;
  String name;

  TitleType title;
  Gender gender;
  Set<String> skills;
  bool active;

  // constraints (minimal v1)
  bool geceYok;
  bool gunduzYok;
  bool sabahYok;
  int maxVardiyaSaat;

  Person({
    required this.id,
    required this.name,
    this.title = TitleType.airsider,
    this.gender = Gender.male,
    Set<String>? skills,
    this.active = true,
    this.geceYok = false,
    this.gunduzYok = false,
    this.sabahYok = false,
    this.maxVardiyaSaat = 12,
  }) : skills = skills ?? <String>{};
}

class FlightItem {
  final String id;

  DateTime date; // date-only (from excel TARİH)
  String iata; // from excel IATA KOD
  String flightNo; // from excel UÇUŞ KODU
  String dest; // from excel DESTINATION
  DateTime stdDateTime; // date + time
  DateTime? oprStartDateTime; // computed from min offset among needs

  DateTime flightDay; // date-only = OPR START day (LOCKED RULE)

  FlightItem({
    required this.id,
    required this.date,
    required this.iata,
    required this.flightNo,
    required this.dest,
    required this.stdDateTime,
    required this.flightDay,
    this.oprStartDateTime,
  });
}

class FlightNeed {
  final String id;
  final String flightId;

  final String position;
  final int requiredCount;

  final TitleType title;
  final Gender? gender;
  final String? skill;

  // operation start offset: how much BEFORE STD
  final Duration offsetBeforeStd;

  FlightNeed({
    required this.id,
    required this.flightId,
    required this.position,
    required this.requiredCount,
    required this.title,
    required this.gender,
    required this.skill,
    required this.offsetBeforeStd,
  });
}

class DailySlot {
  final String id;

  final DateTime day; // date-only = flightDay (OPR START day) for daily position sheet
  final String flightId;
  final String position;
  final int slotIndex; // 1..N
  String? personId;

  DailySlot({
    required this.id,
    required this.day,
    required this.flightId,
    required this.position,
    required this.slotIndex,
    this.personId,
  });
}

class WorkDay {
  final String personId;
  final DateTime day; // date-only, SHIFT DAY = shift start day (locked)
  bool off;
  String shiftCode;
  String shiftStartHHMM;
  String shiftEndHHMM;

  WorkDay({
    required this.personId,
    required this.day,
    required this.off,
    required this.shiftCode,
    required this.shiftStartHHMM,
    required this.shiftEndHHMM,
  });
}

// ------------------------ LOCKED RULES ------------------------

class RulesLocked {
  // Day attribution
  // Flight day = OPR START day (earliest start among needs)
  // Shift day  = shift start day

  // IATA/need rules
  static const bool gateObserverMust = true;

  // Updates locked:
  // XQ & TOM: CHUTE yok
  // OR / X3 / BLX / TB: gate görevleri yok; sadece Ramp/Back/Jetty + Tarmac TL
  // Ramp/Back/Jetty offset: 2:00

  // Planning locks (from our agreement)
  static const int maxFlightsPerPersonPerDay = 4;
  static const int minRestHours = 11;
  static const int maxConsecutive12hDays = 2; // can flex later if requested
  static const int maxConsecutiveNightDays = 2; // can flex later if requested
  static const int maxConsecutiveWorkDays = 7; // locked: no 7+ consecutive
  static const int offTargetAirsiderInterviewer = 3; // per 15 days
  static const int offTargetTL = 4; // per 15 days (locked for TL + Tarmac TL)
}

// ------------------------ STORE ------------------------

class AppStore extends ChangeNotifier {
  final List<Person> persons = [];
  final List<FlightItem> flights = [];
  final List<FlightNeed> needs = [];
  final List<DailySlot> dailySlots = [];

  // 15-day work program (shift day based)
  final List<WorkDay> workProgram = [];

  int _id = 0;
  String nextId() => (++_id).toString();

  DateTime? get minFlightDay => flights.isEmpty
      ? null
      : flights.map((f) => f.flightDay).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get maxFlightDay => flights.isEmpty
      ? null
      : flights.map((f) => f.flightDay).reduce((a, b) => a.isAfter(b) ? a : b);

  // ---------- ONE CLICK ----------
  Future<Map<String, int>> oneClickBuild() async {
    final pCount = await importPersonnelFromTemplateOrList();
    final fCount = await importFlightsFromProgram();
    if (fCount > 0) {
      generateWorkProgramForFlightRange();
      autoAssignAllDays(); // uses workProgram
    }
    return {'personel': pCount, 'ucus': fCount, 'slot': dailySlots.length};
  }

  // ---------- PERSONNEL IMPORT ----------
  /// Supports:
  /// - "Kopya 11 ... ÇALIŞMA PROGRAMI.xlsx" (name-only)
  /// - Excel personnel list (A AdSoyad, B Title, C Gender, D Skills...) if user provides
  Future<int> importPersonnelFromTemplateOrList() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return 0;

    final bytes = res.files.single.bytes;
    if (bytes == null) return 0;

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.firstOrNull;
    if (sheet == null) return 0;

    // Try detect personnel-list header (Title/Gender/Skills)
    final headerRow = _findHeaderRow(sheet, ['AD', 'SOY', 'TITLE']);
    final maxCols = _maxCols(sheet);

    final incoming = <Person>[];

    if (headerRow != null) {
      // Personnel list style
      for (int r = headerRow + 1; r < sheet.maxRows; r++) {
        final name = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value).trim();
        if (name.isEmpty) continue;
        final titleStr = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value).trim();
        final genderStr = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value).trim();
        final skillsStr = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value).trim();

        incoming.add(Person(
          id: nextId(),
          name: name,
          title: _parseTitle(titleStr) ?? TitleType.airsider,
          gender: _parseGender(genderStr) ?? _guessGenderFromName(name) ?? Gender.male,
          skills: skillsStr.isEmpty ? {} : skillsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(),
        ));
      }
    } else {
      // Work program template style: scrape names
      final names = <String>{};
      for (int r = 0; r < min(140, sheet.maxRows); r++) {
        for (int c = 0; c < min(4, maxCols); c++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
          final s = _cellToString(cell.value).trim();
          if (s.isEmpty) continue;
          final up = s.toUpperCase();
          if (up.contains('SAAT') || up.contains('VARDIYA') || up.contains('TARİH') || up.contains('TARIH')) continue;
          if (s.length < 5) continue;
          if (!s.contains(' ')) continue;
          if (RegExp(r'\d').hasMatch(s)) continue;
          names.add(s);
        }
      }

      // Better than "all male airsider": guess gender by name and alternate if unknown
      int alt = 0;
      for (final n in names) {
        final g = _guessGenderFromName(n);
        incoming.add(Person(id: nextId(), name: n.trim(), title: TitleType.airsider, gender: g ?? ((alt++ % 2 == 0) ? Gender.male : Gender.female)));
      }
    }

    if (incoming.isEmpty) return 0;

    final byName = {for (final p in persons) p.name.trim().toLowerCase(): p};
    int added = 0;
    for (final p in incoming) {
      final k = p.name.trim().toLowerCase();
      if (k.isEmpty) continue;
      if (byName.containsKey(k)) continue;
      persons.add(p);
      byName[k] = p;
      added++;
    }
    notifyListeners();
    return added;
  }

  Gender? _guessGenderFromName(String fullName) {
    final first = fullName.trim().split(RegExp(r'\s+')).first.toLowerCase();
    // small but effective TR set
    const female = {
      'ayşe','fatma','emel','elif','zeynep','esra','kübra','kubra','meryem','hatice','sultan','şeyma','seyma',
      'melike','gül','gul','gizem','eda','buse','tuğba','tugba','selin','derya','seda','naz','cansu','aslı','asli'
    };
    const male = {
      'ahmet','mehmet','ali','mustafa','osman','hasan','hüseyin','huseyin','ibrahim','ismail','murat','volkan','serkan',
      'emre','burak','can','tolga','barış','baris','ferhat','kemal','omer','ömer','yusuf'
    };
    if (female.contains(first)) return Gender.female;
    if (male.contains(first)) return Gender.male;
    return null;
  }

  TitleType? _parseTitle(String s) {
    final u = s.trim().toUpperCase();
    if (u.contains('AIR')) return TitleType.airsider;
    if (u.contains('INTER')) return TitleType.interviewer;
    if (u.contains('TARMAC')) return TitleType.tarmacTeamLeader;
    if (u.contains('TEAM')) return TitleType.teamLeader;
    return null;
  }

  Gender? _parseGender(String s) {
    final u = s.trim().toUpperCase();
    if (u.startsWith('E') || u.contains('MALE') || u.contains('ERKEK')) return Gender.male;
    if (u.startsWith('K') || u.contains('FEMALE') || u.contains('KADIN')) return Gender.female;
    return null;
  }

  // ---------- FLIGHT IMPORT (TABLE FORMAT) ----------
  Future<int> importFlightsFromProgram() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return 0;

    final bytes = res.files.single.bytes;
    if (bytes == null) return 0;

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.firstOrNull;
    if (sheet == null) return 0;

    final headerRow = _findHeaderRow(sheet, ['TAR', 'IATA', 'UÇUŞ', 'DEST', 'STD']) ??
        _findHeaderRow(sheet, ['TARIH', 'IATA', 'UCUS', 'DESTINATION', 'STD']);
    if (headerRow == null) return 0;

    final idx = _mapHeaderColumns(sheet, headerRow);

    final cDate = idx['TARİH'] ?? 0;
    final cIata = idx['IATA'] ?? 1;
    final cFlight = idx['UÇUŞ'] ?? 2;
    final cDest = idx['DESTINATION'] ?? 3;
    final cStd = idx['STD'] ?? (idx['DESTINATION'] != null ? idx['DESTINATION']! + 1 : 6);

    final imported = <FlightItem>[];

    for (int r = headerRow + 1; r < sheet.maxRows; r++) {
      final rawDate = sheet.cell(CellIndex.indexByColumnRow(columnIndex: cDate, rowIndex: r)).value;
      final date = _parseExcelDate(rawDate);
      if (date == null) continue;

      final iata = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: cIata, rowIndex: r)).value)
          .trim()
          .toUpperCase();
      final flightNo = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: cFlight, rowIndex: r)).value)
          .trim()
          .toUpperCase()
          .replaceAll(' ', '');
      final dest = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: cDest, rowIndex: r)).value)
          .trim()
          .toUpperCase();

      if (flightNo.isEmpty || dest.isEmpty) continue;

      final stdCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: cStd, rowIndex: r)).value;
      final stdTod = _parseExcelTime(stdCell);
      if (stdTod == null) continue;

      final stdDt = DateTime(date.year, date.month, date.day, stdTod.hour, stdTod.minute);

      imported.add(FlightItem(
        id: nextId(),
        date: date,
        iata: iata.isEmpty ? _iataFromFlightNo(flightNo) : iata,
        flightNo: flightNo,
        dest: dest,
        stdDateTime: stdDt,
        flightDay: DateUtils.dateOnly(stdDt), // temp; recalculated below
      ));
    }

    if (imported.isEmpty) return 0;

    flights
      ..clear()
      ..addAll(imported);

    // Generate needs (IATA rules) and compute OPR START day
    _regenerateNeeds();
    _recomputeFlightDaysByOprStart();
    _regenerateDailySlots();

    // sort flights by flightDay then std
    flights.sort((a, b) {
      final d = a.flightDay.compareTo(b.flightDay);
      if (d != 0) return d;
      return a.stdDateTime.compareTo(b.stdDateTime);
    });

    notifyListeners();
    return imported.length;
  }

  void clearAll() {
    persons.clear();
    flights.clear();
    needs.clear();
    dailySlots.clear();
    workProgram.clear();
    notifyListeners();
  }

  void refresh() => notifyListeners();

  // ---------- NEEDS + DAYS ----------
  void _regenerateNeeds() {
    needs.clear();
    for (final f in flights) {
      needs.addAll(_generateNeedsForFlight(f));
    }
  }

  void _recomputeFlightDaysByOprStart() {
    for (final f in flights) {
      final ns = needs.where((n) => n.flightId == f.id).toList();
      if (ns.isEmpty) {
        f.oprStartDateTime = f.stdDateTime;
        f.flightDay = DateUtils.dateOnly(f.stdDateTime);
        continue;
      }
      DateTime earliest = f.stdDateTime;
      for (final n in ns) {
        final opr = f.stdDateTime.subtract(n.offsetBeforeStd);
        if (opr.isBefore(earliest)) earliest = opr;
      }
      f.oprStartDateTime = earliest;
      f.flightDay = DateUtils.dateOnly(earliest); // LOCKED RULE
    }
  }

  void _regenerateDailySlots() {
    dailySlots.clear();
    for (final f in flights) {
      final ns = needs.where((n) => n.flightId == f.id);
      for (final n in ns) {
        for (int i = 1; i <= n.requiredCount; i++) {
          dailySlots.add(DailySlot(
            id: nextId(),
            day: f.flightDay,
            flightId: f.id,
            position: n.position,
            slotIndex: i,
          ));
        }
      }
    }
  }

  List<FlightNeed> _generateNeedsForFlight(FlightItem f) {
    final iata = f.iata;
    FlightNeed mk({
      required String position,
      required int count,
      required TitleType title,
      Gender? gender,
      String? skill,
      required Duration offset,
    }) {
      return FlightNeed(
        id: nextId(),
        flightId: f.id,
        position: position,
        requiredCount: count,
        title: title,
        gender: gender,
        skill: skill,
        offsetBeforeStd: offset,
      );
    }

    // OFFSETS (locked)
    const gateOffset = Duration(hours: 1, minutes: 45);
    const tlOffset = Duration(hours: 1, minutes: 15);
    const chuteOffset = Duration(hours: 3);
    const airsideOffset = Duration(hours: 2); // UPDATED

    final out = <FlightNeed>[];

    // No gate group
    final noGateIatas = {'OR', 'X3', 'BLX', 'TB'};
    if (noGateIatas.contains(iata)) {
      out.add(mk(position: 'RAMP', count: 1, title: TitleType.airsider, gender: Gender.male, offset: airsideOffset));
      out.add(mk(position: 'BACK', count: 1, title: TitleType.airsider, gender: Gender.female, offset: airsideOffset));
      out.add(mk(position: 'JETTY', count: 1, title: TitleType.airsider, gender: Gender.male, offset: airsideOffset));
      out.add(mk(position: 'TARMAC TEAM LEADER', count: 1, title: TitleType.tarmacTeamLeader, offset: tlOffset));
      return out;
    }

    void addGateCore({bool tlDocCheck = false}) {
      out.add(mk(
        position: 'GATE TEAM LEADER',
        count: 1,
        title: TitleType.teamLeader,
        skill: tlDocCheck ? 'Doc. Check' : null,
        offset: tlOffset,
      ));
      out.add(mk(position: 'GATE PAX ID', count: 1, title: TitleType.interviewer, offset: gateOffset));
      out.add(mk(position: 'GATE SEARCH 1', count: 1, title: TitleType.airsider, gender: Gender.male, offset: gateOffset));
      out.add(mk(position: 'GATE SEARCH 2', count: 1, title: TitleType.airsider, gender: Gender.female, offset: gateOffset));
      if (RulesLocked.gateObserverMust) {
        out.add(mk(position: 'GATE OBSERVER', count: 1, title: TitleType.airsider, offset: gateOffset));
      }
    }

    void addAirsideCore({bool includeJetty = true}) {
      out.add(mk(position: 'RAMP', count: 1, title: TitleType.airsider, gender: Gender.male, offset: airsideOffset));
      out.add(mk(position: 'BACK', count: 1, title: TitleType.airsider, gender: Gender.female, offset: airsideOffset));
      if (includeJetty) {
        out.add(mk(position: 'JETTY', count: 1, title: TitleType.airsider, gender: Gender.male, offset: airsideOffset));
      }
      out.add(mk(position: 'TARMAC TEAM LEADER', count: 1, title: TitleType.tarmacTeamLeader, offset: tlOffset));
    }

    void addChute() => out.add(mk(position: 'CHUTE', count: 1, title: TitleType.airsider, offset: chuteOffset));

    final noChuteIatas = {'XQ', 'TOM'};
    final hasChute = !noChuteIatas.contains(iata);

    switch (iata) {
      case 'BA':
        addGateCore(tlDocCheck: true);
        addAirsideCore(includeJetty: true);
        if (hasChute) addChute();
        out.add(mk(position: 'BAGGAGE ESCORT', count: 1, title: TitleType.airsider, gender: Gender.female, offset: gateOffset));
        return out;

      case 'LS':
      case 'TK':
      case 'FHY':
        addGateCore();
        addAirsideCore(includeJetty: true);
        if (hasChute) addChute();
        if (iata == 'TK') {
          out.add(mk(position: 'BAGGAGE ESCORT', count: 1, title: TitleType.airsider, gender: Gender.female, offset: gateOffset));
        }
        return out;

      case 'XQ':
      case 'TOM':
        addGateCore();
        addAirsideCore(includeJetty: iata == 'TOM');
        return out;

      default:
        addGateCore();
        return out;
    }
  }

  // ---------- WORK PROGRAM (SHIFT) ----------
  /// After flights imported, create a shift plan for the flight date range.
  /// Minimal v1: assigns OFF to meet target and avoid >7 consecutive work days.
  /// ShiftCode derived from earliest OPR start hour among that day's flights (flightDay basis).
  void generateWorkProgramForFlightRange() {
    workProgram.clear();
    if (persons.isEmpty || flights.isEmpty) return;

    final start = minFlightDay!;
    final end = maxFlightDay!;
    final days = _daysBetweenInclusive(start, end);

    // Determine off targets per person
    int targetOff(Person p) {
      if (p.title == TitleType.teamLeader || p.title == TitleType.tarmacTeamLeader) {
        return RulesLocked.offTargetTL;
      }
      return RulesLocked.offTargetAirsiderInterviewer;
    }

    // Create initial: everyone works every day with a shift based on that day
    for (final p in persons.where((p) => p.active)) {
      for (final d in days) {
        final sh = _suggestShiftForDay(d);
        workProgram.add(WorkDay(
          personId: p.id,
          day: d,
          off: false,
          shiftCode: sh.code,
          shiftStartHHMM: sh.start,
          shiftEndHHMM: sh.end,
        ));
      }
    }

    // Apply offs to meet target + prevent >7 consecutive work days
    for (final p in persons.where((p) => p.active)) {
      final target = targetOff(p);
      final personDays = workProgram.where((w) => w.personId == p.id).toList()
        ..sort((a, b) => a.day.compareTo(b.day));

      // First, enforce "no 7+ consecutive": if 7 consecutive work, make 7th off.
      int consec = 0;
      for (final w in personDays) {
        if (!w.off) {
          consec++;
          if (consec >= RulesLocked.maxConsecutiveWorkDays) {
            w.off = true;
            w.shiftCode = 'OFF';
            w.shiftStartHHMM = '';
            w.shiftEndHHMM = '';
            consec = 0;
          }
        } else {
          consec = 0;
        }
      }

      // Then meet targetOff by sprinkling offs (prefer days with fewer flights)
      int currentOff = personDays.where((w) => w.off).length;
      if (currentOff < target) {
        final daysByLoad = personDays
            .where((w) => !w.off)
            .map((w) => MapEntry(w, _flightLoadForDay(w.day)))
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (final e in daysByLoad) {
          if (currentOff >= target) break;
          e.key.off = true;
          e.key.shiftCode = 'OFF';
          e.key.shiftStartHHMM = '';
          e.key.shiftEndHHMM = '';
          currentOff++;
        }
      }
    }

    notifyListeners();
  }

  // ---------- DAILY POSITIONING (AUTO ASSIGN) ----------
  /// Auto-assigns people to daily slots using workProgram availability.
  /// Priority: gender > skill > rest (rest simplified as max 4 flights/day here)
  void autoAssignAllDays() {
    // clear previous assignments
    for (final s in dailySlots) {
      s.personId = null;
    }

    final daySet = dailySlots.map((s) => s.day).toSet().toList()..sort();
    for (final d in daySet) {
      _autoAssignForDay(d);
    }
    notifyListeners();
  }

  void _autoAssignForDay(DateTime day) {
    final slots = dailySlots.where((s) => DateUtils.isSameDay(s.day, day)).toList();
    if (slots.isEmpty) return;

    // available persons: active + not off on that day
    final available = persons.where((p) => p.active && !_isOff(p.id, day)).toList();

    // track per person flight count
    final flightsOfDay = flights.where((f) => DateUtils.isSameDay(f.flightDay, day)).toList();
    final flightIds = flightsOfDay.map((f) => f.id).toSet();
    final counts = <String, int>{for (final p in available) p.id: 0};

    // sort slots deterministic
    slots.sort((a, b) {
      final fa = flights.firstWhere((f) => f.id == a.flightId, orElse: () => flights.first);
      final fb = flights.firstWhere((f) => f.id == b.flightId, orElse: () => flights.first);
      final d1 = fa.stdDateTime.compareTo(fb.stdDateTime);
      if (d1 != 0) return d1;
      final p = a.position.compareTo(b.position);
      if (p != 0) return p;
      return a.slotIndex.compareTo(b.slotIndex);
    });

    for (final slot in slots) {
      if (!flightIds.contains(slot.flightId)) continue;
      final need = _needForSlot(slot);
      if (need == null) continue;

      // candidates: title match
      var cand = available.where((p) => p.title == need.title).toList();

      // gender priority
      if (need.gender != null) {
        final exact = cand.where((p) => p.gender == need.gender).toList();
        if (exact.isNotEmpty) cand = exact;
      }

      // skill priority
      if (need.skill != null && need.skill!.isNotEmpty) {
        final exact = cand.where((p) => p.skills.contains(need.skill)).toList();
        if (exact.isNotEmpty) cand = exact;
      }

      // capacity: max 4 flights/day
      cand = cand.where((p) => (counts[p.id] ?? 0) < RulesLocked.maxFlightsPerPersonPerDay).toList();
      if (cand.isEmpty) continue;

      // pick least-loaded
      cand.sort((a, b) => (counts[a.id] ?? 0).compareTo(counts[b.id] ?? 0));
      final chosen = cand.first;
      slot.personId = chosen.id;
      counts[chosen.id] = (counts[chosen.id] ?? 0) + 1;
    }
  }

  bool _isOff(String personId, DateTime day) {
    final wd = workProgram.where((w) => w.personId == personId && DateUtils.isSameDay(w.day, day)).firstOrNull;
    return wd?.off ?? false;
  }

  FlightNeed? _needForSlot(DailySlot s) {
    // match by flightId + position
    return needs.where((n) => n.flightId == s.flightId && n.position == s.position).firstOrNull;
  }

  // ---------- EXPORT (WHATSAPP SHARE) ----------
  Future<void> exportWorkProgramViaWhatsApp() async {
    if (workProgram.isEmpty) return;

    final start = minFlightDay ?? DateUtils.dateOnly(DateTime.now());
    final end = maxFlightDay ?? start;
    final days = _daysBetweenInclusive(start, end);

    final wb = Excel.createExcel();
    final sheet = wb['CalismaProgrami'];
    wb.delete('Sheet1');

    // header row
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Personel');
    for (int i = 0; i < days.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: 0)).value = TextCellValue(_fmtDate(days[i]));
    }

    final active = persons.where((p) => p.active).toList();
    for (int r = 0; r < active.length; r++) {
      final p = active[r];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(p.name);
      for (int c = 0; c < days.length; c++) {
        final d = days[c];
        final wd = workProgram.where((w) => w.personId == p.id && DateUtils.isSameDay(w.day, d)).firstOrNull;
        final val = (wd == null) ? '' : (wd.off ? 'OFF' : wd.shiftCode);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c + 1, rowIndex: r + 1)).value = TextCellValue(val);
      }
    }

    // bottom "Saatler" row
    final hoursRow = active.length + 2;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: hoursRow)).value = TextCellValue('Saatler');
    for (int c = 0; c < days.length; c++) {
      final sh = _suggestShiftForDay(days[c]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c + 1, rowIndex: hoursRow)).value =
          TextCellValue('${sh.code} ${sh.start}-${sh.end}');
    }

    final bytes = wb.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/calisma_programi.xlsx');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles([XFile(file.path)], text: 'Çalışma Programı');
  }

  Future<void> exportDailyPositionsViaWhatsApp(DateTime day) async {
    final slots = dailySlots.where((s) => DateUtils.isSameDay(s.day, day)).toList();
    if (slots.isEmpty) return;

    final wb = Excel.createExcel();
    final sheet = wb['Pozisyonlar'];
    wb.delete('Sheet1');

    // header
    final headers = ['Uçuş', 'Dest', 'STD', 'Pozisyon', 'Slot', 'Personel'];
    for (int c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value = TextCellValue(headers[c]);
    }

    slots.sort((a, b) {
      final fa = flights.firstWhere((f) => f.id == a.flightId, orElse: () => flights.first);
      final fb = flights.firstWhere((f) => f.id == b.flightId, orElse: () => flights.first);
      final d1 = fa.stdDateTime.compareTo(fb.stdDateTime);
      if (d1 != 0) return d1;
      final p = a.position.compareTo(b.position);
      if (p != 0) return p;
      return a.slotIndex.compareTo(b.slotIndex);
    });

    for (int r = 0; r < slots.length; r++) {
      final s = slots[r];
      final f = flights.firstWhere((x) => x.id == s.flightId);
      final p = persons.where((pp) => pp.id == s.personId).firstOrNull;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(f.flightNo);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(f.dest);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_fmtHHMM(f.stdDateTime));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(s.position);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(s.slotIndex.toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(p?.name ?? '');
    }

    final bytes = wb.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/gunluk_pozisyon_${_fmtDateFile(day)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles([XFile(file.path)], text: 'Günlük Pozisyon (${_fmtDate(day)})');
  }

  // ---------- misc ----------
  String _iataFromFlightNo(String s) {
    final up = s.toUpperCase().replaceAll(' ', '');
    final m = RegExp(r'^[A-Z]{2,3}').firstMatch(up);
    return m?.group(0) ?? up;
  }

  int _flightLoadForDay(DateTime d) => flights.where((f) => DateUtils.isSameDay(f.flightDay, d)).length;

  List<DateTime> _daysBetweenInclusive(DateTime start, DateTime end) {
    final s = DateUtils.dateOnly(start);
    final e = DateUtils.dateOnly(end);
    final out = <DateTime>[];
    for (DateTime d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      out.add(d);
    }
    return out;
  }

  _ShiftSuggestion _suggestShiftForDay(DateTime d) {
    // derive from earliest OPR start hour among that day's flights; else default V1 09:00-17:00
    final dayFlights = flights.where((f) => DateUtils.isSameDay(f.flightDay, d)).toList();
    if (dayFlights.isEmpty) return _ShiftSuggestion('V1', '09:00', '17:00');
    DateTime earliest = dayFlights.first.oprStartDateTime ?? dayFlights.first.stdDateTime;
    for (final f in dayFlights) {
      final t = f.oprStartDateTime ?? f.stdDateTime;
      if (t.isBefore(earliest)) earliest = t;
    }
    final h = earliest.hour;
    if (h < 9) return _ShiftSuggestion('V', '06:00', '14:00');
    if (h < 15) return _ShiftSuggestion('V1', '09:00', '17:00');
    if (h < 20) return _ShiftSuggestion('V3', '14:00', '22:00');
    return _ShiftSuggestion('V7', '22:00', '06:00');
  }
}

class _ShiftSuggestion {
  final String code;
  final String start;
  final String end;
  _ShiftSuggestion(this.code, this.start, this.end);
}

// ------------------------ EXCEL HELPERS ------------------------

int _maxCols(Sheet s) {
  int maxC = 0;
  for (final row in s.rows) {
    if (row.length > maxC) maxC = row.length;
  }
  return maxC == 0 ? 1 : maxC;
}

String _cellToString(Object? v) {
  if (v == null) return '';
  if (v is TextCellValue) return v.value.toString();
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) return v.value.toString();
  if (v is BoolCellValue) return v.value.toString();
  if (v is DateCellValue) return v.asDateTimeLocal().toIso8601String();
  if (v is TimeCellValue) return v.asDuration().toString();
  return v.toString();
}

DateTime? _parseExcelDate(Object? v) {
  if (v == null) return null;
  if (v is DateCellValue) return DateUtils.dateOnly(v.asDateTimeLocal());
  if (v is TextCellValue) {
    final s = v.value.toString().trim();
    final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$').firstMatch(s);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      return DateUtils.dateOnly(DateTime(y, mo, d));
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) return DateUtils.dateOnly(dt);
  }
  if (v is IntCellValue) {
    final base = DateTime(1899, 12, 30);
    return DateUtils.dateOnly(base.add(Duration(days: v.value)));
  }
  if (v is DoubleCellValue) {
    final base = DateTime(1899, 12, 30);
    return DateUtils.dateOnly(base.add(Duration(days: v.value.floor())));
  }
  return null;
}

TimeOfDay? _parseExcelTime(Object? v) {
  if (v == null) return null;

  if (v is DateCellValue) {
    final dt = v.asDateTimeLocal();
    return TimeOfDay(hour: dt.hour, minute: dt.minute);
  }

  if (v is TimeCellValue) {
    final d = v.asDuration();
    final totalMinutes = d.inMinutes;
    return TimeOfDay(hour: (totalMinutes ~/ 60) % 24, minute: totalMinutes % 60);
  }

  if (v is DoubleCellValue) {
    final frac = v.value;
    if (frac.isNaN) return null;
    final totalMinutes = (frac * 24 * 60).round();
    return TimeOfDay(hour: (totalMinutes ~/ 60) % 24, minute: totalMinutes % 60);
  }

  if (v is IntCellValue) {
    final n = v.value;
    return TimeOfDay(hour: (n ~/ 60) % 24, minute: n % 60);
  }

  final s = _cellToString(v).trim();
  if (s.isEmpty) return null;

  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h < 0 || h > 23 || mi < 0 || mi > 59) return null;
    return TimeOfDay(hour: h, minute: mi);
  }

  return null;
}

int? _findHeaderRow(Sheet sheet, List<String> needles) {
  final maxCols = _maxCols(sheet);
  for (int r = 0; r < min(30, sheet.maxRows); r++) {
    final rowStr = <String>[];
    for (int c = 0; c < maxCols; c++) {
      final s = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value)
          .trim()
          .toUpperCase();
      if (s.isNotEmpty) rowStr.add(s);
    }
    final joined = rowStr.join(' | ');
    bool ok = true;
    for (final n in needles) {
      if (!joined.contains(n.toUpperCase())) {
        ok = false;
        break;
      }
    }
    if (ok) return r;
  }
  return null;
}

Map<String, int> _mapHeaderColumns(Sheet sheet, int headerRow) {
  final maxCols = _maxCols(sheet);
  final map = <String, int>{};

  for (int c = 0; c < maxCols; c++) {
    final s = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRow)).value)
        .trim()
        .toUpperCase();

    if (s.contains('TARİH') || s.contains('TARIH')) map['TARİH'] = c;
    if (s.contains('IATA')) map['IATA'] = c;
    if (s.contains('UÇUŞ') || s.contains('UCUS')) map['UÇUŞ'] = c;
    if (s.contains('DESTINATION') || s.contains('DEST')) map['DESTINATION'] = c;
    if (s == 'STD' || s.contains('STD')) map['STD'] = c;
  }
  return map;
}

// ------------------------ APP SHELL ------------------------

class AppStoreScope extends InheritedNotifier<AppStore> {
  const AppStoreScope({super.key, required AppStore store, required Widget child})
      : super(notifier: store, child: child);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStoreScope>()!.notifier!;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int idx = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardPage(),
      PersonsPage(),
      FlightsPage(),
      WorkProgramPage(),
      PositionsPage(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Gozen Planlama (APK / Local)')),
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Personel'),
          NavigationDestination(icon: Icon(Icons.flight), label: 'Uçuş'),
          NavigationDestination(icon: Icon(Icons.view_week), label: 'Çalışma'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'Pozisyon'),
        ],
      ),
    );
  }
}

// ------------------------ DASHBOARD ------------------------

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  int _countTitle(AppStore s, TitleType t, {Gender? g}) => s.persons.where((p) {
        return p.active && p.title == t && (g == null || p.gender == g);
      }).length;

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tek Seferde (Personel + Uçuş + Çalışma + Pozisyon)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  final res = await store.oneClickBuild();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Personel: ${res['personel']} • Uçuş: ${res['ucus']} • Slot: ${res['slot']}'),
                  ));
                },
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Tek Seferde Üret'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kilit Kurallar:\n'
                '• Uçuş günü = OPR START günü (STD değil)\n'
                '• Vardiya günü = vardiya başlangıç günü\n'
                '• XQ & TOM: CHUTE yok\n'
                '• OR/X3/BLX/TB: gate yok (Ramp/Back/Jetty + Tarmac TL)\n'
                '• Ramp/Back/Jetty offset = 2:00\n'
                '• Plan: max 4 uçuş/kişi/gün, min 11s dinlenme, 7+ gün üst üste yok, 15 günde off hedefleri',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            title: const Text('Özet'),
            subtitle: Text(
              'Erkek Airsider: ${_countTitle(store, TitleType.airsider, g: Gender.male)} • '
              'Kadın Airsider: ${_countTitle(store, TitleType.airsider, g: Gender.female)}\n'
              'Interviewer: ${_countTitle(store, TitleType.interviewer)} • '
              'Tarmac TL: ${_countTitle(store, TitleType.tarmacTeamLeader)} • '
              'Team Leader: ${_countTitle(store, TitleType.teamLeader)}\n'
              'Uçuş: ${store.flights.length} • Slot: ${store.dailySlots.length} • Çalışma satırı: ${store.workProgram.length}',
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------ PERSONS ------------------------

class PersonsPage extends StatelessWidget {
  const PersonsPage({super.key});

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
              title: Text(p.name),
              subtitle: Text('${titleLabel(p.title)} • ${genderLabel(p.gender)}${p.skills.isEmpty ? "" : " • ${p.skills.join(", ")}"}'),
              trailing: Switch(
                value: p.active,
                onChanged: (v) {
                  p.active = v;
                  store.refresh();
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final count = await store.importPersonnelFromTemplateOrList();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İçe aktarılan personel: $count')));
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Personel Excel Yükle'),
      ),
    );
  }
}

// ------------------------ FLIGHTS ------------------------

class FlightsPage extends StatelessWidget {
  const FlightsPage({super.key});

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
              title: Text('${f.flightNo} • ${f.dest} (${f.iata})'),
              subtitle: Text(
                'STD: ${_fmtDT(f.stdDateTime)}\n'
                'OPR START: ${f.oprStartDateTime == null ? "-" : _fmtDT(f.oprStartDateTime!)}\n'
                'Uçuş günü: ${_fmtDate(f.flightDay)}',
              ),
            ),
          );
        },
      ),
      floatingActionButton: Wrap(
        spacing: 8,
        children: [
          FloatingActionButton.extended(
            onPressed: () async {
              final n = await store.importFlightsFromProgram();
              if (!context.mounted) return;
              store.generateWorkProgramForFlightRange();
              store.autoAssignAllDays();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İçe aktarılan uçuş: $n')));
            },
            icon: const Icon(Icons.upload),
            label: const Text('Uçuş Excel Yükle'),
          ),
          FloatingActionButton.extended(
            onPressed: () => store.clearAll(),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Temizle'),
          ),
        ],
      ),
    );
  }
}

// ------------------------ WORK PROGRAM ------------------------

class WorkProgramPage extends StatefulWidget {
  const WorkProgramPage({super.key});

  @override
  State<WorkProgramPage> createState() => _WorkProgramPageState();
}

class _WorkProgramPageState extends State<WorkProgramPage> {
  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);

    final start = store.minFlightDay;
    final end = store.maxFlightDay;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            title: const Text('Çalışma Programı'),
            subtitle: Text(start == null ? '-' : '${_fmtDate(start)} → ${_fmtDate(end!)}'),
            trailing: Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    store.generateWorkProgramForFlightRange();
                    store.autoAssignAllDays();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Çalışma programı üretildi.')));
                  },
                  child: const Text('Üret'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await store.exportWorkProgramViaWhatsApp();
                  },
                  child: const Text('WhatsApp Export'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (store.workProgram.isEmpty) const Text('Henüz çalışma programı yok. Uçuş yükleyip Üret yap.'),
        if (store.workProgram.isNotEmpty)
          ...store.persons.where((p) => p.active).map((p) {
            final days = store.workProgram.where((w) => w.personId == p.id).toList()
              ..sort((a, b) => a.day.compareTo(b.day));
            final preview = days.take(7).map((w) => w.off ? 'OFF' : w.shiftCode).join(' ');
            return Card(
              child: ListTile(
                title: Text(p.name),
                subtitle: Text(preview),
              ),
            );
          }),
      ],
    );
  }
}

// ------------------------ POSITIONS ------------------------

class PositionsPage extends StatefulWidget {
  const PositionsPage({super.key});
  @override
  State<PositionsPage> createState() => _PositionsPageState();
}

class _PositionsPageState extends State<PositionsPage> {
  DateTime day = DateUtils.dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);

    final todayFlights = store.flights.where((f) => DateUtils.isSameDay(f.flightDay, day)).toList();
    final todaySlots = store.dailySlots.where((s) => DateUtils.isSameDay(s.day, day)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            title: const Text('Gün seç (Pozisyonlandırma)'),
            subtitle: Text(_fmtDate(day)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2025),
                lastDate: DateTime(2035),
                initialDate: day,
              );
              if (picked != null) setState(() => day = DateUtils.dateOnly(picked));
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            title: const Text('Özet'),
            subtitle: Text('Uçuş: ${todayFlights.length} • Slot: ${todaySlots.length}'),
            trailing: Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    store.autoAssignAllDays();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Oto atama yapıldı.')));
                  },
                  child: const Text('Oto Ata'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await store.exportDailyPositionsViaWhatsApp(day);
                  },
                  child: const Text('WhatsApp Export'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...todayFlights.map((f) {
          final fSlots = todaySlots.where((s) => s.flightId == f.id).toList();
          final byPos = <String, int>{};
          for (final s in fSlots) {
            byPos[s.position] = (byPos[s.position] ?? 0) + 1;
          }
          final posText = byPos.entries.map((e) => '${e.key} (${e.value})').join(' • ');
          return Card(
            child: ListTile(
              title: Text('${f.flightNo} • ${f.dest}'),
              subtitle: Text(posText.isEmpty ? '-' : posText),
            ),
          );
        }),
      ],
    );
  }
}

// ------------------------ FORMAT HELPERS ------------------------

String _fmtDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

String _fmtDateFile(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

String _fmtDT(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year} $hh:$mi';
}

String _fmtHHMM(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$hh:$mi';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
