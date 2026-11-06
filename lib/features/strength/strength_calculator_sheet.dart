import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/export_service.dart';

class SampleStrengthData {
  String part1;
  String part2;
  String part3;
  String part4;
  String borehole;
  String interval;
  String condition;
  String lithology;
  double areaCm2;
  double loadKn;

  SampleStrengthData({
    required this.part1,
    required this.part2,
    required this.part3,
    this.part4 = '1',
    this.borehole = '-',
    this.interval = '-',
    this.condition = 'n',
    this.lithology = '-',
    required this.areaCm2,
    this.loadKn = 0.0,
  });

  double get coeffK => areaCm2 > 0 ? 0.5076 * math.pow(areaCm2, 0.2506) : 0.0;
  double get tensileStrengthMpa => areaCm2 > 0 ? (7.5 * loadKn * coeffK) / areaCm2 : 0.0;
  double get conversionCoeff {
    final m = tensileStrengthMpa;
    if (m <= 0) return 0.0;
    if (m < 1.0) return 12.0;
    if (m < 5.0) return 16.0;
    return 20.0;
  }
  double get compStrengthMpa => tensileStrengthMpa * conversionCoeff;
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

  @override
  void initState() {
    super.initState();
    _samples = widget.initialSamples;
  }

  double get _avgTensile {
    final valid = _samples.where((s) => s.tensileStrengthMpa > 0).toList();
    if (valid.isEmpty) return 0.0;
    return valid.map((s) => s.tensileStrengthMpa).reduce((a, b) => a + b) / valid.length;
  }

  double get _avgComp {
    final valid = _samples.where((s) => s.compStrengthMpa > 0).toList();
    if (valid.isEmpty) return 0.0;
    return valid.map((s) => s.compStrengthMpa).reduce((a, b) => a + b) / valid.length;
  }

  void _editSample(int index) {
    final s = _samples[index];
    final p1Ctrl = TextEditingController(text: s.part1);
    final p2Ctrl = TextEditingController(text: s.part2);
    final p3Ctrl = TextEditingController(text: s.part3);
    final p4Ctrl = TextEditingController(text: s.part4);
    final loadCtrl = TextEditingController(text: s.loadKn > 0 ? s.loadKn.toString() : '');
    String condition = s.condition;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text('Образец #${index + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Шифр пробы (4 графы):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: TextField(controller: p1Ctrl, decoration: const InputDecoration(labelText: 'АБВ', isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 4),
                    Expanded(child: TextField(controller: p2Ctrl, decoration: const InputDecoration(labelText: '1', isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 4),
                    Expanded(child: TextField(controller: p3Ctrl, decoration: const InputDecoration(labelText: '1', isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 4),
                    Expanded(child: TextField(controller: p4Ctrl, decoration: const InputDecoration(labelText: '1', isDense: true, border: OutlineInputBorder()))),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Площадь скола S: ${s.areaCm2.toStringAsFixed(2)} см²',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                const SizedBox(height: 12),
                const Text('Разрушающая нагрузка P (кН):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                TextField(
                  controller: loadCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                setState(() {
                  s.part1 = p1Ctrl.text.trim();
                  s.part2 = p2Ctrl.text.trim();
                  s.part3 = p3Ctrl.text.trim();
                  s.part4 = p4Ctrl.text.trim();
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
            tooltip: 'Экспорт таблицы с формулами',
            onPressed: () => ExportService.exportGostProtocol(
              context: context,
              seriesId: widget.title,
              samples: _samples,
              avgTensile: _avgTensile,
              avgComp: _avgComp,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('СР. РАСТЯЖЕНИЕ', style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
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
                      const Text('СР. СЖАТИЕ Rc', style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                      Text('${_avgComp.toStringAsFixed(1)} МПа', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: ListView.separated(
              itemCount: _samples.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
              itemBuilder: (ctx, idx) {
                final s = _samples[idx];
                return ListTile(
                  tileColor: Colors.white,
                  dense: true,
                  onTap: () => _editSample(idx),
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Text('${idx + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                  ),
                  title: Row(
                    children: [
                      Text('${s.part1} | ${s.part2} | ${s.part3} | ${s.part4}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                        child: Text(s.condition, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'S = ${s.areaCm2.toStringAsFixed(2)} см² | P = ${s.loadKn > 0 ? '${s.loadKn} кН' : '0.00'}',
                    style: TextStyle(fontSize: 11, color: s.loadKn > 0 ? const Color(0xFF64748B) : const Color(0xFFDC2626)),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Rc: ${s.compStrengthMpa.toStringAsFixed(1)} МПа', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                      const Text('Ввести P', style: TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
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
