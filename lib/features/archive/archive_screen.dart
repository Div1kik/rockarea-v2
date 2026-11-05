import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/archive_service.dart';
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
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await ArchiveService.loadRecords();
    setState(() {
      _records = data;
      _isLoading = false;
    });
  }

  void _openStrengthForRecord(TestRecord record) {
    final List<SampleStrengthData> items = [];

    for (int i = 0; i < record.samples.length; i++) {
      final s = record.samples[i];
      final raw = s.name.split(RegExp(r'\s+'));

      items.add(SampleStrengthData(
        part1: raw.isNotEmpty ? raw[0] : 'БАМ',
        part2: raw.length > 1 ? raw[1] : '1',
        part3: raw.length > 2 ? raw[2] : '${i + 1}',
        areaCm2: s.areaCm2,
        loadKn: s.loadKn,
        condition: s.condition,
      ));
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StrengthCalculatorSheet(
          title: 'Расчёт: ${record.id}',
          initialSamples: items,
          onSaved: (updated) async {
            for (int i = 0; i < updated.length; i++) {
              record.samples[i].name = '${updated[i].part1} ${updated[i].part2} ${updated[i].part3}';
              record.samples[i].loadKn = updated[i].loadKn;
              record.samples[i].condition = updated[i].condition;
              record.samples[i].tensileMpa = updated[i].tensileStrengthMpa;
              record.samples[i].compMpa = updated[i].compStrengthMpa;
            }
            await ArchiveService.updateRecord(record);
            _load();
          },
        ),
      ),
    );
  }

  Future<void> _delete(String id) async {
    await ArchiveService.deleteRecord(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Журнал испытаний', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _records.isEmpty
              ? const Center(child: Text('Журнал пуст. Проведите разметку образцов на фото.', style: TextStyle(color: Color(0xFF94A3B8))))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _records.length,
                  itemBuilder: (ctx, idx) {
                    final rec = _records[idx];
                    final hasLoads = rec.samples.any((s) => s.loadKn > 0);

                    return Card(
                      color: Colors.white,
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(rec.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      Text(rec.date, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 20),
                                  onPressed: () => _delete(rec.id),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (File(rec.imagePath).existsSync())
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(File(rec.imagePath), width: 60, height: 60, fit: BoxFit.cover),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Образцов в серии: ${rec.samples.length}', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                                      Text('Общая площадь: ${rec.totalAreaCm2.toStringAsFixed(2)} см²', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                      if (hasLoads)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(4)),
                                          child: const Text('Расчёт прочности выполнен', style: TextStyle(fontSize: 10, color: Color(0xFF059669), fontWeight: FontWeight.bold)),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20, color: Color(0xFFF1F5F9)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.calculate_outlined, size: 16),
                                  label: Text(hasLoads ? 'Открыть расчёт' : 'Внести нагрузки (P)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () => _openStrengthForRecord(rec),
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
