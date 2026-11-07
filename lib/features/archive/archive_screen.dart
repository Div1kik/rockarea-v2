import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/archive_service.dart';
import '../../core/export_service.dart';
import '../strength/strength_calculator_sheet.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<TestRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final records = await ArchiveService.getRecords();
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _confirmDeleteRecord(TestRecord record) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
              SizedBox(width: 8),
              Text(
                'Удалить запись?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: Text(
            'Вы действительно хотите удалить "${record.id}" от ${record.date}?\nДанные серии и все образцы будут стёрты.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Удалить', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await ArchiveService.deleteRecord(record.id);
      await _loadRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            content: Text('Серия "${record.id}" удалена из журнала'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _exportRecord(TestRecord record) {
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
            Text('Экспорт: ${record.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined, color: Color(0xFF2563EB)),
              title: const Text('Результаты испытаний (ГОСТ 24941-81)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Полная таблица с формулами Excel', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                final samples = record.samples.map((s) {
                  final raw = s.name.split(RegExp(r'\s+'));
                  return SampleStrengthData(
                    part1: raw.isNotEmpty ? raw[0] : '',
                    part2: raw.length > 1 ? raw[1] : '',
                    part3: raw.length > 2 ? raw[2] : '',
                    areaCm2: s.areaCm2,
                    loadKn: s.loadKn,
                    condition: s.condition,
                  );
                }).toList();

                final avgTensile = samples.where((s) => s.tensileStrengthMpa > 0).isEmpty
                    ? 0.0
                    : samples.where((s) => s.tensileStrengthMpa > 0).map((s) => s.tensileStrengthMpa).reduce((a, b) => a + b) /
                        samples.where((s) => s.tensileStrengthMpa > 0).length;

                final avgComp = samples.where((s) => s.compStrengthMpa > 0).isEmpty
                    ? 0.0
                    : samples.where((s) => s.compStrengthMpa > 0).map((s) => s.compStrengthMpa).reduce((a, b) => a + b) /
                        samples.where((s) => s.compStrengthMpa > 0).length;

                ExportService.exportGostProtocol(
                  context: context,
                  seriesId: record.id,
                  samples: samples,
                  avgTensile: avgTensile,
                  avgComp: avgComp,
                  shareImmediately: false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.straighten, color: Color(0xFF059669)),
              title: const Text('Ведомость площадей образцов', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Краткая ведомость (№, Шифр, S)', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.exportGeometryOnly(context: context, record: record, shareImmediately: false);
              },
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
        title: const Text('Журнал испытаний'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _records.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 56, color: Color(0xFF94A3B8)),
                      SizedBox(height: 12),
                      Text('Журнал пока пуст', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                      SizedBox(height: 4),
                      Text('Сохранённые серии испытаний появятся здесь', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _records.length,
                  itemBuilder: (ctx, idx) {
                    final record = _records[idx];
                    return Card(
                      color: Colors.white,
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFEFF6FF),
                                  child: Text('${_records.length - idx}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(record.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                                      const SizedBox(height: 2),
                                      Text(record.date, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.file_download_outlined, color: Color(0xFF2563EB)),
                                  tooltip: 'Экспорт',
                                  onPressed: () => _exportRecord(record),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                                  tooltip: 'Удалить',
                                  onPressed: () => _confirmDeleteRecord(record),
                                ),
                              ],
                            ),
                            const Divider(height: 20, color: Color(0xFFF1F5F9)),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Образцов: ${record.samples.length}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                  ),
                                ),
                                Text(
                                  'S общ: ${record.totalAreaCm2.toStringAsFixed(2)} см²',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF2563EB)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
