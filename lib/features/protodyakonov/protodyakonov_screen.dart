import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../deformation/lithotype_db.dart';

/// Одна из 5 навесок внутри образца
class ProtoSubsample {
  double massG; // Масса навески (40..60 г)
  int dropsN;   // Число сбрасываний гири на этой навеске

  ProtoSubsample({
    this.massG = 50.0,
    this.dropsN = 5,
  });

  Map<String, dynamic> toJson() => {
        'massG': massG,
        'dropsN': dropsN,
      };

  factory ProtoSubsample.fromJson(Map<String, dynamic> json) => ProtoSubsample(
        massG: (json['massG'] as num?)?.toDouble() ?? 50.0,
        dropsN: (json['dropsN'] as num?)?.toInt() ?? 5,
      );
}

/// Один образец (состоит из 5 навесок, которые ссыпаются вместе и сеются разом)
class ProtoSpecimen {
  String label;
  List<ProtoSubsample> subsamples;
  double totalDustHeightMm; // Общая высота столбика пыли l (мм) в объемомере по всем 5 навескам
  double? totalDustMassG;   // Общая масса отсеянной пыли (<0.5 мм), г

  ProtoSpecimen({
    required this.label,
    List<ProtoSubsample>? subsamples,
    this.totalDustHeightMm = 0.0,
    this.totalDustMassG,
  }) : subsamples = subsamples ??
            [
              ProtoSubsample(),
              ProtoSubsample(),
              ProtoSubsample(),
              ProtoSubsample(),
              ProtoSubsample(),
            ];

  int get totalDropsN => subsamples.fold<int>(0, (sum, s) => sum + s.dropsN);

  double get totalSampleMassG => subsamples.fold<double>(0.0, (sum, s) => sum + s.massG);

  bool get isValid => totalDropsN > 0 && totalDustHeightMm > 0;

  /// Коэффициент крепости образца по ГОСТ 21153.1-75: f = 20 * sum(n) / l_общ
  double get strengthCoeffF => isValid ? (20.0 * totalDropsN) / totalDustHeightMm : 0.0;

  /// Предел прочности на одноосное сжатие по образцу, МПа
  double estimatedRcMpa(double softeningFactor, bool isWaterSaturated) {
    final f = strengthCoeffF;
    if (f <= 0) return 0.0;
    double rc = f * 10.0;
    if (isWaterSaturated) rc *= softeningFactor;
    return rc;
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'subsamples': subsamples.map((e) => e.toJson()).toList(),
        'totalDustHeightMm': totalDustHeightMm,
        'totalDustMassG': totalDustMassG,
      };

  factory ProtoSpecimen.fromJson(Map<String, dynamic> json) => ProtoSpecimen(
        label: json['label'] as String? ?? 'Образец',
        subsamples: (json['subsamples'] as List<dynamic>?)
            ?.map((e) => ProtoSubsample.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalDustHeightMm: (json['totalDustHeightMm'] as num?)?.toDouble() ?? 0.0,
        totalDustMassG: (json['totalDustMassG'] as num?)?.toDouble(),
      );
}

/// Проба (обычно 4 образца по 5 навесок)
class ProtodyakonovRecord {
  final String id;
  final String date;
  String cipher;
  String borehole;
  String interval;
  String lithotypeId;
  String condition; // 'h', 'n', 'w'
  double? rhoDGcm3;
  List<ProtoSpecimen> specimens;

  ProtodyakonovRecord({
    required this.id,
    required this.date,
    this.cipher = '',
    this.borehole = '',
    this.interval = '',
    this.lithotypeId = 'unknown_rock',
    this.condition = 'h',
    this.rhoDGcm3,
    List<ProtoSpecimen>? specimens,
  }) : specimens = specimens ??
            [
              ProtoSpecimen(label: 'Образец 1'),
              ProtoSpecimen(label: 'Образец 2'),
              ProtoSpecimen(label: 'Образец 3'),
              ProtoSpecimen(label: 'Образец 4'),
            ];

  LithotypeProfile get lithotype => LithotypeDatabase.getById(lithotypeId);

  double get recommendedMassG {
    final rho = (rhoDGcm3 != null && rhoDGcm3! > 1.0) ? rhoDGcm3! : lithotype.rhoSDefault;
    return (20.0 * rho).clamp(40.0, 60.0);
  }

  List<ProtoSpecimen> get validSpecimens => specimens.where((s) => s.isValid).toList();

  /// Средний коэффициент крепости f по пробе (по всем заполненным образцам)
  double get avgStrengthF {
    final valid = validSpecimens;
    if (valid.isEmpty) return 0.0;
    return valid.map((s) => s.strengthCoeffF).reduce((a, b) => a + b) / valid.length;
  }

  /// Средний предел прочности Rc по пробе, МПа
  double get avgRcMpa {
    final f = avgStrengthF;
    if (f <= 0) return 0.0;
    double rc = f * 10.0;
    if (condition == 'w') rc *= lithotype.softeningFactor;
    return rc;
  }

  /// Коэффициент вариации V (%) между образцами в пробе
  double get variationPercent {
    final valid = validSpecimens;
    if (valid.length < 2) return 0.0;
    final mean = avgStrengthF;
    if (mean <= 0) return 0.0;
    double sqSum = 0.0;
    for (final s in valid) {
      sqSum += math.pow(s.strengthCoeffF - mean, 2);
    }
    final stdDev = math.sqrt(sqSum / (valid.length - 1));
    return (stdDev / mean) * 100.0;
  }

  String get strengthCategory {
    final f = avgStrengthF;
    if (f <= 0) return 'Нет данных';
    if (f >= 20) return 'I кат. — В высшей степени крепкие (f ≥ 20)';
    if (f >= 15) return 'II кат. — Очень крепкие (f = 15–19)';
    if (f >= 8) return 'III–IIIа кат. — Крепкие (f = 8–14)';
    if (f >= 5) return 'IV–IVа кат. — Довольно крепкие (f = 5–7)';
    if (f >= 3) return 'V–Vа кат. — Средней крепости (f = 3–4)';
    if (f >= 1.5) return 'VI–VIа кат. — Довольно мягкие (f = 1.5–2)';
    return 'VII–X кат. — Мягкие / рыхлые (f < 1.5)';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'cipher': cipher,
        'borehole': borehole,
        'interval': interval,
        'lithotypeId': lithotypeId,
        'condition': condition,
        'rhoDGcm3': rhoDGcm3,
        'specimens': specimens.map((e) => e.toJson()).toList(),
      };

  factory ProtodyakonovRecord.fromJson(Map<String, dynamic> json) => ProtodyakonovRecord(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        cipher: json['cipher'] as String? ?? '',
        borehole: json['borehole'] as String? ?? '',
        interval: json['interval'] as String? ?? '',
        lithotypeId: json['lithotypeId'] as String? ?? 'unknown_rock',
        condition: json['condition'] as String? ?? 'h',
        rhoDGcm3: (json['rhoDGcm3'] as num?)?.toDouble(),
        specimens: (json['specimens'] as List<dynamic>?)
            ?.map((e) => ProtoSpecimen.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProtoStorageService {
  static const String _key = 'rockarea_protodyakonov_records_v2';

  static Future<List<ProtodyakonovRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => ProtodyakonovRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecord(ProtodyakonovRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getRecords();
    final idx = list.indexWhere((r) => r.id == record.id);
    if (idx != -1) {
      list[idx] = record;
    } else {
      list.insert(0, record);
    }
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<void> deleteRecord(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getRecords();
    list.removeWhere((r) => r.id == id);
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<void> exportCsv({
    required BuildContext context,
    required ProtodyakonovRecord record,
  }) async {
    final sb = StringBuffer();
    sb.write('ВЕДОМОСТЬ ОПРЕДЕЛЕНИЯ КРЕПОСТИ ПО М. М. ПРОТОДЬЯКОНОВУ (ГОСТ 21153.1-75)\r\n');
    sb.write('Шифр пробы;${record.cipher.isNotEmpty ? record.cipher : record.id};Дата;${record.date}\r\n');
    sb.write('Литотип;${record.lithotype.name};Состояние;${record.condition}\r\n');
    sb.write('\r\n');
    sb.write(
      'Образец;'
      'Навеска 1 (г / уд.);'
      'Навеска 2 (г / уд.);'
      'Навеска 3 (г / уд.);'
      'Навеска 4 (г / уд.);'
      'Навеска 5 (г / уд.);'
      'Общая масса навесок, г;'
      'Сумма ударов Σn;'
      'Масса пыли (<0.5 мм), г;'
      'Высота столбика пыли l, мм;'
      'Коэф. крепости образца f;'
      'Оценка Rc образца, МПа;'
      'Средний f по пробе;'
      'Средний Rc по пробе, МПа\r\n',
    );

    const int startRow = 7;
    final int endRow = startRow + record.specimens.length - 1;

    for (int i = 0; i < record.specimens.length; i++) {
      final sp = record.specimens[i];
      final r = startRow + i;

      String subStr(int idx) {
        if (idx >= sp.subsamples.length) return '-';
        final s = sp.subsamples[idx];
        return '${s.massG.toStringAsFixed(1)} г / ${s.dropsN}';
      }

      final dustMassStr = sp.totalDustMassG != null ? sp.totalDustMassG!.toStringAsFixed(2) : '';
      final fFormula = '"=IF(J$r>0; ROUND((20*H$r)/J$r; 2); 0)"';
      final rcFormula = '"=IF(K$r>0; ROUND(K$r*10; 1); 0)"';
      final avgFFormula = (i == 0) ? '"=IF(COUNT(K$startRow:K$endRow)>0; ROUND(AVERAGE(K$startRow:K$endRow); 2); 0)"' : '';
      final avgRcFormula = (i == 0) ? '"=IF(COUNT(L$startRow:L$endRow)>0; ROUND(AVERAGE(L$startRow:L$endRow); 1); 0)"' : '';

      sb.write(
        '${sp.label};'
        '${subStr(0)};'
        '${subStr(1)};'
        '${subStr(2)};'
        '${subStr(3)};'
        '${subStr(4)};'
        '${sp.totalSampleMassG.toStringAsFixed(1)};'
        '${sp.totalDropsN};'
        '$dustMassStr;'
        '${sp.totalDustHeightMm.toStringAsFixed(1)};'
        '$fFormula;'
        '$rcFormula;'
        '$avgFFormula;'
        '$avgRcFormula\r\n',
      );
    }

    final formatted = 'sep=;\r\n${sb.toString()}';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(formatted)];
    final safeCipher = (record.cipher.isNotEmpty ? record.cipher : record.id).replaceAll(RegExp(r'[^\w\dА-Яа-я]'), '_');
    final filename = 'Протодьяконов_$safeCipher.csv';

    File file;
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      file = File('${downloadDir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Ведомость сохранена в Загрузки:\n${file.path}'),
          action: SnackBarAction(
            label: 'Отправить',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(file.path)]),
          ),
        ),
      );
    }
  }
}

class ProtodyakonovModuleScreen extends StatefulWidget {
  const ProtodyakonovModuleScreen({super.key});

  @override
  State<ProtodyakonovModuleScreen> createState() => _ProtodyakonovModuleScreenState();
}

class _ProtodyakonovModuleScreenState extends State<ProtodyakonovModuleScreen> {
  List<ProtodyakonovRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ProtoStorageService.getRecords();
    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([ProtodyakonovRecord? record]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProtodyakonovEditorScreen(existingRecord: record)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Метод Протодьяконова (ГОСТ 21153.1)'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFF97316),
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Новая проба', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(color: Color(0xFFFFF7ED), shape: BoxShape.circle),
                          child: const Icon(Icons.hardware, size: 42, color: Color(0xFFF97316)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Нет проб на копре',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Стандартная схема ГОСТ 21153.1-75: 1 проба = 4 образца по 5 навесок (40–60 г) с общим просеиванием и замером столбика пыли.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF97316),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Создать пробу', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: _records.length,
                  itemBuilder: (context, idx) {
                    final r = _records[idx];
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openEditor(r),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.cipher.isNotEmpty ? r.cipher : r.id,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF7ED),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'f ср = ${r.avgStrengthF.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                                    onPressed: () async {
                                      await ProtoStorageService.deleteRecord(r.id);
                                      _load();
                                    },
                                  ),
                                ],
                              ),
                              Text(
                                '${r.lithotype.name} • Образцов: ${r.validSpecimens.length}/${r.specimens.length} • ${r.date}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Средняя прочность: Rc = ${r.avgRcMpa.toStringAsFixed(1)} МПа • V = ${r.variationPercent.toStringAsFixed(1)}%',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class ProtodyakonovEditorScreen extends StatefulWidget {
  final ProtodyakonovRecord? existingRecord;
  const ProtodyakonovEditorScreen({super.key, this.existingRecord});

  @override
  State<ProtodyakonovEditorScreen> createState() => _ProtodyakonovEditorScreenState();
}

class _ProtodyakonovEditorScreenState extends State<ProtodyakonovEditorScreen> {
  late ProtodyakonovRecord _record;
  late TextEditingController _cipherCtrl;
  late TextEditingController _rhoDCtrl;
  bool _showGostGuide = false;
  int _selectedSpecimenIdx = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    _record = widget.existingRecord ??
        ProtodyakonovRecord(
          id: 'Проба #${now.millisecondsSinceEpoch.toString().substring(8)}',
          date: dateStr,
        );

    _cipherCtrl = TextEditingController(text: _record.cipher);
    _rhoDCtrl = TextEditingController(text: _record.rhoDGcm3?.toString() ?? '');
  }

  @override
  void dispose() {
    _cipherCtrl.dispose();
    _rhoDCtrl.dispose();
    super.dispose();
  }

  void _syncInputs() {
    _record.cipher = _cipherCtrl.text.trim();
    _record.rhoDGcm3 = double.tryParse(_rhoDCtrl.text.replaceAll(',', '.'));
  }

  void _applyDropsToSpecimen(ProtoSpecimen sp, int drops) {
    setState(() {
      for (final s in sp.subsamples) {
        s.dropsN = drops;
      }
    });
  }

  void _applyMassToSpecimen(ProtoSpecimen sp, double mass) {
    setState(() {
      for (final s in sp.subsamples) {
        s.massG = mass;
      }
    });
  }

  Future<void> _save() async {
    _syncInputs();
    await ProtoStorageService.saveRecord(_record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFF059669), content: Text('Проба сохранена!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncInputs();
    if (_selectedSpecimenIdx >= _record.specimens.length) {
      _selectedSpecimenIdx = _record.specimens.length - 1;
    }
    final activeSp = _record.specimens[_selectedSpecimenIdx];
    final avgF = _record.avgStrengthF;
    final avgRc = _record.avgRcMpa;
    final varPct = _record.variationPercent;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_record.cipher.isNotEmpty ? _record.cipher : 'Копер Протодьяконова'),
        actions: [
          IconButton(
            icon: Icon(_showGostGuide ? Icons.help : Icons.help_outline, color: const Color(0xFFF97316)),
            tooltip: 'Шпаргалка ГОСТ 21153.1-75',
            onPressed: () => setState(() => _showGostGuide = !_showGostGuide),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Color(0xFF2563EB)),
            tooltip: 'Сохранить',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_showGostGuide)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(14)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'МЕТОДИКА ПО ГОСТ 21153.1-75',
                    style: TextStyle(color: Color(0xFFFB923C), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '1. Проба делится на 4 образца, каждый образец — на 5 навесок по 40–60 г (фракция 20–40 мм).\n'
                    '2. Каждая из 5 навесок поочередно дробится в копре (гиря 2,4 кг с высоты 600 мм: обычно 5–15 ударов для крепких пород, 2–3 для слабых).\n'
                    '3. Весь раздробленный материал 5 навесок ссыпается вместе и просеивается разом через сито 0,5 мм.\n'
                    '4. Пыль (<0,5 мм) высыпается в объемомер Ø 23 мм — замеряется общая высота столбика l (оптимально 20–100 мм) и масса пыли.',
                    style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, height: 1.45),
                  ),
                ],
              ),
            ),

          // Паспорт пробы
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _cipherCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Шифр пробы (например, БАМ 1 1)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _record.lithotypeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Литотип породы (можно оставить неизвестным)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: LithotypeDatabase.profiles
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _record.lithotypeId = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rhoDCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Плотность ρ (${_record.lithotype.rhoSDefault})',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _record.condition,
                          decoration: const InputDecoration(labelText: 'Состояние', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'h', child: Text('h — сухая')),
                            DropdownMenuItem(value: 'n', child: Text('n — естеств.')),
                            DropdownMenuItem(value: 'w', child: Text('w — водонас.')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _record.condition = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Переключатель 4 образцов внутри пробы
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Образцы в пробе (по 5 навесок):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _record.specimens.add(ProtoSpecimen(label: 'Образец ${_record.specimens.length + 1}'));
                    _selectedSpecimenIdx = _record.specimens.length - 1;
                  });
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Образец', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_record.specimens.length, (idx) {
                final sp = _record.specimens[idx];
                final isSelected = idx == _selectedSpecimenIdx;
                final hasData = sp.isValid;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: isSelected,
                    selectedColor: const Color(0xFF2563EB),
                    backgroundColor: hasData ? const Color(0xFFECFDF5) : Colors.white,
                    label: Text(
                      hasData ? '${sp.label} (f=${sp.strengthCoeffF.toStringAsFixed(1)})' : sp.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : (hasData ? const Color(0xFF059669) : const Color(0xFF334155)),
                      ),
                    ),
                    onSelected: (_) => setState(() => _selectedSpecimenIdx = idx),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),

          // Карточка выбранного образца (5 навесок + общий отсев пыли)
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${activeSp.label} — 5 навесок (40–60 г)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                        ),
                      ),
                      if (_record.specimens.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                          tooltip: 'Удалить этот образец',
                          onPressed: () {
                            setState(() {
                              _record.specimens.removeAt(_selectedSpecimenIdx);
                              if (_selectedSpecimenIdx >= _record.specimens.length) {
                                _selectedSpecimenIdx = _record.specimens.length - 1;
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        label: Text('Всем ${_record.recommendedMassG.toStringAsFixed(0)} г', style: const TextStyle(fontSize: 11)),
                        onPressed: () => _applyMassToSpecimen(
                          activeSp,
                          double.parse(_record.recommendedMassG.toStringAsFixed(1)),
                        ),
                      ),
                      ActionChip(
                        label: const Text('Всем 5 уд.', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyDropsToSpecimen(activeSp, 5),
                      ),
                      ActionChip(
                        label: const Text('Всем 10 уд.', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyDropsToSpecimen(activeSp, 10),
                      ),
                      ActionChip(
                        label: const Text('Всем 15 уд.', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyDropsToSpecimen(activeSp, 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 5 строк навесок
                  for (int i = 0; i < activeSp.subsamples.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 78,
                            child: Text(
                              'Навеска #${i + 1}:',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('sp_${_selectedSpecimenIdx}_m_${i}_${activeSp.subsamples[i].massG}'),
                              initialValue: activeSp.subsamples[i].massG.toString(),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Масса, г',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onChanged: (v) {
                                setState(() {
                                  activeSp.subsamples[i].massG =
                                      double.tryParse(v.replaceAll(',', '.')) ?? activeSp.subsamples[i].massG;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('sp_${_selectedSpecimenIdx}_n_${i}_${activeSp.subsamples[i].dropsN}'),
                              initialValue: activeSp.subsamples[i].dropsN.toString(),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Ударов n',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onChanged: (v) {
                                setState(() {
                                  activeSp.subsamples[i].dropsN = int.tryParse(v.trim()) ?? 0;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  Text(
                    'Результат общего просеивания (${activeSp.label}): Σm = ${activeSp.totalSampleMassG.toStringAsFixed(1)} г • Σn = ${activeSp.totalDropsN} ударов',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('sp_${_selectedSpecimenIdx}_dust_m'),
                          initialValue: activeSp.totalDustMassG != null && activeSp.totalDustMassG! > 0
                              ? activeSp.totalDustMassG.toString()
                              : '',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Масса пыли, г',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setState(() {
                              activeSp.totalDustMassG = double.tryParse(v.replaceAll(',', '.'));
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('sp_${_selectedSpecimenIdx}_dust_l'),
                          initialValue: activeSp.totalDustHeightMm > 0 ? activeSp.totalDustHeightMm.toString() : '',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Высота пыли l, мм',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setState(() {
                              activeSp.totalDustHeightMm = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  if (activeSp.totalDustHeightMm > 0 && (activeSp.totalDustHeightMm < 20 || activeSp.totalDustHeightMm > 100))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        activeSp.totalDustHeightMm < 20
                            ? 'Подсказка ГОСТ: столбик пыли < 20 мм — на следующих образцах можно увеличить число ударов.'
                            : 'Подсказка ГОСТ: столбик пыли > 100 мм — порода мягкая, уменьшите число ударов.',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFEA580C), fontWeight: FontWeight.w600),
                      ),
                    ),

                  if (activeSp.isValid)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'По ${activeSp.label}: f = ${activeSp.strengthCoeffF.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669)),
                          ),
                          Text(
                            'Rc = ${activeSp.estimatedRcMpa(_record.lithotype.softeningFactor, _record.condition == 'w').toStringAsFixed(1)} МПа',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Сводный итог по всей пробе (по всем 4 образцам)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'СВОДНЫЙ ИТОГ ПО ПРОБЕ (УЧТЕНО ОБРАЗЦОВ: ${_record.validSpecimens.length} ИЗ ${_record.specimens.length})',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.7),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        'Средний коэф. f',
                        avgF > 0 ? avgF.toStringAsFixed(2) : '—',
                        const Color(0xFFEA580C),
                        const Color(0xFFFFF7ED),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        'Средний Rc',
                        avgRc > 0 ? '${avgRc.toStringAsFixed(1)} МПа' : '—',
                        const Color(0xFF2563EB),
                        const Color(0xFFEFF6FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Категория крепости: ${_record.strengthCategory}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                if (_record.validSpecimens.length >= 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Вариация между образцами V = ${varPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: varPct > 20 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: avgF > 0
                        ? () async {
                            await _save();
                            if (context.mounted) {
                              ProtoStorageService.exportCsv(context: context, record: _record);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.table_view, size: 18),
                    label: const Text('Сохранить пробу и выгрузить в Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String label, String value, Color accent, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent)),
        ],
      ),
    );
  }
}
