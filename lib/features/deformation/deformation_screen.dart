import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'lithotype_db.dart';

class IndentorTrial {
  double p1Kn;
  double p2Kn;
  double h1Mm;        // Итоговое (или среднее) сближение при P1, мм
  double h2Mm;        // Итоговое (или среднее) сближение при P2, мм
  double h1UnloadMm;  // Остаточная деформация при разгрузке до P1, мм

  // Опциональные показания с 2 отдельных датчиков LVDT (Канал 1 и Канал 2 в EVOTest)
  double? h1Ch1Mm;
  double? h1Ch2Mm;
  double? h2Ch1Mm;
  double? h2Ch2Mm;
  double? h1UnloadCh1Mm;
  double? h1UnloadCh2Mm;

  IndentorTrial({
    this.p1Kn = 0.0,
    this.p2Kn = 0.0,
    this.h1Mm = 0.0,
    this.h2Mm = 0.0,
    this.h1UnloadMm = 0.0,
    this.h1Ch1Mm,
    this.h1Ch2Mm,
    this.h2Ch1Mm,
    this.h2Ch2Mm,
    this.h1UnloadCh1Mm,
    this.h1UnloadCh2Mm,
  });

  /// Проверка перекоса между левым и правым датчиками LVDT (%)
  double get skewPercent {
    if (h2Ch1Mm == null || h2Ch2Mm == null) return 0.0;
    final avg = (h2Ch1Mm! + h2Ch2Mm!) / 2.0;
    if (avg <= 0.005) return 0.0;
    return ((h2Ch1Mm! - h2Ch2Mm!).abs() / avg) * 100.0;
  }

  Map<String, dynamic> toJson() => {
        'p1Kn': p1Kn,
        'p2Kn': p2Kn,
        'h1Mm': h1Mm,
        'h2Mm': h2Mm,
        'h1UnloadMm': h1UnloadMm,
        'h1Ch1Mm': h1Ch1Mm,
        'h1Ch2Mm': h1Ch2Mm,
        'h2Ch1Mm': h2Ch1Mm,
        'h2Ch2Mm': h2Ch2Mm,
        'h1UnloadCh1Mm': h1UnloadCh1Mm,
        'h1UnloadCh2Mm': h1UnloadCh2Mm,
      };

  factory IndentorTrial.fromJson(Map<String, dynamic> json) => IndentorTrial(
        p1Kn: (json['p1Kn'] as num?)?.toDouble() ?? 0.0,
        p2Kn: (json['p2Kn'] as num?)?.toDouble() ?? 0.0,
        h1Mm: (json['h1Mm'] as num?)?.toDouble() ?? 0.0,
        h2Mm: (json['h2Mm'] as num?)?.toDouble() ?? 0.0,
        h1UnloadMm: (json['h1UnloadMm'] as num?)?.toDouble() ?? 0.0,
        h1Ch1Mm: (json['h1Ch1Mm'] as num?)?.toDouble(),
        h1Ch2Mm: (json['h1Ch2Mm'] as num?)?.toDouble(),
        h2Ch1Mm: (json['h2Ch1Mm'] as num?)?.toDouble(),
        h2Ch2Mm: (json['h2Ch2Mm'] as num?)?.toDouble(),
        h1UnloadCh1Mm: (json['h1UnloadCh1Mm'] as num?)?.toDouble(),
        h1UnloadCh2Mm: (json['h1UnloadCh2Mm'] as num?)?.toDouble(),
      );
}

class DeformationRecord {
  final String id;
  final String date;
  String cipher;
  String borehole;
  String interval;
  String lithotypeId;
  String condition;
  int methodBranch; // 0 = Сферические инденторы, 1 = Протодьяконов + пористость
  bool useDualLvdtSensors; // true = 2 датчика LVDT (Канал 1 и Канал 2 без податливости станины)

  double sphereRadiusMm;
  double frameComplianceMmPerKn;
  double? knownRcMpa;
  List<IndentorTrial> trials;

  double? protodyakonovF;
  double? rhoDGcm3;
  double? rhoSGcm3;

  DeformationRecord({
    required this.id,
    required this.date,
    this.cipher = '',
    this.borehole = '',
    this.interval = '',
    this.lithotypeId = 'unknown_rock',
    this.condition = 'n',
    this.methodBranch = 0,
    this.useDualLvdtSensors = true,
    this.sphereRadiusMm = 7.5,
    this.frameComplianceMmPerKn = 0.0,
    this.knownRcMpa,
    List<IndentorTrial>? trials,
    this.protodyakonovF,
    this.rhoDGcm3,
    this.rhoSGcm3,
  }) : trials = trials ?? [IndentorTrial()];

  LithotypeProfile get lithotype => LithotypeDatabase.getById(lithotypeId);

  double get effectiveCompliance => useDualLvdtSensors ? 0.0 : frameComplianceMmPerKn;

  double? get porosityPercent {
    final rhoS = (rhoSGcm3 != null && rhoSGcm3! > 1.0) ? rhoSGcm3! : lithotype.rhoSDefault;
    if (rhoDGcm3 != null && rhoDGcm3! > 0.5 && rhoDGcm3! < rhoS) {
      return ((rhoS - rhoDGcm3!) / rhoS) * 100.0;
    }
    return null;
  }

  double get recommendedP1Kn {
    if (knownRcMpa != null && knownRcMpa! > 0) {
      final pMaxEst = (knownRcMpa! * 2.5) / 14.0;
      return (pMaxEst * 0.15).clamp(0.3, 15.0);
    }
    return 1.5;
  }

  double get recommendedP2Kn {
    if (knownRcMpa != null && knownRcMpa! > 0) {
      final pMaxEst = (knownRcMpa! * 2.5) / 14.0;
      return (pMaxEst * 0.55).clamp(1.0, 55.0);
    }
    return 6.0;
  }

  Map<String, double> calculate() {
    final profile = lithotype;
    double eGpa = 0.0;
    double e0Gpa = 0.0;
    double nu = profile.nu0;
    double mu = profile.nu0;

    final nPct = porosityPercent;
    if (nPct != null) {
      nu = (profile.nu0 + 0.0025 * nPct).clamp(0.12, 0.42);
    }
    if (condition == 'w') {
      nu = (nu + 0.02).clamp(0.12, 0.45);
    }

    if (methodBranch == 0) {
      final List<double> eList = [];
      final List<double> e0List = [];
      final double rMm = sphereRadiusMm > 0 ? sphereRadiusMm : 7.5;
      final double oneMinusNu2 = 1.0 - nu * nu;
      final double comp = effectiveCompliance;

      for (final t in trials) {
        final dpKn = t.p2Kn - t.p1Kn;
        if (dpKn <= 0.05) continue;

        final dhTotalRaw = (t.h2Mm - t.h1Mm) - (dpKn * comp);
        if (dhTotalRaw > 0.002) {
          final double dhHalf = dhTotalRaw / 2.0;
          final double dpN = dpKn * 1000.0;
          final double e0Mpa = (0.75 * dpN * oneMinusNu2) / (math.sqrt(rMm) * math.pow(dhHalf, 1.5));
          e0List.add(e0Mpa / 1000.0);
        }

        final baseH = (t.h1UnloadMm > t.h1Mm) ? t.h1UnloadMm : t.h1Mm;
        final dhElasticRaw = (t.h2Mm - baseH) - (dpKn * comp);
        if (dhElasticRaw > 0.002) {
          final double dhHalfEl = dhElasticRaw / 2.0;
          final double dpN = dpKn * 1000.0;
          final double eMpa = (0.75 * dpN * oneMinusNu2) / (math.sqrt(rMm) * math.pow(dhHalfEl, 1.5));
          eList.add(eMpa / 1000.0);
        }
      }

      if (e0List.isNotEmpty) {
        e0Gpa = e0List.reduce((a, b) => a + b) / e0List.length;
      }
      if (eList.isNotEmpty) {
        eGpa = eList.reduce((a, b) => a + b) / eList.length;
      } else if (e0Gpa > 0) {
        eGpa = e0Gpa / profile.kElasticBase;
      }
      if (e0Gpa > eGpa && eGpa > 0) {
        e0Gpa = eGpa;
      }
    } else {
      final f = protodyakonovF ?? 0.0;
      if (f > 0) {
        final double rcEstMpa = f * 10.0;
        if (nPct != null) {
          final double ePorosity = profile.eSkeletonGpa * math.exp(-profile.porosityDecayB * nPct);
          final double eStrength = (profile.alphaLit * rcEstMpa) / 1000.0;
          eGpa = 0.65 * ePorosity + 0.35 * eStrength;
        } else {
          eGpa = (profile.alphaLit * rcEstMpa) / 1000.0;
        }

        if (condition == 'w') {
          eGpa *= profile.softeningFactor;
        }

        final double kEl = nPct != null
            ? (profile.kElasticBase - 0.004 * nPct).clamp(0.45, 0.95)
            : profile.kElasticBase;
        e0Gpa = eGpa * kEl;
      }
    }

    if (eGpa > 0 && e0Gpa > 0) {
      final double plasticShare = (1.0 - (e0Gpa / eGpa)).clamp(0.0, 0.55);
      mu = (nu + (0.50 - nu) * plasticShare).clamp(nu, 0.49);
    } else {
      mu = nu;
    }

    return {
      'E': eGpa,
      'E0': e0Gpa,
      'nu': nu,
      'mu': mu,
      'nPct': nPct ?? -1.0,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'cipher': cipher,
        'borehole': borehole,
        'interval': interval,
        'lithotypeId': lithotypeId,
        'condition': condition,
        'methodBranch': methodBranch,
        'useDualLvdtSensors': useDualLvdtSensors,
        'sphereRadiusMm': sphereRadiusMm,
        'frameComplianceMmPerKn': frameComplianceMmPerKn,
        'knownRcMpa': knownRcMpa,
        'trials': trials.map((t) => t.toJson()).toList(),
        'protodyakonovF': protodyakonovF,
        'rhoDGcm3': rhoDGcm3,
        'rhoSGcm3': rhoSGcm3,
      };

  factory DeformationRecord.fromJson(Map<String, dynamic> json) => DeformationRecord(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        cipher: json['cipher'] as String? ?? '',
        borehole: json['borehole'] as String? ?? '',
        interval: json['interval'] as String? ?? '',
        lithotypeId: json['lithotypeId'] as String? ?? 'unknown_rock',
        condition: json['condition'] as String? ?? 'n',
        methodBranch: (json['methodBranch'] as num?)?.toInt() ?? 0,
        useDualLvdtSensors: json['useDualLvdtSensors'] as bool? ?? true,
        sphereRadiusMm: (json['sphereRadiusMm'] as num?)?.toDouble() ?? 7.5,
        frameComplianceMmPerKn: (json['frameComplianceMmPerKn'] as num?)?.toDouble() ?? 0.0,
        knownRcMpa: (json['knownRcMpa'] as num?)?.toDouble(),
        trials: (json['trials'] as List<dynamic>?)
            ?.map((e) => IndentorTrial.fromJson(e as Map<String, dynamic>))
            .toList(),
        protodyakonovF: (json['protodyakonovF'] as num?)?.toDouble(),
        rhoDGcm3: (json['rhoDGcm3'] as num?)?.toDouble(),
        rhoSGcm3: (json['rhoSGcm3'] as num?)?.toDouble(),
      );
}

class DeformationStorageService {
  static const String _key = 'rockarea_deformation_records';

  static Future<List<DeformationRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => DeformationRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecord(DeformationRecord record) async {
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
    required DeformationRecord record,
  }) async {
    final res = record.calculate();
    final sb = StringBuffer();
    sb.write('ВЕДОМОСТЬ ДЕФОРМАЦИОННЫХ ХАРАКТЕРИСТИК (ГОСТ 24941-81 / ГОСТ Р 59958-2021)\r\n');
    sb.write('Шифр пробы;${record.cipher.isNotEmpty ? record.cipher : record.id};Дата;${record.date}\r\n');
    sb.write('Скважина;${record.borehole};Интервал;${record.interval};Состояние;${record.condition}\r\n');
    sb.write('Литотип;${record.lithotype.name};Метод;${record.methodBranch == 0 ? (record.useDualLvdtSensors ? "Инденторы + 2 датчика LVDT" : "Инденторы (траверса)") : "Протодьяконов + пористость"}\r\n');
    sb.write('\r\n');
    sb.write('Модуль упругости E, ГПа;Модуль деформации E0, ГПа;Коэф. Пуассона v;Коэф. поперечной деформации mu;Пористость n, %\r\n');
    sb.write(
      '${res['E']!.toStringAsFixed(2)};'
      '${res['E0']!.toStringAsFixed(2)};'
      '${res['nu']!.toStringAsFixed(3)};'
      '${res['mu']!.toStringAsFixed(3)};'
      '${res['nPct']! >= 0 ? res['nPct']!.toStringAsFixed(1) : "-"}\r\n',
    );

    if (record.methodBranch == 0) {
      sb.write('\r\n');
      sb.write('Опыт;P1, кН;P2, кН;h1 ср., мм;h2 ср., мм;h1 разгр., мм;h2 кан.1, мм;h2 кан.2, мм;Перекос, %\r\n');
      for (int i = 0; i < record.trials.length; i++) {
        final t = record.trials[i];
        sb.write(
          '${i + 1};${t.p1Kn};${t.p2Kn};${t.h1Mm};${t.h2Mm};${t.h1UnloadMm};'
          '${t.h2Ch1Mm ?? "-"};${t.h2Ch2Mm ?? "-"};${t.skewPercent.toStringAsFixed(1)}\r\n',
        );
      }
    }

    final formatted = 'sep=;\r\n${sb.toString()}';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(formatted)];
    final safeCipher = (record.cipher.isNotEmpty ? record.cipher : record.id).replaceAll(RegExp(r'[^\w\dА-Яа-я]'), '_');
    final filename = 'Деформации_$safeCipher.csv';

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

class DeformationModuleScreen extends StatefulWidget {
  const DeformationModuleScreen({super.key});

  @override
  State<DeformationModuleScreen> createState() => _DeformationModuleScreenState();
}

class _DeformationModuleScreenState extends State<DeformationModuleScreen> {
  List<DeformationRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DeformationStorageService.getRecords();
    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([DeformationRecord? record]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeformationEditorScreen(existingRecord: record)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Деформационные характеристики'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2563EB),
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
                          decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                          child: const Icon(Icons.architecture, size: 42, color: Color(0xFF2563EB)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Нет сохранённых испытаний',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Расчёт модулей E, E₀ и коэффициентов ν, μ по сферическим инденторам (с поддержкой 2 датчиков LVDT) или по копру Протодьяконова.',
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
                          label: const Text('Начать расчёт', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    final res = r.calculate();
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
                                      color: r.methodBranch == 0 ? const Color(0xFFEFF6FF) : const Color(0xFFFFF7ED),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      r.methodBranch == 0
                                          ? (r.useDualLvdtSensors ? '2 датчика LVDT' : 'Инденторы')
                                          : 'Протодьяконов',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: r.methodBranch == 0 ? const Color(0xFF2563EB) : const Color(0xFFEA580C),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                                    onPressed: () async {
                                      await DeformationStorageService.deleteRecord(r.id);
                                      _load();
                                    },
                                  ),
                                ],
                              ),
                              Text('${r.lithotype.name} • ${r.date}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _miniStat('E', '${res['E']!.toStringAsFixed(1)} ГПа'),
                                  _miniStat('E₀', '${res['E0']!.toStringAsFixed(1)} ГПа'),
                                  _miniStat('ν', res['nu']!.toStringAsFixed(3)),
                                  _miniStat('μ', res['mu']!.toStringAsFixed(3)),
                                ],
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

  Widget _miniStat(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
        Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
      ],
    );
  }
}

class DeformationEditorScreen extends StatefulWidget {
  final DeformationRecord? existingRecord;
  const DeformationEditorScreen({super.key, this.existingRecord});

  @override
  State<DeformationEditorScreen> createState() => _DeformationEditorScreenState();
}

class _DeformationEditorScreenState extends State<DeformationEditorScreen> {
  late DeformationRecord _record;
  late TextEditingController _cipherCtrl;
  late TextEditingController _boreholeCtrl;
  late TextEditingController _intervalCtrl;
  late TextEditingController _sphereRadiusCtrl;
  late TextEditingController _complianceCtrl;
  late TextEditingController _knownRcCtrl;
  late TextEditingController _protoFCtrl;
  late TextEditingController _rhoDCtrl;
  late TextEditingController _rhoSCtrl;
  bool _showLvdtGuide = false;
  bool _manualTwoChannels = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    _record = widget.existingRecord ??
        DeformationRecord(
          id: 'Деф #${now.millisecondsSinceEpoch.toString().substring(8)}',
          date: dateStr,
        );

    _cipherCtrl = TextEditingController(text: _record.cipher);
    _boreholeCtrl = TextEditingController(text: _record.borehole);
    _intervalCtrl = TextEditingController(text: _record.interval);
    _sphereRadiusCtrl = TextEditingController(text: _record.sphereRadiusMm.toString());
    _complianceCtrl = TextEditingController(text: _record.frameComplianceMmPerKn.toString());
    _knownRcCtrl = TextEditingController(text: _record.knownRcMpa?.toString() ?? '');
    _protoFCtrl = TextEditingController(text: _record.protodyakonovF?.toString() ?? '');
    _rhoDCtrl = TextEditingController(text: _record.rhoDGcm3?.toString() ?? '');
    _rhoSCtrl = TextEditingController(text: _record.rhoSGcm3?.toString() ?? '');
  }

  @override
  void dispose() {
    _cipherCtrl.dispose();
    _boreholeCtrl.dispose();
    _intervalCtrl.dispose();
    _sphereRadiusCtrl.dispose();
    _complianceCtrl.dispose();
    _knownRcCtrl.dispose();
    _protoFCtrl.dispose();
    _rhoDCtrl.dispose();
    _rhoSCtrl.dispose();
    super.dispose();
  }

  double? _parseOpt(String text) {
    final v = text.trim().replaceAll(',', '.');
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  void _syncInputs() {
    _record.cipher = _cipherCtrl.text.trim();
    _record.borehole = _boreholeCtrl.text.trim();
    _record.interval = _intervalCtrl.text.trim();
    _record.sphereRadiusMm = _parseOpt(_sphereRadiusCtrl.text) ?? 7.5;
    _record.frameComplianceMmPerKn = _parseOpt(_complianceCtrl.text) ?? 0.0;
    _record.knownRcMpa = _parseOpt(_knownRcCtrl.text);
    _record.protodyakonovF = _parseOpt(_protoFCtrl.text);
    _record.rhoDGcm3 = _parseOpt(_rhoDCtrl.text);
    _record.rhoSGcm3 = _parseOpt(_rhoSCtrl.text);
  }

  void _recalcTrialFromChannels(IndentorTrial t) {
    if (t.h1Ch1Mm != null && t.h1Ch2Mm != null) {
      t.h1Mm = (t.h1Ch1Mm! + t.h1Ch2Mm!) / 2.0;
    }
    if (t.h2Ch1Mm != null && t.h2Ch2Mm != null) {
      t.h2Mm = (t.h2Ch1Mm! + t.h2Ch2Mm!) / 2.0;
    }
    if (t.h1UnloadCh1Mm != null && t.h1UnloadCh2Mm != null) {
      t.h1UnloadMm = (t.h1UnloadCh1Mm! + t.h1UnloadCh2Mm!) / 2.0;
    }
  }

  Future<void> _save() async {
    _syncInputs();
    await DeformationStorageService.saveRecord(_record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFF059669), content: Text('Расчёт сохранён!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncInputs();
    final res = _record.calculate();
    final eVal = res['E']!;
    final e0Val = res['E0']!;
    final nuVal = res['nu']!;
    final muVal = res['mu']!;
    final nPct = res['nPct']!;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_record.cipher.isNotEmpty ? _record.cipher : 'Расчёт деформаций'),
        actions: [
          IconButton(
            icon: Icon(_showLvdtGuide ? Icons.help : Icons.help_outline, color: const Color(0xFF2563EB)),
            tooltip: 'Инструкция по датчикам LVDT (EWT-300X)',
            onPressed: () => setState(() => _showLvdtGuide = !_showLvdtGuide),
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
          if (_showLvdtGuide)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(14)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'РАБОТА С 2 ДАТЧИКАМИ LVDT НА ПРЕССЕ EWT-300X',
                    style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '1. Закрепите оба датчика слева и справа на нижней платформе оснастки так, чтобы их штоки упирались в верхнюю траверсу оснастки с преднатягом 3–5 мм.\n'
                    '2. В программе EVOTest проверьте табло «Деформация (mm) / Большая деформация»: при нажатии на штоки должны меняться Каналы 1 и 2.\n'
                    '3. Обнулите деформацию перед контактом сфер с образцом.\n'
                    '4. Податливость станины при работе с LVDT автоматически обнулена (0.000), так как датчики меряют чистое сближение инденторов.',
                    style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, height: 1.45),
                  ),
                ],
              ),
            ),

          // Шаг 1: Паспорт и Литотип
          _sectionHeader('1. ПАСПОРТ ОБРАЗЦА И ПОРОДА'),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _cipherCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Шифр пробы',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _record.condition,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Сост.',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'n', child: Text('n (ест.)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'w', child: Text('w (вод.)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'h', child: Text('h (сух.)', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _record.condition = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _record.lithotypeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Литологический тип (БД упругих параметров)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: LithotypeDatabase.profiles
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _record.lithotypeId = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Шаг 2: Выбор ветки испытания
          _sectionHeader('2. МЕТОДИКА ИСПЫТАНИЯ'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                icon: Icon(Icons.radio_button_checked, size: 16),
                label: Text('Инденторы (ГОСТ)', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: Icon(Icons.hardware, size: 16),
                label: Text('Протодьяконов + ρ', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {_record.methodBranch},
            onSelectionChanged: (set) => setState(() => _record.methodBranch = set.first),
          ),
          const SizedBox(height: 12),

          if (_record.methodBranch == 0) ...[
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: const Color(0xFF059669),
                      title: const Text(
                        'Внешние датчики LVDT (Канал 1 + Канал 2)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                      subtitle: Text(
                        _record.useDualLvdtSensors
                            ? 'Включено: податливость станины = 0 (чистое сближение сфер)'
                            : 'Выключено: замер по траверсе с поправкой на жесткость рамы',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      value: _record.useDualLvdtSensors,
                      onChanged: (val) => setState(() => _record.useDualLvdtSensors = val),
                    ),
                    if (_record.useDualLvdtSensors)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('Среднее EVOTest', style: TextStyle(fontSize: 11)),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Кан. 1 и Кан. 2', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                          selected: {_manualTwoChannels},
                          onSelectionChanged: (set) => setState(() => _manualTwoChannels = set.first),
                        ),
                      ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sphereRadiusCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Радиус сферы R (мм)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _record.useDualLvdtSensors
                              ? TextField(
                                  controller: _knownRcCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Ожид. Rc (МПа)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                )
                              : TextField(
                                  controller: _complianceCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Податл. рамы (мм/кН)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        'Рекомендуемые ступени: P₁ ≈ ${_record.recommendedP1Kn.toStringAsFixed(1)} кН, P₂ ≈ ${_record.recommendedP2Kn.toStringAsFixed(1)} кН',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            for (int i = 0; i < _record.trials.length; i++)
              _buildTrialCard(i),

            TextButton.icon(
              onPressed: () => setState(() => _record.trials.add(IndentorTrial())),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Добавить параллельный образец серии'),
            ),
          ] else ...[
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: _protoFCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Коэффициент крепости f (по Протодьяконову)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _rhoDCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Плотность скелета ρd (г/см³)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _rhoSCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Плотн. частиц ρs (${_record.lithotype.rhoSDefault})',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Шаг 3: Итоговая панель
          _sectionHeader('3. РЕЗУЛЬТАТЫ РАСЧЁТА'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        'Модуль упругости E',
                        eVal > 0 ? '${eVal.toStringAsFixed(2)} ГПа' : '—',
                        const Color(0xFF2563EB),
                        const Color(0xFFEFF6FF),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        'Модуль деформации E₀',
                        e0Val > 0 ? '${e0Val.toStringAsFixed(2)} ГПа' : '—',
                        const Color(0xFF059669),
                        const Color(0xFFECFDF5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        'Коэф. Пуассона ν',
                        nuVal.toStringAsFixed(3),
                        const Color(0xFF0F172A),
                        const Color(0xFFF1F5F9),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        'Попереч. деф. μ',
                        muVal.toStringAsFixed(3),
                        const Color(0xFFEA580C),
                        const Color(0xFFFFF7ED),
                      ),
                    ),
                  ],
                ),
                if (nPct >= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Расчётная пористость образца: n = ${nPct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
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
                    onPressed: () async {
                      await _save();
                      if (context.mounted) {
                        DeformationStorageService.exportCsv(context: context, record: _record);
                      }
                    },
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

  Widget _buildTrialCard(int index) {
    final t = _record.trials[index];
    final skew = t.skewPercent;
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Образец #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if (_record.trials.length > 1)
                  InkWell(
                    onTap: () => setState(() => _record.trials.removeAt(index)),
                    child: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _numField(
                    'P₁ (кН)',
                    t.p1Kn,
                    (v) => setState(() => t.p1Kn = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numField(
                    'P₂ (кН)',
                    t.p2Kn,
                    (v) => setState(() => t.p2Kn = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_record.useDualLvdtSensors && _manualTwoChannels) ...[
              const Text('Показания LVDT при P₁ (мм):', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _numField('h₁ Кан.1', t.h1Ch1Mm ?? 0.0, (v) {
                      setState(() {
                        t.h1Ch1Mm = v;
                        _recalcTrialFromChannels(t);
                      });
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _numField('h₁ Кан.2', t.h1Ch2Mm ?? 0.0, (v) {
                      setState(() {
                        t.h1Ch2Mm = v;
                        _recalcTrialFromChannels(t);
                      });
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Показания LVDT при P₂ (мм):', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _numField('h₂ Кан.1', t.h2Ch1Mm ?? 0.0, (v) {
                      setState(() {
                        t.h2Ch1Mm = v;
                        _recalcTrialFromChannels(t);
                      });
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _numField('h₂ Кан.2', t.h2Ch2Mm ?? 0.0, (v) {
                      setState(() {
                        t.h2Ch2Mm = v;
                        _recalcTrialFromChannels(t);
                      });
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _numField('h₁ разгр. ср. (мм)', t.h1UnloadMm, (v) => setState(() => t.h1UnloadMm = v)),
              if (skew > 25.0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Внимание: перекос между датчиками ${skew.toStringAsFixed(0)}% (>25%). Проверьте центрирование куска.',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFEA580C), fontWeight: FontWeight.w600),
                  ),
                ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _numField('h₁ (мм)', t.h1Mm, (v) => setState(() => t.h1Mm = v)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _numField('h₂ (мм)', t.h2Mm, (v) => setState(() => t.h2Mm = v)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _numField('h₁ разгр.', t.h1UnloadMm, (v) => setState(() => t.h1UnloadMm = v)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _numField(String label, double initial, ValueChanged<double> onChanged) {
    return TextFormField(
      initialValue: initial > 0 ? initial.toString() : '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      onChanged: (v) => onChanged(double.tryParse(v.replaceAll(',', '.')) ?? 0.0),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.8),
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
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: accent)),
        ],
      ),
    );
  }
}
