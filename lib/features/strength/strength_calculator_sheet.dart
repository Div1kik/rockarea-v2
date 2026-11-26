import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/export_service.dart';
import '../deformation/lithotype_db.dart';

class SampleStrengthData {
  String part1;
  String part2;
  String part3;
  String borehole;
  String interval;
  String condition;
  String lithology;
  double areaCm2;
  double loadKn;

  SampleStrengthData({
    this.part1 = '',
    this.part2 = '',
    this.part3 = '',
    this.borehole = '-',
    this.interval = '-',
    this.condition = 'n',
    this.lithology = '-',
    required this.areaCm2,
    this.loadKn = 0.0,
  });

  double get coeffK => areaCm2 > 0 ? 0.5076 * math.pow(areaCm2, 0.2506) : 0.0;
  double get tensileStrengthMpa => areaCm2 > 0 ? (7.5 * loadKn * coeffK) / areaCm2 : 0.0;

  /// Классический ступенчатый коэффициент по ГОСТ 24941-81 (12 / 16 / 20)
  double get conversionCoeff {
    final m = tensileStrengthMpa;
    if (m <= 0) return 0.0;
    if (m < 1.0) return 12.0;
    if (m < 5.0) return 16.0;
    return 20.0;
  }

  double get compStrengthMpa => tensileStrengthMpa * conversionCoeff;

  /// Комбинированный коэффициент пересчета: базовый К литотипа * плавный индекс сохранности по sigma_p
  double combinedConversionCoeff(LithotypeProfile profile) {
    final m = tensileStrengthMpa;
    if (m <= 0) return 0.0;
    final double integrityFactor = math.min(1.05, 0.65 + 0.22 * math.log(m + 1.0));
    return profile.kConversionBase * integrityFactor;
  }

  double combinedCompStrengthMpa(LithotypeProfile profile) {
    return tensileStrengthMpa * combinedConversionCoeff(profile);
  }
}

class StrengthCalculatorSheet extends StatefulWidget {
  final String title;
  final List<SampleStrengthData> initialSamples;
  final ValueChanged<List<SampleStrengthData>> onSaved;

  const StrengthCalculatorSheet({
    super.key,
    this.title = 'Результаты испытаний',
    required this.initialSamples,
    required this.onSaved,
  });

  @override
  State<StrengthCalculatorSheet> createState() => _StrengthCalculatorSheetState();
}

class _StrengthCalculatorSheetState extends State<StrengthCalculatorSheet> {
  late List<SampleStrengthData> _samples;
  bool _useLithotypeMode = false;
  String _selectedLithotypeId = 'unknown_rock';

  @override
  void initState() {
    super.initState();
    _samples = widget.initialSamples;
  }

  LithotypeProfile get _activeProfile => LithotypeDatabase.getById(_selectedLithotypeId);

  double get _avgTensile {
    final valid = _samples.where((s) => s.tensileStrengthMpa > 0).toList();
    if (valid.isEmpty) return 0.0;
    return valid.map((s) => s.tensileStrengthMpa).reduce((a, b) => a + b) / valid.length;
  }

  double get _avgComp {
    if (_useLithotypeMode) {
      final profile = _activeProfile;
      final valid = _samples.where((s) => s.combinedCompStrengthMpa(profile) > 0).toList();
      if (valid.isEmpty) return 0.0;
      return valid.map((s) => s.combinedCompStrengthMpa(profile)).reduce((a, b) => a + b) / valid.length;
    } else {
      final valid = _samples.where((s) => s.compStrengthMpa > 0).toList();
      if (valid.isEmpty) return 0.0;
      return valid.map((s) => s.compStrengthMpa).reduce((a, b) => a + b) / valid.length;
    }
  }

  void _applyLithotypeToSamples(String newId) {
    final profile = LithotypeDatabase.getById(newId);
    setState(() {
      _selectedLithotypeId = newId;
      for (final s in _samples) {
        s.lithology = profile.name.split('/').first.trim();
      }
    });
  }

  void _editSample(int index) {
    final s = _samples[index];
    final initialCipher = [s.part1, s.part2, s.part3].where((e) => e.isNotEmpty).join(' ');
    final cipherCtrl = TextEditingController(text: initialCipher);
    final loadCtrl = TextEditingController(text: s.loadKn > 0 ? s.loadKn.toString() : '');
    String condition = s.condition;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Образец #${index + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Шифр пробы (через пробел):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: cipherCtrl,
                  decoration: const InputDecoration(
                    hintText: 'БАМ 1 1',
                    hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Площадь скола S: ${s.areaCm2.toStringAsFixed(2)} см²',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                const SizedBox(height: 12),
                const Text('Разрушающая нагрузка P (кН):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: loadCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Состояние:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                DropdownButton<String>(
                  value: condition,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'n', child: Text('n — естественная влажность')),
                    DropdownMenuItem(value: 'w', child: Text('w — водонасыщенное')),
                    DropdownMenuItem(value: 'h', child: Text('h — воздушно-сухое')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => condition = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              onPressed: () {
                final raw = cipherCtrl.text.trim().split(RegExp(r'\s+'));
                setState(() {
                  s.part1 = raw.isNotEmpty ? raw[0] : '';
                  s.part2 = raw.length > 1 ? raw[1] : '';
                  s.part3 = raw.length > 2 ? raw[2] : '';
                  s.loadKn = double.tryParse(loadCtrl.text.replaceAll(',', '.')) ?? 0.0;
                  s.condition = condition;
                });
                Navigator.pop(ctx);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _activeProfile;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: Color(0xFF2563EB)),
            tooltip: 'Мгновенный экспорт в Загрузки',
            onPressed: () => ExportService.exportGostProtocol(
              context: context,
              seriesId: widget.title,
              samples: _samples,
              avgTensile: _avgTensile,
              avgComp: _avgComp,
              useLithotypeConversion: _useLithotypeMode,
              lithotypeProfile: _useLithotypeMode ? profile : null,
              shareImmediately: false,
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () {
              widget.onSaved(_samples);
              Navigator.pop(context);
            },
            child: const Text('Готово'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Переключатель методики пересчета: ГОСТ 24941-81 vs Комбинированный (Литотип + sigma_p)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.rule, size: 16),
                      label: Text('ГОСТ 24941 (12/16/20)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.layers_outlined, size: 16),
                      label: Text('Литотип + σp (комб.)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  selected: {_useLithotypeMode},
                  onSelectionChanged: (set) {
                    setState(() {
                      _useLithotypeMode = set.first;
                      if (_useLithotypeMode) {
                        _applyLithotypeToSamples(_selectedLithotypeId);
                      }
                    });
                  },
                ),
                if (_useLithotypeMode) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedLithotypeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Порода (Kлит + поправка на прочность σp)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: LithotypeDatabase.profiles
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.name} (Kлит=${p.kConversionBase.toStringAsFixed(1)})',
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _applyLithotypeToSamples(val);
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Сводная панель средних значений
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('СР. РАСТЯЖЕНИЕ σp', style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                      Text('${_avgTensile.toStringAsFixed(2)} МПа', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    ],
                  ),
                ),
                Container(width: 1, height: 35, color: const Color(0xFFE2E8F0)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _useLithotypeMode ? 'СР. СЖАТИЕ Rc (ЛИТОТИП)' : 'СР. СЖАТИЕ Rc (ГОСТ)',
                        style: TextStyle(
                          fontSize: 9,
                          color: _useLithotypeMode ? const Color(0xFF059669) : const Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_avgComp.toStringAsFixed(1)} МПа',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _useLithotypeMode ? const Color(0xFF059669) : const Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Список образцов
          Expanded(
            child: ListView.separated(
              itemCount: _samples.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
              itemBuilder: (ctx, idx) {
                final s = _samples[idx];
                final cipherLabel = [s.part1, s.part2, s.part3].where((e) => e.isNotEmpty).join(' ');
                final double activeRc = _useLithotypeMode ? s.combinedCompStrengthMpa(profile) : s.compStrengthMpa;
                final double activeK = _useLithotypeMode ? s.combinedConversionCoeff(profile) : s.conversionCoeff;

                return ListTile(
                  tileColor: Colors.white,
                  dense: true,
                  onTap: () => _editSample(idx),
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: _useLithotypeMode ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _useLithotypeMode ? const Color(0xFF059669) : const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(cipherLabel.isNotEmpty ? cipherLabel : 'Шифр не задан',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cipherLabel.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF94A3B8))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                        child: Text(s.condition, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'S = ${s.areaCm2.toStringAsFixed(2)} см² | P = ${s.loadKn > 0 ? '${s.loadKn} кН' : 'не задана'}'
                    '${activeK > 0 ? ' | Kпер = ${activeK.toStringAsFixed(1)}' : ''}',
                    style: TextStyle(fontSize: 11, color: s.loadKn > 0 ? const Color(0xFF64748B) : const Color(0xFFDC2626)),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rc: ${activeRc.toStringAsFixed(1)} МПа',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _useLithotypeMode ? const Color(0xFF059669) : const Color(0xFF2563EB),
                        ),
                      ),
                      Text(
                        _useLithotypeMode && s.compStrengthMpa > 0
                            ? 'ГОСТ: ${s.compStrengthMpa.toStringAsFixed(1)}'
                            : 'Изменить',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
