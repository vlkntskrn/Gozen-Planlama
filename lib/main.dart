
import 'dart:async';
import 'dart:math';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  DateTime rawDay;
  String flightNo;
  String dest;
  DateTime stdDateTime;
  DateTime? staDateTime;

  DateTime flightDay;

  FlightItem({
    required this.id,
    required this.rawDay,
    required this.flightNo,
    required this.dest,
    required this.stdDateTime,
    this.staDateTime,
    required this.flightDay,
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
  final Duration offsetBeforeStd;

  String shiftCode;
  DateTime shiftStart;
  DateTime shiftEnd;

  FlightNeed({
    required this.id,
    required this.flightId,
    required this.position,
    required this.requiredCount,
    required this.title,
    required this.gender,
    required this.skill,
    required this.offsetBeforeStd,
    required this.shiftCode,
    required this.shiftStart,
    required this.shiftEnd,
  });
}

class DailySlot {
  final String id;
  final DateTime day; // flightDay
  final String flightId;
  final String position;
  final int slotIndex;
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

class RulesLocked {
  static const bool gateObserverMust = true;
}

class AppStore extends ChangeNotifier {
  final List<Person> persons = [];
  final List<FlightItem> flights = [];
  final List<FlightNeed> needs = [];
  final List<DailySlot> dailySlots = [];

  int _id = 0;
  String nextId() => (++_id).toString();

  void upsertPersons(Iterable<Person> items) {
    final byName = {for (final p in persons) p.name.trim().toLowerCase(): p};
    for (final p in items) {
      final key = p.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (byName.containsKey(key)) continue;
      persons.add(p);
      byName[key] = p;
    }
    notifyListeners();
  }

  void addFlights(Iterable<FlightItem> items) {
    flights.addAll(items);
    flights.sort((a, b) {
      final d = a.flightDay.compareTo(b.flightDay);
      if (d != 0) return d;
      return a.stdDateTime.compareTo(b.stdDateTime);
    });
    notifyListeners();
  }

  void clearAllFlights() {
    flights.clear();
    needs.clear();
    dailySlots.clear();
    notifyListeners();
  }

  void regenerateNeedsAndDailySlotsForAllFlights() {
    needs.clear();
    dailySlots.clear();

    for (final f in flights) {
      final generated = _generateNeedsForFlight(f);
      needs.addAll(generated);

      for (final n in generated) {
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
    notifyListeners();
  }

  List<FlightNeed> _generateNeedsForFlight(FlightItem f) {
    final iata = _iataFromFlightNo(f.flightNo);
    final std = f.stdDateTime;

    FlightNeed mk({
      required String position,
      required int count,
      required TitleType title,
      Gender? gender,
      String? skill,
      required Duration offset,
    }) {
      final oprStart = std.subtract(offset);
      final shiftStart = DateTime(oprStart.year, oprStart.month, oprStart.day, oprStart.hour);
      final shiftEnd = shiftStart.add(const Duration(hours: 8));
      final shiftCode = _suggestShiftCode(shiftStart);
      return FlightNeed(
        id: nextId(),
        flightId: f.id,
        position: position,
        requiredCount: count,
        title: title,
        gender: gender,
        skill: skill,
        offsetBeforeStd: offset,
        shiftCode: shiftCode,
        shiftStart: shiftStart,
        shiftEnd: shiftEnd,
      );
    }

    const gateOffset = Duration(hours: 1, minutes: 45);
    const tlOffset = Duration(hours: 1, minutes: 15);
    const chuteOffset = Duration(hours: 3);
    const airsideOffset = Duration(hours: 2);

    final out = <FlightNeed>[];

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

    void addChute() {
      out.add(mk(position: 'CHUTE', count: 1, title: TitleType.airsider, offset: chuteOffset));
    }

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

  void recomputeFlightDaysByOprStart() {
    for (final f in flights) {
      final ns = needs.where((n) => n.flightId == f.id).toList();
      if (ns.isEmpty) continue;
      DateTime earliest = f.stdDateTime;
      for (final n in ns) {
        final opr = f.stdDateTime.subtract(n.offsetBeforeStd);
        if (opr.isBefore(earliest)) earliest = opr;
      }
      f.flightDay = DateUtils.dateOnly(earliest);
    }
  }

  Future<int> importPersonnelFromWorkProgramTemplate() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return 0;
    final bytes = res.files.single.bytes;
    if (bytes == null) return 0;

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet == null) return 0;

    final names = <String>{};

    for (int r = 0; r < min(80, sheet.maxRows); r++) {
      for (int c = 0; c < min(3, _sheetMaxCols(sheet)); c++) {
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

    final personsToAdd = names.map((n) => Person(id: nextId(), name: n)).toList();
    upsertPersons(personsToAdd);
    return personsToAdd.length;
  }

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
    final sheet = excel.tables.values.first;
    if (sheet == null) return 0;

    DateTime? currentDay;
    DateTime? lastGoodDay;

    final imported = <FlightItem>[];

    for (int r = 0; r < sheet.maxRows; r++) {
      final a = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value).trim();
      final parsedHeaderDay = _tryParseDayHeader(a);
      if (parsedHeaderDay != null) {
        currentDay = parsedHeaderDay;
        lastGoodDay = parsedHeaderDay;
        continue;
      }

      final rowHasStdHeader = _rowContains(sheet, r, 'STD');
      final rowHasChuteHeader = _rowContains(sheet, r, 'CHUTE') || _rowContains(sheet, r, 'Chute');

      if ((a.contains('#REF') || a.isEmpty) && (rowHasStdHeader || rowHasChuteHeader) && lastGoodDay != null) {
        currentDay = DateUtils.dateOnly(lastGoodDay!.add(const Duration(days: 1)));
        lastGoodDay = currentDay;
        continue;
      }

      if (currentDay == null) continue;

      final flightNo = _normalizeFlightNo(a);
      if (flightNo == null) continue;

      final dest = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value).trim().toUpperCase();

      final stdCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value ??
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value ??
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value;

      final stdTod = _parseExcelTime(stdCell);
      if (stdTod == null) continue;

      final stdDt = DateTime(currentDay.year, currentDay.month, currentDay.day, stdTod.hour, stdTod.minute);

      imported.add(FlightItem(
        id: nextId(),
        rawDay: currentDay,
        flightNo: flightNo,
        dest: dest,
        stdDateTime: stdDt,
        flightDay: DateUtils.dateOnly(stdDt),
      ));
    }

    if (imported.isEmpty) return 0;

    addFlights(imported);
    regenerateNeedsAndDailySlotsForAllFlights();
    recomputeFlightDaysByOprStart();

    dailySlots.clear();
    for (final f in flights) {
      final fsNeeds = needs.where((n) => n.flightId == f.id);
      for (final n in fsNeeds) {
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
    notifyListeners();

    return imported.length;
  }

  Future<Map<String, int>> oneClickBuild() async {
    final pCount = await importPersonnelFromWorkProgramTemplate();
    final fCount = await importFlightsFromProgram();
    final slotCount = dailySlots.length;
    return {'personel': pCount, 'ucus': fCount, 'slot': slotCount};
  }

  String _iataFromFlightNo(String s) {
    final up = s.toUpperCase().replaceAll(' ', '');
    final m = RegExp(r'^[A-Z]{2,3}').firstMatch(up);
    return m?.group(0) ?? up;
  }

  String _suggestShiftCode(DateTime shiftStart) {
    final h = shiftStart.hour;
    if (h < 9) return 'V';
    if (h < 15) return 'V1';
    if (h < 20) return 'V3';
    return 'V7';
  }
}


int _sheetMaxCols(Sheet sheet) {
  int m = 0;
  for (final row in sheet.rows) {
    if (row.length > m) m = row.length;
  }
  return m;
}

String _cellToString(Object? v) {
  if (v == null) return '';
  if (v is TextCellValue) return v.value.toString();
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) return v.value.toString();
  if (v is BoolCellValue) return v.value.toString();
  if (v is DateCellValue) return v.asDateTimeLocal().toString();
  if (v is TimeCellValue) return v.asDuration().toString();
  return v.toString();
}

DateTime? _tryParseDayHeader(String a) {
  final s = a.trim();
  if (s.isEmpty) return null;
  if (s.contains('#REF')) return null;
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
  return null;
}

String? _normalizeFlightNo(String raw) {
  final s = raw.trim().toUpperCase();
  if (s.isEmpty) return null;
  final compact = s.replaceAll(' ', '');
  if (!RegExp(r'^[A-Z0-9]{4,7}$').hasMatch(compact)) return null;
  if (!RegExp(r'^[A-Z]{1,3}').hasMatch(compact)) return null;
  return compact;
}

bool _rowContains(Sheet sheet, int row, String needle) {
  for (int c = 0; c < min(10, _sheetMaxCols(sheet)); c++) {
    final s = _cellToString(sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value).toUpperCase();
    if (s.contains(needle.toUpperCase())) return true;
  }
  return false;
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
    final h = (totalMinutes ~/ 60) % 24;
    final m = totalMinutes % 60;
    return TimeOfDay(hour: h, minute: m);
  }

  if (v is DoubleCellValue) {
    final frac = v.value;
    if (frac.isNaN) return null;
    final totalMinutes = (frac * 24 * 60).round();
    final h = (totalMinutes ~/ 60) % 24;
    final m = totalMinutes % 60;
    return TimeOfDay(hour: h, minute: m);
  }

  if (v is IntCellValue) {
    final n = v.value;
    final h = (n ~/ 60) % 24;
    final m = n % 60;
    return TimeOfDay(hour: h, minute: m);
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

  final m2 = RegExp(r'^(\d{1,2})[.](\d{2})$').firstMatch(s);
  if (m2 != null) {
    final h = int.parse(m2.group(1)!);
    final mi = int.parse(m2.group(2)!);
    if (h < 0 || h > 23 || mi < 0 || mi > 59) return null;
    return TimeOfDay(hour: h, minute: mi);
  }

  return null;
}

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
      PositionsPage(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Gozen Planlama (One-Click)')),
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Personel'),
          NavigationDestination(icon: Icon(Icons.flight), label: 'Uçuş'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'Pozisyon'),
        ],
      ),
    );
  }
}

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
              const Text('Tek Seferde (Personel + Uçuş + Pozisyon)', style: TextStyle(fontWeight: FontWeight.bold)),
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
                '• Gate Observer MUST\n'
                '• XQ & TOM: CHUTE yok\n'
                '• OR/X3/BLX/TB: gate yok (Ramp/Back/Jetty + Tarmac TL)\n'
                '• Ramp/Back/Jetty offset = 2:00',
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
              'Uçuş: ${store.flights.length} • Slot: ${store.dailySlots.length}',
            ),
          ),
        ),
      ],
    );
  }
}

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
              subtitle: Text('${titleLabel(p.title)} • ${genderLabel(p.gender)}'),
              trailing: Switch(
                value: p.active,
                onChanged: (v) {
                  p.active = v;
                  store.notifyListeners();
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final count = await store.importPersonnelFromWorkProgramTemplate();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İçe aktarılan personel: $count')));
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Personel Excel Yükle'),
      ),
    );
  }
}

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
              title: Text('${f.flightNo} • ${f.dest}'),
              subtitle: Text(
                'STD: ${_fmtDT(f.stdDateTime)}\n'
                'Uçuş günü (OPR START): ${_fmtDate(f.flightDay)}',
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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İçe aktarılan uçuş: $n')));
            },
            icon: const Icon(Icons.upload),
            label: const Text('Uçuş Excel Yükle'),
          ),
          FloatingActionButton.extended(
            onPressed: () => store.clearAllFlights(),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Temizle'),
          ),
        ],
      ),
    );
  }
}

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
            trailing: FilledButton(
              onPressed: () {
                store.notifyListeners();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pozisyonlar hazır.')));
              },
              child: const Text('Pozisyonlandır'),
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

String _fmtDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

String _fmtDT(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year} $hh:$mi';
}
