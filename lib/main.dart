import 'dart:ui';
import 'package:flutter/material.dart';

void main() {
  runApp(const OpsPlannerApp());
}

/// Airport Ops Planner (V1 Skeleton)
///
/// Included:
/// - In-memory store (no backend yet)
/// - Personnel pool management (add/edit/deactivate)
/// - Per-person constraints (no night/day/morning, max shift hours)
/// - Requests (OFF / MORNING / DAY / EVENING / NIGHT) + manager approved flag
/// - Rule toggles:
///   - Min rest between shifts = 11h (locked)
///   - Max 2 consecutive 12h shifts (default; can be overridden with employee request)
///   - Max 2 consecutive night shifts (default; can be overridden with employee request)
///   - Extra +1 Airsider buffer for every shift (gender alternates by shift)
///   - Gate Observer rule set to MUST
///
/// Not included (placeholder buttons exist):
/// - Excel import/export implementation (needs pubspec + packages)
/// - Actual 15-day planning engine + flight assignment engine
class OpsPlannerApp extends StatelessWidget {
  const OpsPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ops Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final Store store = Store.seed();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(store: store),
      PersonnelPage(store: store),
      RulesPage(store: store),
      RequestsPage(store: store),
      ImportExportPage(store: store),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(index)),
        actions: [
          IconButton(
            tooltip: 'About',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AboutDialog(
                applicationName: 'Ops Planner',
                applicationVersion: 'V1 Skeleton',
                applicationLegalese:
                    'Prototype UI for personnel pool, constraints & requests.',
              ),
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Personel'),
          NavigationDestination(icon: Icon(Icons.rule_folder_outlined), label: 'Kurallar'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), label: 'Talepler'),
          NavigationDestination(icon: Icon(Icons.file_present_outlined), label: 'Import/Export'),
        ],
      ),
    );
  }

  String _titleFor(int i) {
    switch (i) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Personel';
      case 2:
        return 'Kurallar';
      case 3:
        return 'Talepler';
      case 4:
        return 'Import / Export';
      default:
        return 'Ops Planner';
    }
  }
}

/* =========================
   Domain models
========================= */

enum Gender { erkek, kadin, diger }

enum ShiftPref { off, sabah, gunduz, aksam, gece }

class Person {
  Person({
    required this.id,
    required this.fullName,
    required this.title,
    required this.gender,
    required this.skills,
    this.active = true,
    this.appRole = 'OCC',
  });

  final String id;
  String fullName;
  String title; // e.g. Airsider, Interviewer, Team Leader, Tarmac TL
  Gender gender;
  List<String> skills; // editable tags
  bool active;
  String appRole; // Admin/OCC/Supervisor/Agent (kept as string for now)
}

class PersonConstraints {
  PersonConstraints({
    required this.personId,
    this.geceYok = false,
    this.gunduzYok = false,
    this.sabahYok = false,
    this.maxVardiyaSaat = 12,
    this.note = '',
  });

  final String personId;
  bool geceYok;
  bool gunduzYok;
  bool sabahYok;
  int maxVardiyaSaat;
  String note;
}

class PersonRequest {
  PersonRequest({
    required this.id,
    required this.personId,
    required this.date,
    required this.pref,
    this.managerApproved = false,
    this.note = '',
  });

  final String id;
  final String personId;
  DateTime date;
  ShiftPref pref;
  bool managerApproved;
  String note;
}

class PlanningRules {
  PlanningRules({
    this.minRestHours = 11,
    this.maxConsecutive12h = 2,
    this.maxConsecutiveNight = 2,
    this.allowOverrideWithRequest = true,
    this.requestQuotaPer15Days = 5,
    this.extraAirsiderPerShift = 1,
    this.alternateExtraAirsiderGender = true,
    this.startExtraAirsiderGender = Gender.erkek,
    this.gateObserverMust = true,
  });

  int minRestHours; // Excel kuralı: 11 saat
  int maxConsecutive12h;
  int maxConsecutiveNight;
  bool allowOverrideWithRequest;
  int requestQuotaPer15Days;

  // No-show risk buffer
  int extraAirsiderPerShift; // user rule: every shift +1
  bool alternateExtraAirsiderGender; // male/female alternating by shift
  Gender startExtraAirsiderGender; // first shift's extra gender

  // Position requirement rule
  bool gateObserverMust; // changed from "if available" to MUST
}

/* =========================
   In-memory store
========================= */

class Store extends ChangeNotifier {
  Store({
    required this.people,
    required this.constraintsByPerson,
    required this.requests,
    required this.rules,
  });

  final List<Person> people;
  final Map<String, PersonConstraints> constraintsByPerson;
  final List<PersonRequest> requests;
  final PlanningRules rules;

  static Store seed() {
    final p1 = Person(
      id: _id(),
      fullName: 'Ali Yılmaz',
      title: 'Airsider',
      gender: Gender.erkek,
      skills: ['AS', 'Gate'],
    );
    final p2 = Person(
      id: _id(),
      fullName: 'Ayşe Demir',
      title: 'Interviewer',
      gender: Gender.kadin,
      skills: ['INT', 'APIS'],
    );
    return Store(
      people: [p1, p2],
      constraintsByPerson: {
        p1.id: PersonConstraints(personId: p1.id, geceYok: false, maxVardiyaSaat: 12),
        p2.id: PersonConstraints(personId: p2.id, geceYok: true, maxVardiyaSaat: 10),
      },
      requests: [],
      rules: PlanningRules(),
    );
  }

  PersonConstraints constraintsOf(String personId) {
    return constraintsByPerson[personId] ??= PersonConstraints(personId: personId);
  }

  void addPerson(Person p) {
    people.add(p);
    constraintsByPerson.putIfAbsent(p.id, () => PersonConstraints(personId: p.id));
    notifyListeners();
  }

  void updatePerson(Person p) {
    final idx = people.indexWhere((x) => x.id == p.id);
    if (idx >= 0) {
      people[idx] = p;
      notifyListeners();
    }
  }

  void toggleActive(String personId, bool active) {
    final p = people.firstWhere((x) => x.id == personId);
    p.active = active;
    notifyListeners();
  }

  void saveConstraints(PersonConstraints c) {
    constraintsByPerson[c.personId] = c;
    notifyListeners();
  }

  void addRequest(PersonRequest r) {
    requests.add(r);
    notifyListeners();
  }

  void updateRequest(PersonRequest r) {
    final idx = requests.indexWhere((x) => x.id == r.id);
    if (idx >= 0) {
      requests[idx] = r;
      notifyListeners();
    }
  }

  void deleteRequest(String id) {
    requests.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  int requestCountInWindow(String personId, DateTime endInclusive) {
    final start = endInclusive.subtract(const Duration(days: 14));
    return requests
        .where((r) => r.personId == personId)
        .where((r) => !r.date.isBefore(start) && !r.date.isAfter(endInclusive))
        .length;
  }

  static String _id() => DateTime.now().microsecondsSinceEpoch.toString();
}

/* =========================
   Pages
========================= */

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.store});
  final Store store;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late DateTime selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final activeCount = widget.store.people.where((p) => p.active).length;
    final total = widget.store.people.length;

    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final store = widget.store;
        final r = store.rules;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Card(
              title: 'Özet',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Personel: $activeCount aktif / $total toplam'),
                  const SizedBox(height: 8),
                  Text('Min dinlenme: ${widget.store.rules.minRestHours} saat'),
                  Text('Ekstra Airsider/shift: ${widget.store.rules.extraAirsiderPerShift}'),
                  Text("Gate Observer: ${widget.store.rules.gateObserverMust ? 'MUST' : 'Opsiyonel'}"),
                  Text('12s ardışık limit: ${widget.store.rules.maxConsecutive12h} (talep ile esnetilebilir: ${widget.store.rules.allowOverrideWithRequest ? "Evet" : "Hayır"})'),
                  Text('Gece ardışık limit: ${widget.store.rules.maxConsecutiveNight} (talep ile esnetilebilir: ${widget.store.rules.allowOverrideWithRequest ? "Evet" : "Hayır"})'),
                  const Divider(height: 24),
                  _IntStepper(
                    label: 'Vardiya başı ekstra Airsider',
                    value: r.extraAirsiderPerShift,
                    min: 0,
                    max: 3,
                    onChanged: (v) {
                      r.extraAirsiderPerShift = v;
                      store.notifyListeners();
                    },
                    helperText: 'No-show risk buffer için her vardiyaya fazladan Airsider.',
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ekstra Airsider cinsiyetini dönüşümlü planla'),
                    subtitle: const Text('Bir vardiyada erkek ekstra ise sonraki vardiyada kadın ekstra planlanır.'),
                    value: r.alternateExtraAirsiderGender,
                    onChanged: (v) {
                      r.alternateExtraAirsiderGender = v;
                      store.notifyListeners();
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Gender>(
                    value: r.startExtraAirsiderGender,
                    decoration: const InputDecoration(
                      labelText: 'İlk vardiya ekstra Airsider cinsiyeti',
                      border: OutlineInputBorder(),
                    ),
                    items: Gender.values
                        .map(
                          (g) => DropdownMenuItem(
                            value: g,
                            child: Text(g == Gender.erkek ? 'Erkek' : 'Kadın'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      r.startExtraAirsiderGender = v;
                      store.notifyListeners();
                    },
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gate Observer zorunlu'),
                    subtitle: const Text('Önceki kural: if available. Yeni kural: MUST.'),
                    value: r.gateObserverMust,
                    onChanged: (v) {
                      r.gateObserverMust = v;
                      store.notifyListeners();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              title: 'Tarih',
              child: Row(
                children: [
                  Text(_fmtDate(selected)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2025, 1, 1),
                        lastDate: DateTime(2030, 12, 31),
                        initialDate: selected,
                      );
                      if (picked != null) setState(() => selected = picked);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Seç'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              title: 'Plan Motoru (placeholder)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bu sürümde plan motoru yok; sadece UI + veri modeli var.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _toast(context, 'Plan motoru sonraki adım.'),
                    child: const Text('15 Günlük Plan Üret'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => _toast(context, 'Günlük pozisyonlandırma sonraki adım.'),
                    child: const Text('Günlük Pozisyonlandır'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class PersonnelPage extends StatelessWidget {
  const PersonnelPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final people = [...store.people]..sort((a, b) => a.fullName.compareTo(b.fullName));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Personel Havuzu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                FilledButton.icon(
                  onPressed: () async {
                    final created = await Navigator.of(context).push<Person?>(
                      MaterialPageRoute(builder: (_) => PersonEditorPage(store: store)),
                    );
                    if (created != null) store.addPerson(created);
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Ekle'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final p in people) ...[
              _PersonTile(store: store, person: p),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.store, required this.person});
  final Store store;
  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = store.constraintsOf(person.id);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(person.fullName.isNotEmpty ? person.fullName.trim()[0] : '?')),
        title: Text(person.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title: ${person.title} • Gender: ${_genderLabel(person.gender)} • ${person.active ? "Aktif" : "Pasif"}'),
            Text('Skills: ${person.skills.isEmpty ? "-" : person.skills.join(", ")}'),
            Text('Kısıtlar: ${_constraintsLabel(c)}'),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                final updated = await Navigator.of(context).push<Person?>(
                  MaterialPageRoute(builder: (_) => PersonEditorPage(store: store, existing: person)),
                );
                if (updated != null) store.updatePerson(updated);
                break;
              case 'constraints':
                final updatedC = await Navigator.of(context).push<PersonConstraints?>(
                  MaterialPageRoute(builder: (_) => ConstraintsEditorPage(store: store, person: person)),
                );
                if (updatedC != null) store.saveConstraints(updatedC);
                break;
              case 'toggle':
                store.toggleActive(person.id, !person.active);
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
            const PopupMenuItem(value: 'constraints', child: Text('Kısıtlar')),
            PopupMenuItem(value: 'toggle', child: Text(person.active ? 'Pasif yap' : 'Aktif yap')),
          ],
        ),
      ),
    );
  }
}

class RulesPage extends StatelessWidget {
  const RulesPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final r = store.rules;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Card(
              title: 'Kilit Kurallar',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('• Öncelik: Cinsiyet > Skill > Dinlenme'),
                  SizedBox(height: 6),
                  Text('• 12 saat vardiya: ardışık max 2 gün (talep ile esnetilebilir)'),
                  Text('• Gece vardiya: ardışık max 2 gün (talep ile esnetilebilir)'),
                  Text('• Min dinlenme: 11 saat'),
                  Text('• Her vardiya +1 ekstra Airsider (no-show buffer)'),
                  Text('• Ekstra Airsider cinsiyeti vardiya bazlı dönüşümlü'),
                  Text('• Gate Observer: MUST (zorunlu)'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              title: 'Parametreler',
              child: Column(
                children: [
                  _IntStepper(
                    label: 'Min dinlenme (saat)',
                    value: r.minRestHours,
                    min: 8,
                    max: 16,
                    onChanged: (v) {
                      r.minRestHours = v;
                      store.notifyListeners();
                    },
                    helperText: 'Excel kuralında 11 saat. Şimdilik düzenlenebilir.',
                  ),
                  const Divider(height: 24),
                  _IntStepper(
                    label: '12s ardışık limit',
                    value: r.maxConsecutive12h,
                    min: 1,
                    max: 5,
                    onChanged: (v) {
                      r.maxConsecutive12h = v;
                      store.notifyListeners();
                    },
                  ),
                  const Divider(height: 24),
                  _IntStepper(
                    label: 'Gece ardışık limit',
                    value: r.maxConsecutiveNight,
                    min: 1,
                    max: 5,
                    onChanged: (v) {
                      r.maxConsecutiveNight = v;
                      store.notifyListeners();
                    },
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Talep varsa esnet'),
                    subtitle: const Text('Personel talebi/manager onayı varsa ardışık limitler esneyebilir.'),
                    value: r.allowOverrideWithRequest,
                    onChanged: (v) {
                      r.allowOverrideWithRequest = v;
                      store.notifyListeners();
                    },
                  ),
                  const Divider(height: 24),
                  _IntStepper(
                    label: '15 günde talep hakkı',
                    value: r.requestQuotaPer15Days,
                    min: 0,
                    max: 15,
                    onChanged: (v) {
                      r.requestQuotaPer15Days = v;
                      store.notifyListeners();
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final people = store.people.where((p) => p.active).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
        final reqs = [...store.requests]..sort((a, b) => b.date.compareTo(a.date));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Talepler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                FilledButton.icon(
                  onPressed: people.isEmpty
                      ? null
                      : () async {
                          final created = await Navigator.of(context).push<PersonRequest?>(
                            MaterialPageRoute(builder: (_) => RequestEditorPage(store: store)),
                          );
                          if (created != null) store.addRequest(created);
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Talep Ekle'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (reqs.isEmpty)
              const _EmptyHint(text: 'Henüz talep yok.'),
            for (final r in reqs) ...[
              _RequestTile(store: store, request: r),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.store, required this.request});
  final Store store;
  final PersonRequest request;

  @override
  Widget build(BuildContext context) {
    final p = store.people.firstWhere((x) => x.id == request.personId, orElse: () => Person(id: 'x', fullName: 'Silinmiş', title: '-', gender: Gender.diger, skills: []));
    final quota = store.rules.requestQuotaPer15Days;
    final used = store.requestCountInWindow(request.personId, request.date);

    return Card(
      child: ListTile(
        title: Text('${p.fullName} • ${_prefLabel(request.pref)}'),
        subtitle: Text('${_fmtDate(request.date)} • Onay: ${request.managerApproved ? "Evet" : "Hayır"} • Puan: $used/$quota'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                final updated = await Navigator.of(context).push<PersonRequest?>(
                  MaterialPageRoute(builder: (_) => RequestEditorPage(store: store, existing: request)),
                );
                if (updated != null) store.updateRequest(updated);
                break;
              case 'toggle':
                store.updateRequest(PersonRequest(
                  id: request.id,
                  personId: request.personId,
                  date: request.date,
                  pref: request.pref,
                  managerApproved: !request.managerApproved,
                  note: request.note,
                ));
                break;
              case 'delete':
                store.deleteRequest(request.id);
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Düzenle')),
            PopupMenuItem(value: 'toggle', child: Text('Onay değiştir')),
            PopupMenuItem(value: 'delete', child: Text('Sil')),
          ],
        ),
      ),
    );
  }
}

class ImportExportPage extends StatelessWidget {
  const ImportExportPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          title: 'Excel Import (placeholder)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Uçuş Excel yükleme burada olacak (file picker + parser).'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _toast(context, 'Import: pubspec + paketler sonraki adım.'),
                child: const Text('Uçuş Excel Yükle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Excel Export (placeholder)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('2 çıktı: (1) Personel vardiya listesi (yayın) (2) Uçuş bazlı görevlendirme formatı.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _toast(context, 'Export: pubspec + excel writer sonraki adım.'),
                child: const Text('Personel Vardiya Excel Export'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => _toast(context, 'Export: pubspec + excel writer sonraki adım.'),
                child: const Text('Uçuş Görevlendirme Excel Export'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Not: Değişiklik durumunda minimum değişiklik + sarı highlight mantığı plan motoru ile birlikte gelecek.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* =========================
   Editors
========================= */

class PersonEditorPage extends StatefulWidget {
  const PersonEditorPage({super.key, required this.store, this.existing});
  final Store store;
  final Person? existing;

  @override
  State<PersonEditorPage> createState() => _PersonEditorPageState();
}

class _PersonEditorPageState extends State<PersonEditorPage> {
  late final TextEditingController nameCtl;
  late final TextEditingController titleCtl;
  late final TextEditingController roleCtl;
  late Gender gender;
  late bool active;
  late List<String> skills;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    nameCtl = TextEditingController(text: p?.fullName ?? '');
    titleCtl = TextEditingController(text: p?.title ?? '');
    roleCtl = TextEditingController(text: p?.appRole ?? 'OCC');
    gender = p?.gender ?? Gender.diger;
    active = p?.active ?? true;
    skills = [...(p?.skills ?? <String>[])];
  }

  @override
  void dispose() {
    nameCtl.dispose();
    titleCtl.dispose();
    roleCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Personel Düzenle' : 'Personel Ekle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameCtl,
            decoration: const InputDecoration(labelText: 'Ad Soyad'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleCtl,
            decoration: const InputDecoration(labelText: 'Title (Airsider/Interviewer/TL...)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: roleCtl,
            decoration: const InputDecoration(labelText: 'App Role (Admin/OCC/Supervisor/Agent)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Gender>(
            value: gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: Gender.erkek, child: Text('Erkek')),
              DropdownMenuItem(value: Gender.kadin, child: Text('Kadın')),
              DropdownMenuItem(value: Gender.diger, child: Text('Diğer')),
            ],
            onChanged: (v) => setState(() => gender = v ?? Gender.diger),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktif'),
            value: active,
            onChanged: (v) => setState(() => active = v),
          ),
          const SizedBox(height: 12),
          _SkillEditor(
            skills: skills,
            onChanged: (v) => setState(() => skills = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              if (name.isEmpty) {
                _toast(context, 'Ad Soyad boş olamaz.');
                return;
              }
              final title = titleCtl.text.trim().isEmpty ? '-' : titleCtl.text.trim();
              final role = roleCtl.text.trim().isEmpty ? 'OCC' : roleCtl.text.trim();
              final id = widget.existing?.id ?? Store._id();
              final p = Person(
                id: id,
                fullName: name,
                title: title,
                gender: gender,
                skills: skills,
                active: active,
                appRole: role,
              );
              Navigator.of(context).pop(p);
            },
            child: Text(isEdit ? 'Kaydet' : 'Ekle'),
          ),
        ],
      ),
    );
  }
}

class ConstraintsEditorPage extends StatefulWidget {
  const ConstraintsEditorPage({super.key, required this.store, required this.person});
  final Store store;
  final Person person;

  @override
  State<ConstraintsEditorPage> createState() => _ConstraintsEditorPageState();
}

class _ConstraintsEditorPageState extends State<ConstraintsEditorPage> {
  late bool geceYok;
  late bool gunduzYok;
  late bool sabahYok;
  late int maxSaat;
  late final TextEditingController noteCtl;

  @override
  void initState() {
    super.initState();
    final c = widget.store.constraintsOf(widget.person.id);
    geceYok = c.geceYok;
    gunduzYok = c.gunduzYok;
    sabahYok = c.sabahYok;
    maxSaat = c.maxVardiyaSaat;
    noteCtl = TextEditingController(text: c.note);
  }

  @override
  void dispose() {
    noteCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Kısıtlar • ${widget.person.fullName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gece yok'),
            value: geceYok,
            onChanged: (v) => setState(() => geceYok = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gündüz yok'),
            value: gunduzYok,
            onChanged: (v) => setState(() => gunduzYok = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sabah yok'),
            value: sabahYok,
            onChanged: (v) => setState(() => sabahYok = v),
          ),
          const SizedBox(height: 12),
          _IntStepper(
            label: 'Maks vardiya süresi (saat)',
            value: maxSaat,
            min: 4,
            max: 12,
            onChanged: (v) => setState(() => maxSaat = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Not',
              hintText: 'Örn: hamile / süt izinli / sağlık kısıtı ...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final c = PersonConstraints(
                personId: widget.person.id,
                geceYok: geceYok,
                gunduzYok: gunduzYok,
                sabahYok: sabahYok,
                maxVardiyaSaat: maxSaat,
                note: noteCtl.text.trim(),
              );
              Navigator.of(context).pop(c);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}

class RequestEditorPage extends StatefulWidget {
  const RequestEditorPage({super.key, required this.store, this.existing});
  final Store store;
  final PersonRequest? existing;

  @override
  State<RequestEditorPage> createState() => _RequestEditorPageState();
}

class _RequestEditorPageState extends State<RequestEditorPage> {
  late String personId;
  late DateTime date;
  late ShiftPref pref;
  late bool managerApproved;
  late final TextEditingController noteCtl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final firstActive = widget.store.people.firstWhere((p) => p.active, orElse: () => widget.store.people.first);
    personId = e?.personId ?? firstActive.id;
    date = e?.date ?? DateTime.now();
    pref = e?.pref ?? ShiftPref.off;
    managerApproved = e?.managerApproved ?? false;
    noteCtl = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    noteCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final people = widget.store.people.where((p) => p.active).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));

    final used = widget.store.requestCountInWindow(personId, date);
    final quota = widget.store.rules.requestQuotaPer15Days;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Talep Düzenle' : 'Talep Ekle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: personId,
            decoration: const InputDecoration(labelText: 'Personel'),
            items: [
              for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.fullName)),
            ],
            onChanged: (v) => setState(() => personId = v ?? personId),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tarih'),
            subtitle: Text(_fmtDate(date)),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2025, 1, 1),
                  lastDate: DateTime(2030, 12, 31),
                  initialDate: date,
                );
                if (picked != null) setState(() => date = picked);
              },
              child: const Text('Seç'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ShiftPref>(
            value: pref,
            decoration: const InputDecoration(labelText: 'Talep Tipi'),
            items: const [
              DropdownMenuItem(value: ShiftPref.off, child: Text('OFF')),
              DropdownMenuItem(value: ShiftPref.sabah, child: Text('SABAH')),
              DropdownMenuItem(value: ShiftPref.gunduz, child: Text('GÜNDÜZ')),
              DropdownMenuItem(value: ShiftPref.aksam, child: Text('AKŞAM')),
              DropdownMenuItem(value: ShiftPref.gece, child: Text('GECE')),
            ],
            onChanged: (v) => setState(() => pref = v ?? pref),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Müdür onaylı'),
            subtitle: Text('15 günde talep puanı: $used/$quota'),
            value: managerApproved,
            onChanged: (v) => setState(() => managerApproved = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Açıklama',
              hintText: 'Örn: 2 gün gece talebi / özel durum ...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              // Soft gate: show warning if over quota (still allow save)
              final finalUsed = widget.store.requestCountInWindow(personId, date);
              if (!isEdit && finalUsed >= quota) {
                _toast(context, 'Uyarı: 15 gün içinde talep hakkı dolu ($finalUsed/$quota). Yine de kaydedildi.');
              }
              final id = widget.existing?.id ?? Store._id();
              Navigator.of(context).pop(
                PersonRequest(
                  id: id,
                  personId: personId,
                  date: date,
                  pref: pref,
                  managerApproved: managerApproved,
                  note: noteCtl.text.trim(),
                ),
              );
            },
            child: Text(isEdit ? 'Kaydet' : 'Ekle'),
          ),
        ],
      ),
    );
  }
}

/* =========================
   Widgets / helpers
========================= */

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}

class _IntStepper extends StatelessWidget {
  const _IntStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            IconButton(
              onPressed: value <= min ? null : () => onChanged(value - 1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$value', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            IconButton(
              onPressed: value >= max ? null : () => onChanged(value + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(helperText!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _SkillEditor extends StatefulWidget {
  const _SkillEditor({required this.skills, required this.onChanged});
  final List<String> skills;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends State<_SkillEditor> {
  late List<String> skills;
  final TextEditingController ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    skills = [...widget.skills];
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Skills',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in skills)
                InputChip(
                  label: Text(s),
                  onDeleted: () {
                    setState(() => skills.remove(s));
                    widget.onChanged([...skills]);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctl,
                  decoration: const InputDecoration(
                    labelText: 'Skill ekle',
                    hintText: 'Örn: APIS, CHUTE, RAMP...',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () {
                  final v = ctl.text.trim();
                  if (v.isEmpty) return;
                  if (!skills.contains(v)) {
                    setState(() => skills.add(v));
                    widget.onChanged([...skills]);
                  }
                  ctl.clear();
                },
                child: const Text('Ekle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

String _genderLabel(Gender g) {
  switch (g) {
    case Gender.erkek:
      return 'Erkek';
    case Gender.kadin:
      return 'Kadın';
    case Gender.diger:
      return 'Diğer';
  }
}

String _prefLabel(ShiftPref p) {
  switch (p) {
    case ShiftPref.off:
      return 'OFF';
    case ShiftPref.sabah:
      return 'SABAH';
    case ShiftPref.gunduz:
      return 'GÜNDÜZ';
    case ShiftPref.aksam:
      return 'AKŞAM';
    case ShiftPref.gece:
      return 'GECE';
  }
}

String _constraintsLabel(PersonConstraints c) {
  final parts = <String>[];
  if (c.sabahYok) parts.add('Sabah yok');
  if (c.gunduzYok) parts.add('Gündüz yok');
  if (c.geceYok) parts.add('Gece yok');
  parts.add('Max ${c.maxVardiyaSaat}h');
  return parts.join(' • ');
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg)),
  );
}
