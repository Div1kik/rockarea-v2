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
    final list = await ArchiveService.getRecords();
    setState(() {
      _records = list;
      _isLoading = false;
    });
  }

  void _openStrengthForRecord(TestRecord record) {
    final List<SampleStrengthData> items = [];
    for (int i = 0; i < record.samples.length; i++) {
      final s = record.samples[i];
      final raw = s.name.split(RegExp(r'\s+'));

      items.add(SampleStrengthData(
        part1: raw.isNotEmpty ? raw[0] : '',
        part2: raw.length > 1 ? raw[1] : '',
        part3: raw.length > 2 ? raw[2] : '',
        areaCm2: s.areaCm2,
        loadKn: s.loadKn,
        condition: s.condition,
      ));
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StrengthCalculatorSheet(
          title: record.id,
          initialSamples: items,
          onSaved: (updated) async {
            final List<SampleItem> updatedSamples = [];
            for (int i = 0; i < record.samples.length; i++) {
              final orig = record.samples[i];
              if (i < updated.length) {
                final up = updated[i];
                final name = [up.part1, up.part2, up.part3].where((e) => e.isNotEmpty).join(' ');
                updatedSamples.add(SampleItem(
                  name: name.isNotEmpty ? name : orig.name,
                  areaPx: orig.areaPx,
                  areaCm2: orig.areaCm2,
                  loadKn: up.loadKn,
                  condition: up.condition,
                  tensileMpa: up.tensileStrengthMpa,
                  compMpa: up.compStrengthMpa,
                ));
              } else {
                updatedSamples.add(orig);
              }
            }
            record.samples = updatedSamples;
            await ArchiveService.saveRecord(record);
            _loadRecords();
          },
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _records.isEmpty
              ? const Center(
                  child: Text('В журнале пока нет сохраненных серий', style: TextStyle(color: Color(0xFF94A3B8))),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  itemCount: _records.length,
                  itemBuilder: (ctx, idx) {
                    final r = _records[idx];
                    return Card(
                      color: Colors.white,
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openStrengthForRecord(r),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFFEFF6FF),
                                    child: Text('${idx + 1}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                                        Text(r.date, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.calculate_outlined, color: Color(0xFF2563EB)),
                                    tooltip: 'Ввести нагрузки / Расчёт',
                                    onPressed: () => _openStrengthForRecord(r),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.file_download_outlined, color: Color(0xFF059669)),
                                    tooltip: 'Экспорт таблицы',
                                    onPressed: () => ExportService.exportGeometryOnly(context: context, record: r),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                                    tooltip: 'Удалить серию',
                                    onPressed: () async {
                                      await ArchiveService.deleteRecord(r.id);
                                      _loadRecords();
                                    },
                                  ),
                                ],
                              ),
                              const Divider(height: 20, color: Color(0xFFF1F5F9)),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Образцов: ${r.samples.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                                  Text('S общ: ${r.totalAreaCm2.toStringAsFixed(2)} см²',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
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
}
