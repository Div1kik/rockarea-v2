import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../deformation/lithotype_db.dart';

class ProtoSubsample {
  double massG;       // Масса навески, г (40..60 г)
  int dropsN;         // Число сбрасываний гири n
  double dustHeightMm; // Высота столбика пыли (<0.5 мм) в объемомере d=23 мм, мм

  ProtoSubsample({
    this.massG = 50.0,
    this.dropsN = 5,
    this.dustHeightMm = 0.0,
  });

  bool get isValid => dropsN > 0 && dustHeightMm > 0;

  /// Коэффициент крепости f по ГОСТ 21153.1-75: f = 20 * n / l
  double get strengthCoeffF => isValid ? (20.0 * dropsN) / dustHeightMm : 0.0;

  Map<String, dynamic> toJson() => {
        'massG': massG,
        'dropsN': dropsN,
        'dustHeightMm': dustHeightMm,
      };

  factory ProtoSubsample.fromJson(Map<String, dynamic> json) => ProtoSubsample(
        massG: (json['massG'] as num?)?.toDouble() ?? 50.0,
        dropsN: (json['dropsN'] as num?)?.toInt() ?? 5,
        dustHeightMm: (json['dustHeightMm'] as num?)?.toDouble() ?? 0.0,
      );
}

class ProtodyakonovRecord {
  final String id;
  final String date;
  String cipher;
  String borehole;
  String interval;
  String lithotypeId;
  String condition; // 'n', 'w', 'h'
  double? rhoDGcm3;
  List<ProtoSubsample> subsamples;

  ProtodyakonovRecord({
    required this.id,
    required this.date,
    this.cipher = '',
    this.borehole = '',
    this.interval = '',
    this.lithotypeId = 'gabbro_diabase',
    this.condition = 'h',
    this.rhoDGcm3,
    List<ProtoSubsample>? subsamples,
  }) : subsamples = subsamples ??
            [
              ProtoSubsample(),
              ProtoSubsample(),
              ProtoSubsample(),
              ProtoSubsample(),
              ProtoSubsample(),
            ];

  LithotypeProfile get lithotype => LithotypeDatabase.getById(lithotypeId);

  /// Рекомендуемая масса одной навески по ГОСТ 21153.1-75 (объем ~20 см3 => m = 20 * rho)
  double get recommendedMassG {
    final rho = (rhoDGcm3 != null && rhoDGcm3! > 1.0) ? rhoDGcm3! : lithotype.rhoSDefault;
    return (20.0 * rho).clamp(40.0, 65.0);
  }

  List<ProtoSubsample> get validSubsamples => subsamples.where((s) => s.isValid).toList();

  /// Средний коэффициент крепости f
  double get avgStrengthF {
    final valid = validSubsamples;
    if (valid.isEmpty) return 0.0;
    final sum = valid.map((s) => s.strengthCoeffF).reduce((a, b) => a + b);
    return sum / valid.length;
  }

  /// Суммарный расчет по ГОСТ: f = 20 * sum(n) / sum(l)
  double get pooledStrengthF {
    final valid = validSubsamples;
    if (valid.isEmpty) return 0.0;
    final totalN = valid.map((s) => s.dropsN).reduce((a, b) => a + b);
    final totalL = valid.map((s) => s.dustHeightMm).reduce((a, b) => a + b);
    return totalL > 0 ? (20.0 * totalN) / totalL : 0.0;
  }

  /// Коэффициент вариации V, %
  double get variationPercent {
    final valid = validSubsamples;
    if (valid.length < 2) return 0.0;
    final mean = avgStrengthF;
    if (mean <= 0) return 0.0;
    double sqDiffSum = 0.0;
    for (final s in valid) {
      sqDiffSum += math.pow(s.strengthCoeffF - mean, 2);
    }
    final stdDev = math.sqrt(sqDiffSum / (valid.length - 1));
    return (stdDev / mean) * 100.0;
  }

  /// Эквивалентный предел прочности на одноосное сжатие Rc, МПа (Rc ≈ 10 * f)
  double get estimatedRcMpa {
    final f = pooledStrengthF;
    if (f <= 0) return 0.0;
    double rc = f * 10.0;
    if (condition == 'w') {
      rc *= lithotype.softeningFactor;
    }
    return rc;
  }

  /// Категория крепости по шкале проф. М. М. Протодьяконова
  String get strengthCategory {
    final f = pooledStrengthF;
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
        'subsamples': subsamples.map((e) => e.toJson()).toList(),
      };

  factory ProtodyakonovRecord.fromJson(Map<String, dynamic> json) => ProtodyakonovRecord(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        cipher: json['cipher'] as String? ?? '',
        borehole: json['borehole'] as String? ?? '',
        interval: json['interval'] as String? ?? '',
        lithotypeId: json['lithotypeId'] as String? ?? 'gabbro_diabase',
        condition: json['condition'] as String? ?? 'h',
        rhoDGcm3: (json['rhoDGcm3'] as num?)?.toDouble(),
        subsamples: (json['subsamples'] as List<dynamic>?)
            ?.map((e) => ProtoSubsample.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProtoStorageService {
  static const String _key = 'rockarea_protodyakonov_records';

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
    sb.write('ПРОТОКОЛ ОПРЕДЕЛЕНИЯ КОЭФФИЦИЕНТА КРЕПОСТИ ПО М. М. ПРОТОДЬЯКОНОВУ (ГОСТ 21153.1-75)\r\n');
    sb.write('Шифр пробы;${record.cipher.isNotEmpty ? record.cipher : record.id};Дата;${record.date}\r\n');
    sb.write('Литотип;${record.lithotype.name};Состояние;${record.condition}\r\n');
    sb.write('\r\n');
    sb.write('№ навески;Масса навески m, г;Число сбрасываний n;Высота столбика пыли l, мм;Коэффициент крепости f;Средний f;Оценка Rc, МПа\r\n');

    const int startRow = 7;
    final int endRow = startRow + record.subsamples.length - 1;

    for (int i = 0; i < record.subsamples.length; i++) {
      final s = record.subsamples[i];
      final r = startRow + i;
      final fFormula = '"=IF(D$r>0; ROUND((20*C$r)/D$r; 2); 0)"';
      final avgFormula = (i == 0) ? '"=ROUND((20*SUM(C$startRow:C$endRow))/SUM(D$startRow:D$endRow); 2)"' : '';
      final rcFormula = (i == 0) ? '"=ROUND(F$startRow*10; 1)"' : '';

      sb.write(
        '${i + 1};'
        '${s.massG.toStringAsFixed(1)};'
        '${s.dropsN};'
        '${s.dustHeightMm.toStringAsFixed(1)};'
        '$fFormula;'
        '$avgFormula;'
        '$rcFormula\r\n',
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
        label: const Text('Новое испытание', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          'Нет испытаний на копре',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Определение коэффициента крепости f и предела прочности Rc методом толчения щебня (фракция 20–40 мм) с подсказками по массе навески и числу ударов.',
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
                          label: const Text('Начать испытание', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                      'f = ${r.pooledStrengthF.toStringAsFixed(2)}',
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
                              Text('${r.lithotype.name} • ${r.date}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              const SizedBox(height: 8),
                              Text(
                                'Оценка прочности: Rc = ${r.estimatedRcMpa.toStringAsFixed(1)} МПа • ${r.strengthCategory}',
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
  late TextEditingController _boreholeCtrl;
  late TextEditingController _intervalCtrl;
  late TextEditingController _rhoDCtrl;
  bool _showGostGuide = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    _record = widget.existingRecord ??
        ProtodyakonovRecord(
          id: 'Копер #${now.millisecondsSinceEpoch.toString().substring(8)}',
          date: dateStr,
        );

    _cipherCtrl = TextEditingController(text: _record.cipher);
    _boreholeCtrl = TextEditingController(text: _record.borehole);
    _intervalCtrl = TextEditingController(text: _record.interval);
    _rhoDCtrl = TextEditingController(text: _record.rhoDGcm3?.toString() ?? '');
  }

  @override
  void dispose() {
    _cipherCtrl.dispose();
    _boreholeCtrl.dispose();
    _intervalCtrl.dispose();
    _rhoDCtrl.dispose();
    super.dispose();
  }

  void _syncInputs() {
    _record.cipher = _cipherCtrl.text.trim();
    _record.borehole = _boreholeCtrl.text.trim();
    _record.interval = _intervalCtrl.text.trim();
    _record.rhoDGcm3 = double.tryParse(_rhoDCtrl.text.replaceAll(',', '.'));
  }

  void _applyRecommendedMassToAll() {
    final recMass = double.parse(_record.recommendedMassG.toStringAsFixed(1));
    setState(() {
      for (final s in _record.subsamples) {
        s.massG = recMass;
      }
    });
  }

  void _applyDropsToAll(int drops) {
    setState(() {
      for (final s in _record.subsamples) {
        s.dropsN = drops;
      }
    });
  }

  Future<void> _save() async {
    _syncInputs();
    await ProtoStorageService.saveRecord(_record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFF059669), content: Text('Протокол сохранен!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncInputs();
    final f = _record.pooledStrengthF;
    final rc = _record.estimatedRcMpa;
    final varPct = _record.variationPercent;
    final validCount = _record.validSubsamples.length;

    // Проверка оптимальной высоты столбика пыли (по ГОСТ 21153.1-75 суммарно по 5 навескам 20..100 мм)
    final totalDust = _record.validSubsamples.fold<double>(0.0, (sum, s) => sum + s.dustHeightMm);
    String? heightAdvice;
    if (validCount >= 3) {
      if (totalDust < 20.0) {
        heightAdvice = 'Суммарный столбик пыли (${totalDust.toStringAsFixed(1)} мм) < 20 мм: для следующей серии увеличьте число ударов n до 10–15.';
      } else if (totalDust > 100.0) {
        heightAdvice = 'Суммарный столбик пыли (${totalDust.toStringAsFixed(1)} мм) > 100 мм: порода мягкая, уменьшите число ударов n до 2–3.';
      }
    }

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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          // Блок 1: Интерактивная памятка по ГОСТ 21153.1-75
          if (_showGostGuide)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.menu_book, color: Color(0xFFFB923C), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ПАМЯТКА ЛАБОРАНТА (ГОСТ 21153.1-75)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Фракция щебня: 20–40 мм (допускается 10–20 мм), куски угловатые без лещадности.\n'
                    '• Число параллельных навесок: минимум 5 шт. на одну пробу.\n'
                    '• Масса 1 навески: 40–60 г (для выбранной породы ≈ ${_record.recommendedMassG.toStringAsFixed(0)} г).\n'
                    '• Копер (гиря 2,4 кг, высота 600 мм): 10–15 ударов для крепких пород, 5 ударов для средних, 2–3 для слабых.\n'
                    '• Сито 0,5 мм: просеивать 20–30 с, замерять высоту пыли в объемомере Ø 23 мм.',
                    style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, height: 1.45),
                  ),
                ],
              ),
            ),

          // Блок 2: Паспорт пробы и автоподбор массы навески
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
                      labelText: 'Литотип породы',
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
                  const SizedBox(height: 10),
                  // Быстрые кнопки настройки всех навесок
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.scale, size: 15, color: Color(0xFF2563EB)),
                        label: Text('Масса ${_record.recommendedMassG.toStringAsFixed(0)} г всем', style: const TextStyle(fontSize: 11)),
                        onPressed: _applyRecommendedMassToAll,
                      ),
                      ActionChip(
                        label: const Text('3 удара', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyDropsToAll(3),
                      ),
                      ActionChip(
                        label: const Text('5 ударов', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyDropsToAll(5),
                      ),
                      ActionChip(
                        label: const Text('10 ударов', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyDropsToAll(10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Блок 3: Список параллельных навесок (по умолчанию 5 шт. по ГОСТ)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Параллельные навески (${_record.subsamples.length} шт.)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _record.subsamples.add(
                      ProtoSubsample(
                        massG: double.parse(_record.recommendedMassG.toStringAsFixed(1)),
                        dropsN: _record.subsamples.isNotEmpty ? _record.subsamples.last.dropsN : 5,
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить навеску'),
              ),
            ],
          ),

          for (int i = 0; i < _record.subsamples.length; i++) _buildSubsampleCard(i),

          if (heightAdvice != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Text(
                heightAdvice,
                style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412), fontWeight: FontWeight.w600),
              ),
            ),

          // Блок 4: Итоговый расчет
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
                const Text(
                  'РЕЗУЛЬТАТЫ ПО ГОСТ 21153.1-75',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.8),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        'Коэф. крепости f',
                        f > 0 ? f.toStringAsFixed(2) : '—',
                        const Color(0xFFEA580C),
                        const Color(0xFFFFF7ED),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        'Оценка прочности Rc',
                        rc > 0 ? '${rc.toStringAsFixed(1)} МПа' : '—',
                        const Color(0xFF2563EB),
                        const Color(0xFFEFF6FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Классификация: ${_record.strengthCategory}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                if (validCount >= 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Коэффициент вариации V = ${varPct.toStringAsFixed(1)}% ${varPct > 20 ? "(высокий разброс — рекомендуется добавить 2 навески)" : "(однородность в норме)"}',
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
                    onPressed: f > 0
                        ? () async {
                            await _save();
                            if (context.mounted) {
                              ProtoStorageService.exportCsv(context: context, record: _record);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.table_view, size: 18),
                    label: const Text('Сохранить и выгрузить в Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubsampleCard(int index) {
    final s = _record.subsamples[index];
    final fVal = s.strengthCoeffF;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: const Color(0xFFFFF7ED),
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEA580C))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Навеска #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                if (fVal > 0)
                  Text(
                    'f = ${fVal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF059669)),
                  ),
                if (_record.subsamples.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                    onPressed: () => setState(() => _record.subsamples.removeAt(index)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('m_${index}_${s.massG}'),
                    initialValue: s.massG > 0 ? s.massG.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Масса m (г)', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) {
                      s.massG = double.tryParse(v.replaceAll(',', '.')) ?? s.massG;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('n_${index}_${s.dropsN}'),
                    initialValue: s.dropsN.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Удары n', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) {
                      setState(() => s.dropsN = int.tryParse(v.trim()) ?? 5);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: s.dustHeightMm > 0 ? s.dustHeightMm.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Пыль l (мм)', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) {
                      setState(() => s.dustHeightMm = double.tryParse(v.replaceAll(',', '.')) ?? 0.0);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
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
