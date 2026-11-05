import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SampleItem {
  String name;
  double areaPx;
  double areaCm2;
  double loadKn;
  String condition;
  double tensileMpa;
  double compMpa;

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

  factory SampleItem.fromJson(Map<String, dynamic> j) => SampleItem(
        name: j['name'] ?? '',
        areaPx: (j['areaPx'] as num?)?.toDouble() ?? 0.0,
        areaCm2: (j['areaCm2'] as num?)?.toDouble() ?? 0.0,
        loadKn: (j['loadKn'] as num?)?.toDouble() ?? 0.0,
        condition: j['condition'] ?? 'n',
        tensileMpa: (j['tensileMpa'] as num?)?.toDouble() ?? 0.0,
        compMpa: (j['compMpa'] as num?)?.toDouble() ?? 0.0,
      );
}

class TestRecord {
  final String id;
  final String date;
  final String imagePath;
  final double totalAreaCm2;
  List<SampleItem> samples;

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

  factory TestRecord.fromJson(Map<String, dynamic> j) => TestRecord(
        id: j['id'] ?? '',
        date: j['date'] ?? '',
        imagePath: j['imagePath'] ?? '',
        totalAreaCm2: (j['totalAreaCm2'] as num?)?.toDouble() ?? 0.0,
        samples: (j['samples'] as List? ?? [])
            .map((e) => SampleItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ArchiveService {
  static const String _kKey = 'rockarea_records_v2';

  static Future<List<TestRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? [];
    return raw.map((s) => TestRecord.fromJson(jsonDecode(s))).toList();
  }

  static Future<void> saveRecord(TestRecord record) async {
    final records = await loadRecords();
    records.insert(0, record);
    await _writeRecords(records);
  }

  static Future<void> updateRecord(TestRecord record) async {
    final records = await loadRecords();
    final idx = records.indexWhere((r) => r.id == record.id);
    if (idx != -1) {
      records[idx] = record;
      await _writeRecords(records);
    }
  }

  static Future<void> deleteRecord(String id) async {
    final records = await loadRecords();
    records.removeWhere((r) => r.id == id);
    await _writeRecords(records);
  }

  static Future<void> _writeRecords(List<TestRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final data = records.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_kKey, data);
  }
}
