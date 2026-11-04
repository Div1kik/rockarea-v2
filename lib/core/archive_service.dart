import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'imagePath': imagePath,
        'totalAreaCm2': totalAreaCm2,
        'samples': samples.map((s) => s.toMap()).toList(),
      };

  factory TestRecord.fromMap(Map<String, dynamic> map) => TestRecord(
        id: map['id'] ?? '',
        date: map['date'] ?? '',
        imagePath: map['imagePath'] ?? '',
        totalAreaCm2: (map['totalAreaCm2'] as num?)?.toDouble() ?? 0.0,
        samples: (map['samples'] as List<dynamic>? ?? [])
            .map((s) => SampleItem.fromMap(s as Map<String, dynamic>))
            .toList(),
      );
}

class SampleItem {
  final String name;
  final double areaPx;
  final double areaCm2;

  SampleItem({
    required this.name,
    required this.areaPx,
    required this.areaCm2,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'areaPx': areaPx,
        'areaCm2': areaCm2,
      };

  factory SampleItem.fromMap(Map<String, dynamic> map) => SampleItem(
        name: map['name'] ?? '',
        areaPx: (map['areaPx'] as num?)?.toDouble() ?? 0.0,
        areaCm2: (map['areaCm2'] as num?)?.toDouble() ?? 0.0,
      );
}

class ArchiveService {
  static const String _storageKey = 'rockarea_records';

  static Future<List<TestRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_storageKey) ?? [];
    return jsonList
        .map((str) => TestRecord.fromMap(jsonDecode(str) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveRecord(TestRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await loadRecords();
    records.insert(0, record);
    final jsonList = records.map((r) => jsonEncode(r.toMap())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  static Future<void> deleteRecord(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await loadRecords();
    records.removeWhere((r) => r.id == id);
    final jsonList = records.map((r) => jsonEncode(r.toMap())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }
}
