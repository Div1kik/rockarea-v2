import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/archive_service.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<TestRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ArchiveService.loadRecords();
    if (mounted) {
      setState(() {
        _records = data;
        _loading = false;
      });
    }
  }

  Future<void> _delete(String id) async {
    await ArchiveService.deleteRecord(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: const Text('Журнал испытаний керна', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF131C2E),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _records.isEmpty
              ? const Center(
                  child: Text('Архив пуст.\nВыполните серию измерений и нажмите «Сохранить».',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _records.length,
                  itemBuilder: (context, i) {
                    final rec = _records[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131C2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: ExpansionTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: File(rec.imagePath).existsSync()
                              ? Image.file(File(rec.imagePath), width: 48, height: 48, fit: BoxFit.cover)
                              : Container(
                                  width: 48,
                                  height: 48,
                                  color: const Color(0xFF1E293B),
                                  child: const Icon(Icons.image_not_supported, color: Color(0xFF64748B)),
                                ),
                        ),
                        title: Text(rec.id, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text('${rec.date} • Объектов: ${rec.samples.length}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        trailing: Text('${rec.totalAreaCm2.toStringAsFixed(2)} см²',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        children: [
                          const Divider(color: Color(0xFF243048), height: 1),
                          ...rec.samples.map(
                            (s) => ListTile(
                              dense: true,
                              title: Text(s.name, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                              subtitle: Text('${s.areaPx.toStringAsFixed(0)} px²',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                              trailing: Text('${s.areaCm2.toStringAsFixed(2)} см²',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 13)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _delete(rec.id),
                                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                  label: const Text('Удалить из архива', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
