import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/export_service.dart';

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
    required this.part1,
    required this.part2,
    required this.part3,
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
    this.title = 'ГОСТ 24941-81 (Инденторы)',
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

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Экспорт протокола ГОСТ 24941-81', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            const Text('Таблица сформирована строго 1-в-1 по лабораторному бланку Excel', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.download, color: Color(0xFF2563EB)),
              ),
              title: const Text('Сохранить в память (Загрузки)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Прямая запись CSV-файла на устройство', style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.exportGostProtocol(
                  context: context,
                  seriesId: widget.title,
                  samples: _samples,
                  avgTensile: _avgTensile,
                  avgComp: _avgComp,
                  shareImmediately: false,
                );
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share_outlined, color: Color(0xFFF97316)),
              ),
              title: const Text('Отправить / Поделиться', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Переслать в мессенджер, почту или диск', style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.exportGostProtocol(
                  context: context,
                  seriesId: widget.title,
                  samples: _samples,
                  avgTensile: _avgTensile,
                  avgComp: _avgComp,
                  shareImmediately: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editSample(int index) {
    final s = _samples[index];
    final cipherCtrl = TextEditingController(text: '${s.part1} ${s.part2} ${s.part3}'.trim());
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
                const Text('Шифр пробы (3 значения через пробел):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                TextField(
                  controller: cipherCtrl,
                  decoration: const InputDecoration(
                    hintText: 'БАМ 1 1',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Площадь скола S: ${s.areaCm2.toStringAsFixed(2)} см²',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                const SizedBox(height: 12),
                const Text('Разрушающая нагрузка P (кН):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                TextField(
                  controller: loadCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Например: 14.5',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Состояние образца:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF97316), foregroundColor: Colors.white),
              onPressed: () {
                final raw = cipherCtrl.text.trim().split(RegExp(r'\s+'));
                setState(() {
                  s.part1 = raw.isNotEmpty ? raw[0] : '-';
                  s.part2 = raw.length > 1 ? raw[1] : '-';
                  s.part3 = raw.length > 2 ? raw[2] : '-';
                  s.loadKn = double.tryParse(loadCtrl.text.replaceAll(',', '.')) ?? 0.0;
                  s.condition = condition;
                });
                Navigator.pop(ctx);
              },
              child: const Text('Рассчитать'),
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
            tooltip: 'Экспорт / Сохранить протокол',
            onPressed: _showExportOptions,
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
            child: const Text('Принять'),
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
                      Text('${_avgComp.toStringAsFixed(2)} МПа', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
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
                      Text('${s.part1} | ${s.part2} | ${s.part3}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                        child: Text(s.condition, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'S = ${s.areaCm2.toStringAsFixed(2)} см² | P = ${s.loadKn > 0 ? '${s.loadKn} кН' : 'не задана'}',
                    style: TextStyle(fontSize: 11, color: s.loadKn > 0 ? const Color(0xFF64748B) : const Color(0xFFDC2626)),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Rc: ${s.compStrengthMpa.toStringAsFixed(1)} МПа', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                      Text('Нажмите для ввода P', style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
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
