import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../deformation/lithotype_db.dart';

class CylinderSampleRow {
  String cipher;
  String condition; // 'n', 'w', 'h'

  // 1. Геометрия (один диаметр d и одна длина h в мм)
  double diameterMm;
  double heightMm;

  // 2. Влажность (бюкс)
  String boxNumber;
  double? boxEmptyG;   // m0
  double? boxWetG;     // m1
  double? boxDryG;     // m2

  // 3. Плотность: 0 = геометрическая (масса / объем цилиндра), 1 = гидростатическая (взвешивание в воде)
  int densityMethod;
  double? airMassG;         // m1 на воздухе, г
  double? paraffinedMassG;  // m2 с парафином на воздухе, г (опционально)
  double? waterMassG;       // m3 в воде, г

  // 4. Ультразвук (ГОСТ 21153.7-75)
  double? usBaseMm;   // База прозвучивания (если null, берется heightMm)
  double? tpUs;       // Время продольной волны, мкс
  double? tsUs;       // Время поперечной волны, мкс

  // 5. Пресс (разрушающая нагрузка P, кН)
  double loadKn;

  CylinderSampleRow({
    this.cipher = '',
    this.condition = 'n',
    this.diameterMm = 0.0,
    this.heightMm = 0.0,
    this.boxNumber = '',
    this.boxEmptyG,
    this.boxWetG,
    this.boxDryG,
    this.densityMethod = 0,
    this.airMassG,
    this.paraffinedMassG,
    this.waterMassG,
    this.usBaseMm,
    this.tpUs,
    this.tsUs,
    this.loadKn = 0.0,
  });

  // --- Расчеты геометрии ---
  /// Площадь торца A, см2
  double get areaCm2 => diameterMm > 0 ? (math.pi * math.pow(diameterMm / 10.0, 2)) / 4.0 : 0.0;

  /// Объем цилиндра V, см3
  double get volumeCm3 => (areaCm2 > 0 && heightMm > 0) ? areaCm2 * (heightMm / 10.0) : 0.0;

  /// Соотношение h / d
  double get hdRatio => (diameterMm > 0 && heightMm > 0) ? heightMm / diameterMm : 0.0;

  // --- Расчет влажности W, % ---
  double? get moisturePercent {
    if (boxEmptyG == null || boxWetG == null || boxDryG == null) return null;
    final drySoil = boxDryG! - boxEmptyG!;
    final water = boxWetG! - boxDryG!;
    if (drySoil <= 0.01 || water < 0) return null;
    return (water / drySoil) * 100.0;
  }

  // --- Расчет плотности rho, г/см3 ---
  double? get densityGcm3 {
    if (airMassG == null || airMassG! <= 0) return null;
    if (densityMethod == 0) {
      // Геометрический метод: m / V_цилиндра
      if (volumeCm3 <= 0) return null;
      return airMassG! / volumeCm3;
    } else {
      // Гидростатическое взвешивание (ГОСТ): m1 / ((m2 - m3)/rho_w - (m2 - m1)/rho_p)
      if (waterMassG == null) return null;
      const double rhoW = 1.0;
      const double rhoP = 0.90;
      final double m1 = airMassG!;
      final double m2 = (paraffinedMassG != null && paraffinedMassG! >= m1) ? paraffinedMassG! : m1;
      final double m3 = waterMassG!;
      final double vol = ((m2 - m3) / rhoW) - ((m2 - m1) / rhoP);
      if (vol <= 0.01) return null;
      return m1 / vol;
    }
  }

  /// Плотность сухого грунта/породы rho_d, г/см3
  double? get dryDensityGcm3 {
    final rho = densityGcm3;
    if (rho == null) return null;
    final w = moisturePercent ?? 0.0;
    return rho / (1.0 + 0.01 * w);
  }

  /// Пористость n, %
  double? porosityPercent(double rhoSDefault) {
    final rhoD = dryDensityGcm3;
    if (rhoD == null || rhoD >= rhoSDefault) return null;
    return ((rhoSDefault - rhoD) / rhoSDefault) * 100.0;
  }

  // --- Расчет ультразвука (ГОСТ 21153.7-75) ---
  double get effectiveUsBaseMm => (usBaseMm != null && usBaseMm! > 0) ? usBaseMm! : heightMm;

  /// Скорость продольной волны Vp, м/с
  double? get vpMs {
    if (effectiveUsBaseMm <= 0 || tpUs == null || tpUs! <= 0) return null;
    // мм / мкс = км/с = 1000 м/с
    return (effectiveUsBaseMm / tpUs!) * 1000.0;
  }

  /// Скорость поперечной волны Vs, м/с
  double? get vsMs {
    if (effectiveUsBaseMm <= 0 || tsUs == null || tsUs! <= 0) return null;
    return (effectiveUsBaseMm / tsUs!) * 1000.0;
  }

  /// Динамический коэффициент Пуассона v_дин
  double? get dynamicNu {
    final vp = vpMs;
    final vs = vsMs;
    if (vp == null || vs == null || vp <= vs * 1.15) return null;
    final vp2 = vp * vp;
    final vs2 = vs * vs;
    return (vp2 - 2.0 * vs2) / (2.0 * (vp2 - vs2));
  }

  /// Динамический модуль упругости E_дин, ГПа
  double? dynamicEGpa(double fallbackRhoGcm3) {
    final vp = vpMs;
    final vs = vsMs;
    if (vp == null || vs == null || vp <= vs * 1.15) return null;
    final double rhoKgM3 = (densityGcm3 ?? fallbackRhoGcm3) * 1000.0;
    final vp2 = vp * vp;
    final vs2 = vs * vs;
    final double ePa = rhoKgM3 * vs2 * ((3.0 * vp2 - 4.0 * vs2) / (vp2 - vs2));
    return ePa / 1e9;
  }

  // --- Расчет прочности на прессе ---
  /// Одноосное сжатие Rc по ГОСТ 21153.2-84, МПа
  double get compressionRcMpa {
    if (areaCm2 <= 0 || loadKn <= 0) return 0.0;
    return (10.0 * loadKn) / areaCm2;
  }

  /// Одноосное растяжение (раскалывание цилиндра) sigma_p по ГОСТ 21153.3-85, МПа
  double get tensileSplittingMpa {
    if (diameterMm <= 0 || heightMm <= 0 || loadKn <= 0) return 0.0;
    final double dCm = diameterMm / 10.0;
    final double hCm = heightMm / 10.0;
    return (20.0 * loadKn) / (math.pi * dCm * hCm);
  }

  Map<String, dynamic> toJson() => {
        'cipher': cipher,
        'condition': condition,
        'diameterMm': diameterMm,
        'heightMm': heightMm,
        'boxNumber': boxNumber,
        'boxEmptyG': boxEmptyG,
        'boxWetG': boxWetG,
        'boxDryG': boxDryG,
        'densityMethod': densityMethod,
        'airMassG': airMassG,
        'paraffinedMassG': paraffinedMassG,
        'waterMassG': waterMassG,
        'usBaseMm': usBaseMm,
        'tpUs': tpUs,
        'tsUs': tsUs,
        'loadKn': loadKn,
      };

  factory CylinderSampleRow.fromJson(Map<String, dynamic> json) => CylinderSampleRow(
        cipher: json['cipher'] as String? ?? '',
        condition: json['condition'] as String? ?? 'n',
        diameterMm: (json['diameterMm'] as num?)?.toDouble() ?? 0.0,
        heightMm: (json['heightMm'] as num?)?.toDouble() ?? 0.0,
        boxNumber: json['boxNumber'] as String? ?? '',
        boxEmptyG: (json['boxEmptyG'] as num?)?.toDouble(),
        boxWetG: (json['boxWetG'] as num?)?.toDouble(),
        boxDryG: (json['boxDryG'] as num?)?.toDouble(),
        densityMethod: (json['densityMethod'] as num?)?.toInt() ?? 0,
        airMassG: (json['airMassG'] as num?)?.toDouble(),
        paraffinedMassG: (json['paraffinedMassG'] as num?)?.toDouble(),
        waterMassG: (json['waterMassG'] as num?)?.toDouble(),
        usBaseMm: (json['usBaseMm'] as num?)?.toDouble(),
        tpUs: (json['tpUs'] as num?)?.toDouble(),
        tsUs: (json['tsUs'] as num?)?.toDouble(),
        loadKn: (json['loadKn'] as num?)?.toDouble() ?? 0.0,
      );
}

class CylinderBatchRecord {
  final String id;
  final String date;
  String batchTitle;
  String borehole;
  String interval;
  String lithotypeId;
  int strengthTestType; // 0 = Одноосное сжатие (ГОСТ 21153.2), 1 = Растяжение/раскалывание (ГОСТ 21153.3)
  List<CylinderSampleRow> rows;

  CylinderBatchRecord({
    required this.id,
    required this.date,
    this.batchTitle = '',
    this.borehole = '',
    this.interval = '',
    this.lithotypeId = 'unknown_rock',
    this.strengthTestType = 0,
    List<CylinderSampleRow>? rows,
  }) : rows = rows ??
            List.generate(
              5,
              (i) => CylinderSampleRow(cipher: '${i + 1}'),
            );

  LithotypeProfile get lithotype => LithotypeDatabase.getById(lithotypeId);

  double strengthValueFor(CylinderSampleRow r) =>
      strengthTestType == 0 ? r.compressionRcMpa : r.tensileSplittingMpa;

  List<double> get validStrengths =>
      rows.map(strengthValueFor).where((v) => v > 0).toList();

  double get avgStrengthMpa {
    final vals = validStrengths;
    if (vals.isEmpty) return 0.0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double get variationPercent {
    final vals = validStrengths;
    if (vals.length < 2) return 0.0;
    final mean = avgStrengthMpa;
    if (mean <= 0) return 0.0;
    final sqSum = vals.fold<double>(0.0, (sum, v) => sum + math.pow(v - mean, 2));
    final sd = math.sqrt(sqSum / (vals.length - 1));
    return (sd / mean) * 100.0;
  }

  double? get avgDensityGcm3 {
    final vals = rows.map((r) => r.densityGcm3).whereType<double>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double? get avgMoisturePercent {
    final vals = rows.map((r) => r.moisturePercent).whereType<double>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'batchTitle': batchTitle,
        'borehole': borehole,
        'interval': interval,
        'lithotypeId': lithotypeId,
        'strengthTestType': strengthTestType,
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  factory CylinderBatchRecord.fromJson(Map<String, dynamic> json) => CylinderBatchRecord(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        batchTitle: json['batchTitle'] as String? ?? '',
        borehole: json['borehole'] as String? ?? '',
        interval: json['interval'] as String? ?? '',
        lithotypeId: json['lithotypeId'] as String? ?? 'unknown_rock',
        strengthTestType: (json['strengthTestType'] as num?)?.toInt() ?? 0,
        rows: (json['rows'] as List<dynamic>?)
            ?.map((e) => CylinderSampleRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CylinderBatchStorage {
  static const String _key = 'rockarea_cylinder_batches_v1';

  static Future<List<CylinderBatchRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => CylinderBatchRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecord(CylinderBatchRecord record) async {
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

  /// Экспорт сводной ведомости в CSV (Excel с живыми формулами)
  static Future<void> exportCsv({
    required BuildContext context,
    required CylinderBatchRecord record,
  }) async {
    final sb = StringBuffer();
    final testName = record.strengthTestType == 0
        ? 'ОДНООСНОЕ СЖАТИЕ (ГОСТ 21153.2-84)'
        : 'ОДНООСНОЕ РАСТЯЖЕНИЕ / РАСКАЛЫВАНИЕ (ГОСТ 21153.3-85)';

    sb.write('ЖУРНАЛ ИСПЫТАНИЙ ОБРАЗЦОВ ПРАВИЛЬНОЙ ФОРМЫ — $testName\r\n');
    sb.write('Партия;${record.batchTitle.isNotEmpty ? record.batchTitle : record.id};Дата;${record.date}\r\n');
    sb.write('Скважина;${record.borehole};Интервал;${record.interval};Порода;${record.lithotype.name}\r\n');
    sb.write('\r\n');
    sb.write(
      '№;'
      'Шифр;'
      'Сост.;'
      'd, мм;'
      'h, мм;'
      'Площадь A, см2;'
      'Объем V, см3;'
      'Влажность W, %;'
      'Плотность ρ, г/см3;'
      'Плотн. сух. ρd, г/см3;'
      'Vp, м/с;'
      'Vs, м/с;'
      'E дин, ГПа;'
      'ν дин;'
      'Нагрузка P, кН;'
      '${record.strengthTestType == 0 ? "Прочность Rc, МПа" : "Прочность σp, МПа"};'
      'Среднее по партии, МПа\r\n',
    );

    const int startRow = 7;
    final int endRow = startRow + record.rows.length - 1;

    for (int i = 0; i < record.rows.length; i++) {
      final r = record.rows[i];
      final rowIdx = startRow + i;
      final wStr = r.moisturePercent != null ? r.moisturePercent!.toStringAsFixed(2) : '';
      final rhoStr = r.densityGcm3 != null ? r.densityGcm3!.toStringAsFixed(3) : '';
      final rhoDStr = r.dryDensityGcm3 != null ? r.dryDensityGcm3!.toStringAsFixed(3) : '';
      final vpStr = r.vpMs != null ? r.vpMs!.toStringAsFixed(0) : '';
      final vsStr = r.vsMs != null ? r.vsMs!.toStringAsFixed(0) : '';
      final eDyn = r.dynamicEGpa(record.lithotype.rhoSDefault);
      final eDynStr = eDyn != null ? eDyn.toStringAsFixed(2) : '';
      final nuDynStr = r.dynamicNu != null ? r.dynamicNu!.toStringAsFixed(3) : '';

      final areaFormula = '"=ROUND(PI()*((D$rowIdx/10)^2)/4; 2)"';
      final volFormula = '"=ROUND(F$rowIdx*(E$rowIdx/10); 2)"';
      final strengthFormula = record.strengthTestType == 0
          ? '"=IF(AND(F$rowIdx>0; O$rowIdx>0); ROUND((10*O$rowIdx)/F$rowIdx; 1); 0)"'
          : '"=IF(AND(D$rowIdx>0; E$rowIdx>0; O$rowIdx>0); ROUND((20*O$rowIdx)/(PI()*(D$rowIdx/10)*(E$rowIdx/10)); 2); 0)"';
      final avgFormula = (i == 0)
          ? '"=IF(COUNTIF(P$startRow:P$endRow; "">0"")>0; ROUND(AVERAGEIF(P$startRow:P$endRow; "">0""); 1); 0)"'
          : '';

      sb.write(
        '${i + 1};'
        '${r.cipher};'
        '${r.condition};'
        '${r.diameterMm.toStringAsFixed(2)};'
        '${r.heightMm.toStringAsFixed(2)};'
        '$areaFormula;'
        '$volFormula;'
        '$wStr;'
        '$rhoStr;'
        '$rhoDStr;'
        '$vpStr;'
        '$vsStr;'
        '$eDynStr;'
        '$nuDynStr;'
        '${r.loadKn.toStringAsFixed(2)};'
        '$strengthFormula;'
        '$avgFormula\r\n',
      );
    }

    final formatted = 'sep=;\r\n${sb.toString()}';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(formatted)];
    final safeTitle = (record.batchTitle.isNotEmpty ? record.batchTitle : record.id)
        .replaceAll(RegExp(r'[^\w\dА-Яа-я]'), '_');
    final filename = 'Журнал_цилиндров_$safeTitle.csv';

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

  /// Экспорт JSON-пакета партии для переноса в десктопную версию / LIMS
  static Future<void> exportLimsJson({
    required BuildContext context,
    required CylinderBatchRecord record,
  }) async {
    final jsonText = const JsonEncoder.withIndent('  ').convert(record.toJson());
    final bytes = utf8.encode(jsonText);
    final safeTitle = (record.batchTitle.isNotEmpty ? record.batchTitle : record.id)
        .replaceAll(RegExp(r'[^\w\dА-Яа-я]'), '_');
    final filename = 'LIMS_пакет_$safeTitle.json';

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
          backgroundColor: const Color(0xFF2563EB),
          content: Text('JSON-пакет для ПК/LIMS сохранён:\n${file.path}'),
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

class CylinderBatchModuleScreen extends StatefulWidget {
  const CylinderBatchModuleScreen({super.key});

  @override
  State<CylinderBatchModuleScreen> createState() => _CylinderBatchModuleScreenState();
}

class _CylinderBatchModuleScreenState extends State<CylinderBatchModuleScreen> {
  List<CylinderBatchRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CylinderBatchStorage.getRecords();
    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([CylinderBatchRecord? record]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CylinderBatchEditorScreen(existingRecord: record)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Журнал цилиндров (ГОСТ 21153)'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Новая партия', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                          child: const Icon(Icons.view_column_outlined, size: 42, color: Color(0xFF2563EB)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Нет партий цилиндров',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Поточный электронный журнал: обмер (d, h), влажность, плотность (геометрическая и в воде), ультразвук и пресс (сжатие / растяжение).',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Создать партию', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    final isComp = r.strengthTestType == 0;
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
                                      r.batchTitle.isNotEmpty ? r.batchTitle : r.id,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isComp ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isComp ? 'Сжатие Rc' : 'Растяжение σp',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isComp ? const Color(0xFF2563EB) : const Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                                    onPressed: () async {
                                      await CylinderBatchStorage.deleteRecord(r.id);
                                      _load();
                                    },
                                  ),
                                ],
                              ),
                              Text(
                                '${r.lithotype.name} • Образцов: ${r.rows.length} • ${r.date}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Среднее ${isComp ? "Rc" : "σp"} = ${r.avgStrengthMpa.toStringAsFixed(1)} МПа'
                                '${r.avgDensityGcm3 != null ? ' • ρ = ${r.avgDensityGcm3!.toStringAsFixed(2)} г/см³' : ''}'
                                '${r.avgMoisturePercent != null ? ' • W = ${r.avgMoisturePercent!.toStringAsFixed(1)}%' : ''}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
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

class CylinderBatchEditorScreen extends StatefulWidget {
  final CylinderBatchRecord? existingRecord;
  const CylinderBatchEditorScreen({super.key, this.existingRecord});

  @override
  State<CylinderBatchEditorScreen> createState() => _CylinderBatchEditorScreenState();
}

class _CylinderBatchEditorScreenState extends State<CylinderBatchEditorScreen>
    with SingleTickerProviderStateMixin {
  late CylinderBatchRecord _record;
  late TabController _tabCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _boreholeCtrl;
  late TextEditingController _intervalCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    _record = widget.existingRecord ??
        CylinderBatchRecord(
          id: 'Партия #${now.millisecondsSinceEpoch.toString().substring(8)}',
          date: dateStr,
        );

    _titleCtrl = TextEditingController(text: _record.batchTitle);
    _boreholeCtrl = TextEditingController(text: _record.borehole);
    _intervalCtrl = TextEditingController(text: _record.interval);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _titleCtrl.dispose();
    _boreholeCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  void _syncHeader() {
    _record.batchTitle = _titleCtrl.text.trim();
    _record.borehole = _boreholeCtrl.text.trim();
    _record.interval = _intervalCtrl.text.trim();
  }

  void _addRow() {
    setState(() {
      _record.rows.add(CylinderSampleRow(cipher: '${_record.rows.length + 1}'));
    });
  }

  void _addFiveRows() {
    setState(() {
      final start = _record.rows.length;
      for (int i = 0; i < 5; i++) {
        _record.rows.add(CylinderSampleRow(cipher: '${start + i + 1}'));
      }
    });
  }

  Future<void> _save() async {
    _syncHeader();
    await CylinderBatchStorage.saveRecord(_record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFF059669), content: Text('Партия сохранена!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncHeader();
    final isComp = _record.strengthTestType == 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_record.batchTitle.isNotEmpty ? _record.batchTitle : 'Журнал партии'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download_outlined, color: Color(0xFF2563EB)),
            tooltip: 'Экспорт ведомости',
            onSelected: (val) async {
              await _save();
              if (!context.mounted) return;
              if (val == 'csv') {
                CylinderBatchStorage.exportCsv(context: context, record: _record);
              } else if (val == 'json') {
                CylinderBatchStorage.exportLimsJson(context: context, record: _record);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('Выгрузить в Excel (.csv)')),
              PopupMenuItem(value: 'json', child: Text('Пакет для ПК / LIMS (.json)')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Color(0xFF2563EB)),
            tooltip: 'Сохранить',
            onPressed: _save,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF2563EB),
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '1. Обмер (d, h)'),
            Tab(text: '2. Влажность / Плотность'),
            Tab(text: '3. Ультразвук'),
            Tab(text: '4. Пресс (P)'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Компактная шапка партии (сворачиваемая при необходимости)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Партия / Проба',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _record.lithotypeId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Порода',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: LithotypeDatabase.profiles
                            .map((p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.name.split('/').first.trim(), style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _record.lithotypeId = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        selected: isComp,
                        selectedColor: const Color(0xFF2563EB),
                        label: Text(
                          'Сжатие (ГОСТ 21153.2)',
                          style: TextStyle(fontSize: 11, color: isComp ? Colors.white : const Color(0xFF334155)),
                        ),
                        onSelected: (_) => setState(() => _record.strengthTestType = 0),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ChoiceChip(
                        selected: !isComp,
                        selectedColor: const Color(0xFF059669),
                        label: Text(
                          'Растяжение (ГОСТ 21153.3)',
                          style: TextStyle(fontSize: 11, color: !isComp ? Colors.white : const Color(0xFF334155)),
                        ),
                        onSelected: (_) => setState(() => _record.strengthTestType = 1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Содержимое 4 вкладок
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildGeometryTab(),
                _buildMoistureDensityTab(),
                _buildUltrasonicTab(),
                _buildPressTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('+1 образец', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _addFiveRows,
            icon: const Icon(Icons.playlist_add, size: 16),
            label: const Text('+5 образцов', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// ВКЛАДКА 1: Поточный обмер (только d и h без фанатизма)
  Widget _buildGeometryTab() {
    final isComp = _record.strengthTestType == 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        for (int i = 0; i < _record.rows.length; i++) _buildGeometryRowCard(i, isComp),
        _buildRowControls(),
      ],
    );
  }

  Widget _buildGeometryRowCard(int index, bool isComp) {
    final r = _record.rows[index];
    final ratio = r.hdRatio;
    final bool ratioWarn = ratio > 0 && (isComp ? (ratio < 1.75 || ratio > 2.25) : (ratio < 0.45 || ratio > 1.15));

    return Card(
      color: ratioWarn ? const Color(0xFFFFFBEB) : Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ratioWarn ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: const Color(0xFFEFF6FF),
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 82,
                  child: TextFormField(
                    initialValue: r.cipher,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Шифр',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    ),
                    onChanged: (v) => r.cipher = v.trim(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextFormField(
                    initialValue: r.diameterMm > 0 ? r.diameterMm.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'd, мм',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    ),
                    onChanged: (v) => setState(() => r.diameterMm = double.tryParse(v.replaceAll(',', '.')) ?? 0.0),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextFormField(
                    initialValue: r.heightMm > 0 ? r.heightMm.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'h, мм',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    ),
                    onChanged: (v) => setState(() => r.heightMm = double.tryParse(v.replaceAll(',', '.')) ?? 0.0),
                  ),
                ),
                if (_record.rows.length > 1)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                    onPressed: () => setState(() => _record.rows.removeAt(index)),
                  ),
              ],
            ),
            if (r.areaCm2 > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'A = ${r.areaCm2.toStringAsFixed(2)} см² • V = ${r.volumeCm3.toStringAsFixed(1)} см³',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                    ),
                    Text(
                      'h/d = ${ratio.toStringAsFixed(2)}${ratioWarn ? " (вне допуска)" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: ratioWarn ? const Color(0xFFD97706) : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ВКЛАДКА 2: Влажность и Плотность (Геометрическая или Гидростатическая в воде)
  Widget _buildMoistureDensityTab() {
    final rhoS = _record.lithotype.rhoSDefault;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        for (int i = 0; i < _record.rows.length; i++) _buildMoistureDensityCard(i, rhoS),
        _buildRowControls(),
      ],
    );
  }

  Widget _buildMoistureDensityCard(int index, double rhoS) {
    final r = _record.rows[index];
    final w = r.moisturePercent;
    final rho = r.densityGcm3;
    final rhoD = r.dryDensityGcm3;
    final nPct = r.porosityPercent(rhoS);

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
                Text(
                  'Образец #${index + 1} (${r.cipher.isNotEmpty ? r.cipher : "без шифра"})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                ),
                const Spacer(),
                if (rho != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'ρ = ${rho.toStringAsFixed(3)} г/см³',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Блок плотности: выбор между быстрой геометрической и точной в воде
            Row(
              children: [
                ChoiceChip(
                  selected: r.densityMethod == 0,
                  label: const Text('По размерам (m / V)', style: TextStyle(fontSize: 11)),
                  onSelected: (_) => setState(() => r.densityMethod = 0),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  selected: r.densityMethod == 1,
                  label: const Text('В воде (ГОСТ)', style: TextStyle(fontSize: 11)),
                  onSelected: (_) => setState(() => r.densityMethod = 1),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (r.densityMethod == 0)
              Row(
                children: [
                  Expanded(
                    child: _optNumField('Масса образца m, г', r.airMassG, (v) => setState(() => r.airMassG = v)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    r.volumeCm3 > 0 ? 'V = ${r.volumeCm3.toStringAsFixed(1)} см³' : 'Задайте d, h на 1-й вкладке',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _optNumField('m₁ воздух, г', r.airMassG, (v) => setState(() => r.airMassG = v)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _optNumField('m₂ параф. (опц.)', r.paraffinedMassG, (v) => setState(() => r.paraffinedMassG = v)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _optNumField('m₃ в воде, г', r.waterMassG, (v) => setState(() => r.waterMassG = v)),
                  ),
                ],
              ),

            const Divider(height: 16, color: Color(0xFFE2E8F0)),
            Row(
              children: [
                const Text('Влажность (бюкс):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                const Spacer(),
                if (w != null)
                  Text(
                    'W = ${w.toStringAsFixed(2)}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _optNumField('Пустой m₀', r.boxEmptyG, (v) => setState(() => r.boxEmptyG = v)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _optNumField('Влажн. m₁', r.boxWetG, (v) => setState(() => r.boxWetG = v)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _optNumField('Сухой m₂', r.boxDryG, (v) => setState(() => r.boxDryG = v)),
                ),
              ],
            ),
            if (rhoD != null || nPct != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${rhoD != null ? "Плотность скелета ρd = ${rhoD.toStringAsFixed(3)} г/см³" : ""}'
                  '${nPct != null ? " • Пористость n = ${nPct.toStringAsFixed(1)}%" : ""}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ВКЛАДКА 3: Ультразвук и трещиноватость (ГОСТ 21153.7-75)
  Widget _buildUltrasonicTab() {
    final fallbackRho = _record.lithotype.rhoSDefault;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        for (int i = 0; i < _record.rows.length; i++) _buildUltrasonicCard(i, fallbackRho),
        _buildRowControls(),
      ],
    );
  }

  Widget _buildUltrasonicCard(int index, double fallbackRho) {
    final r = _record.rows[index];
    final vp = r.vpMs;
    final vs = r.vsMs;
    final eDyn = r.dynamicEGpa(fallbackRho);
    final nuDyn = r.dynamicNu;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Образец #${index + 1} (${r.cipher.isNotEmpty ? r.cipher : "без шифра"})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: r.usBaseMm != null ? r.usBaseMm.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'База l (${r.heightMm > 0 ? r.heightMm.toStringAsFixed(1) : "мм"})',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => r.usBaseMm = double.tryParse(v.replaceAll(',', '.'))),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _optNumField('tp, мкс (прод.)', r.tpUs, (v) => setState(() => r.tpUs = v)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _optNumField('ts, мкс (попер.)', r.tsUs, (v) => setState(() => r.tsUs = v)),
                ),
              ],
            ),
            if (vp != null || vs != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vp = ${vp != null ? "${vp.toStringAsFixed(0)} м/с" : "—"}  |  Vs = ${vs != null ? "${vs.toStringAsFixed(0)} м/с" : "—"}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    if (eDyn != null && nuDyn != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'E дин = ${eDyn.toStringAsFixed(2)} ГПа  |  ν дин = ${nuDyn.toStringAsFixed(3)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ВКЛАДКА 4: Пресс (ввод разрушающей нагрузки P и сводный итог партии)
  Widget _buildPressTab() {
    final isComp = _record.strengthTestType == 0;
    final avgVal = _record.avgStrengthMpa;
    final varPct = _record.variationPercent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        // Сводный блок результатов партии
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isComp ? 'СРЕДНЕЕ СЖАТИЕ Rc' : 'СРЕДНЕЕ РАСТЯЖЕНИЕ σp',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    ),
                    Text(
                      avgVal > 0 ? '${avgVal.toStringAsFixed(1)} МПа' : '—',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: isComp ? const Color(0xFF2563EB) : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Испытано: ${_record.validStrengths.length} / ${_record.rows.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  if (_record.validStrengths.length >= 2)
                    Text(
                      'Вариация V = ${varPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: varPct > 25 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        for (int i = 0; i < _record.rows.length; i++) _buildPressRowCard(i, isComp),
        _buildRowControls(),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await _save();
              if (context.mounted) {
                CylinderBatchStorage.exportCsv(context: context, record: _record);
              }
            },
            icon: const Icon(Icons.table_view, size: 18),
            label: const Text('Сохранить партию и выгрузить в Excel', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildPressRowCard(int index, bool isComp) {
    final r = _record.rows[index];
    final resMpa = isComp ? r.compressionRcMpa : r.tensileSplittingMpa;
    final bool missingGeom = isComp ? (r.areaCm2 <= 0) : (r.diameterMm <= 0 || r.heightMm <= 0);

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFFF1F5F9),
              child: Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.cipher.isNotEmpty ? r.cipher : 'Образец #${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    missingGeom
                        ? 'Нет размеров d, h'
                        : 'd=${r.diameterMm.toStringAsFixed(1)}, h=${r.heightMm.toStringAsFixed(1)} мм',
                    style: TextStyle(fontSize: 11, color: missingGeom ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 96,
              child: TextFormField(
                initialValue: r.loadKn > 0 ? r.loadKn.toString() : '',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'P, кН',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (v) => setState(() => r.loadKn = double.tryParse(v.replaceAll(',', '.')) ?? 0.0),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    resMpa > 0 ? '${resMpa.toStringAsFixed(1)} МПа' : '—',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: isComp ? const Color(0xFF2563EB) : const Color(0xFF059669),
                    ),
                  ),
                  Text(isComp ? 'Rc' : 'σp', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optNumField(String label, double? initial, ValueChanged<double?> onChanged) {
    return TextFormField(
      initialValue: initial != null ? initial.toString() : '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      onChanged: (v) => onChanged(double.tryParse(v.trim().replaceAll(',', '.'))),
    );
  }
}
