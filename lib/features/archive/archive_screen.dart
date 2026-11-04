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

    final savedPath = await ExportService.exportSelectedRecordsToCsv(selectedRecords);
    if (!mounted) return;

    if (savedPath != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Файл сохранен', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ],
          ),
          content: Text(
            'Таблица успешно сохранена на устройство:\n\n$savedPath',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
    }
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
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          _selectedIds.isEmpty ? 'Журнал испытаний' : 'Выбрано: ${_selectedIds.length}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: Icon(
                _selectedIds.length == _records.length ? Icons.deselect : Icons.select_all,
                color: const Color(0xFF2563EB),
              ),
              tooltip: 'Выбрать все',
              onPressed: _selectAll,
            ),
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined, color: Color(0xFFF97316)),
              tooltip: 'Экспорт в CSV',
              onPressed: _exportSelected,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF97316)))
          : _records.isEmpty
              ? const Center(
                  child: Text('Архив пуст.\nВыполните серию измерений и нажмите «В журнал».',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _records.length,
                  itemBuilder: (context, i) {
                    final rec = _records[i];
                    final isChecked = _selectedIds.contains(rec.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isChecked ? const Color(0xFFF97316) : const Color(0xFFE2E8F0),
                          width: isChecked ? 2 : 1,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: ExpansionTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isChecked,
                              activeColor: const Color(0xFFF97316),
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
                                        color: const Color(0xFFE2E8F0),
                                        child: const Icon(Icons.broken_image, size: 20, color: Color(0xFF94A3B8)),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(rec.id, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 14)),
                        subtitle: Text('${rec.date} • Образцов: ${rec.samples.length}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        trailing: Text('${rec.totalAreaCm2.toStringAsFixed(2)} см²',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                        children: [
                          const Divider(color: Color(0xFFF1F5F9), height: 1),
                          ...rec.samples.map(
                            (s) => ListTile(
                              dense: true,
                              title: Text(s.name, style: const TextStyle(color: Color(0xFF334155), fontSize: 13, fontWeight: FontWeight.w500)),
                              subtitle: Text('${s.areaPx.toStringAsFixed(0)} px²',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                              trailing: Text('${s.areaCm2.toStringAsFixed(2)} см²',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, color: Color(0xFFF97316), fontSize: 13)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showImagePreview(rec.imagePath, rec.id),
                                  icon: const Icon(Icons.fullscreen, size: 16, color: Color(0xFF2563EB)),
                                  label: const Text('Открыть фото', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12)),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    await ArchiveService.deleteRecord(rec.id);
                                    _load();
                                  },
                                  icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFDC2626)),
                                  label: const Text('Удалить', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
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
              color: Colors.white,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.file_download_outlined),
                label: Text('Экспортировать выбранные (${_selectedIds.length}) в CSV',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                onPressed: _exportSelected,
              ),
            )
          : null,
    );
  }
}
