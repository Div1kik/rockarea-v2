import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SampleItem {
  final String name;
  final double areaPx;
  final double areaCm2;
  final double loadKn;
  final String condition;
  final double tensileMpa;
  final double compMpa;

  SampleItem({
    required this.name,
    required this.areaPx,
    required this.areaCm2,
    this.loadKn = 0.0,
    this.condition = 'n',
    this.tensileMpa = 0.0,
    this.compMpa = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'areaPx': areaPx,
        'areaCm2': areaCm2,
        'loadKn': loadKn,
        'condition': condition,
        'tensileMpa': tensileMpa,
        'compMpa': compMpa,
      };

  factory SampleItem.fromJson(Map<String, dynamic> json) => SampleItem(
        name: json['name'] as String? ?? 'Образец',
        areaPx: (json['areaPx'] as num?)?.toDouble() ?? 0.0,
        areaCm2: (json['areaCm2'] as num?)?.toDouble() ?? 0.0,
        loadKn: (json['loadKn'] as num?)?.toDouble() ?? 0.0,
        condition: json['condition'] as String? ?? 'n',
        tensileMpa: (json['tensileMpa'] as num?)?.toDouble() ?? 0.0,
        compMpa: (json['compMpa'] as num?)?.toDouble() ?? 0.0,
      );
}

class TestRecord {
  final String id;
  final String date;
  final String imagePath;
  final double totalAreaCm2;
  final List<SampleItem> samples;

  TestRecord({
    required this.id,
    required this.date,
    required this.imagePath,
    required this.totalAreaCm2,
    required this.samples,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'imagePath': imagePath,
        'totalAreaCm2': totalAreaCm2,
        'samples': samples.map((s) => s.toJson()).toList(),
      };

  factory TestRecord.fromJson(Map<String, dynamic> json) => TestRecord(
        id: json['id'] as String? ?? 'Серия',
        date: json['date'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
        totalAreaCm2: (json['totalAreaCm2'] as num?)?.toDouble() ?? 0.0,
        samples: (json['samples'] as List<dynamic>? ?? [])
            .map((e) => SampleItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ArchiveService {
  static const String _fileName = 'archive_records.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Возвращает все сохранённые серии (для совместимости поддерживаются оба имени)
  static Future<List<TestRecord>> getRecords() async {
    return loadRecords();
  }

  static Future<List<TestRecord>> loadRecords() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map((e) => TestRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Сохранение новой серии в журнал
  static Future<void> saveRecord(TestRecord record) async {
    final list = await loadRecords();
    list.insert(0, record);
    final file = await _getFile();
    await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()), flush: true);
  }

  /// Удаление серии по идентификатору
  static Future<void> deleteRecord(String recordId) async {
    final list = await loadRecords();
    list.removeWhere((r) => r.id == recordId);
    final file = await _getFile();
    await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()), flush: true);
  }
}
