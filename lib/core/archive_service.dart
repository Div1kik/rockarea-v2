import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/archive_service.dart';
import '../../core/export_service.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<TestRecord> _records = [];
  final Set<String> _selectedIds = {};
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
        _selectedIds.clear();
        _loading = false;
      });
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _records.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_records.map((r) => r.id));
      }
    });
  }

  Future<void> _exportSelected() async {
    final selectedRecords = _records.where((r) => _selectedIds.contains(r.id)).toList();
    if (selectedRecords.isEmpty) return;
    await ExportService.exportSelectedRecordsToCsv(selectedRecords);
  }

  void _showImagePreview(String imagePath, String title) {
    if (!File(imagePath).existsSync()) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(imagePath), fit: BoxFit.contain),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: Text(
          _selectedIds.isEmpty ? 'Журнал испытаний' : 'Выбрано: ${_selectedIds.length}',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF131C2E),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: Icon(
                _selectedIds.length == _records.length ? Icons.deselect : Icons.select_all,
                color: const Color(0xFF10B981),
              ),
              tooltip: 'Выбрать все',
              onPressed: _selectAll,
            ),
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.ios_share, color: Color(0xFF10B981)),
              tooltip: 'Экспорт CSV',
              onPressed: _exportSelected,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _records.isEmpty
              ? const Center(
                  child: Text('Архив пуст.\nВыполните серию измерений и нажмите «В архив».',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _records.length,
                  itemBuilder: (context, i) {
                    final rec = _records[i];
                    final isChecked = _selectedIds.contains(rec.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isChecked ? const Color(0xFF1E293B) : const Color(0xFF131C2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isChecked ? const Color(0xFF10B981) : const Color(0xFF243048),
                        ),
                      ),
                      child: ExpansionTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isChecked,
                              activeColor: const Color(0xFF10B981),
                              onChanged: (_) => _toggleSelection(rec.id),
                            ),
                            GestureDetector(
                              onTap: () => _showImagePreview(rec.imagePath, rec.id),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: File(rec.imagePath).existsSync()
                                    ? Image.file(File(rec.imagePath), width: 44, height: 44, fit: BoxFit.cover)
                                    : Container(
                                        width: 44,
                                        height: 44,
                                        color: const Color(0xFF243048),
                                        child: const Icon(Icons.broken_image, size: 20, color: Color(0xFF64748B)),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(rec.id, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                        subtitle: Text('${rec.date} • Образцов: ${rec.samples.length}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        trailing: Text('${rec.totalAreaCm2.toStringAsFixed(2)} см²',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showImagePreview(rec.imagePath, rec.id),
                                  icon: const Icon(Icons.fullscreen, size: 16, color: Color(0xFF10B981)),
                                  label: const Text('Открыть фото', style: TextStyle(color: Color(0xFF10B981), fontSize: 12)),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    await ArchiveService.deleteRecord(rec.id);
                                    _load();
                                  },
                                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                  label: const Text('Удалить', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF131C2E),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.download_outlined),
                label: Text('Экспортировать выбранные (${_selectedIds.length}) в CSV',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _exportSelected,
              ),
            )
          : null,
    );
  }
}
