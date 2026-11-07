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

  factory TestRecord.fromJson(Map<String, dynamic> json) => TestRecord(
    id: json['id'] as String? ?? '',
    date: json['date'] as String? ?? '',
    imagePath: json['imagePath'] as String? ?? '',
    totalAreaCm2: (json['totalAreaCm2'] as num?)?.toDouble() ?? 0.0,
    samples: (json['samples'] as List<dynamic>?)
            ?.map((e) => SampleItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class ArchiveService {
  static const String _key = 'rockarea_test_records';

  static Future<List<TestRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_key);
    if (data == null || data.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(data) as List<dynamic>;
      return list.map((e) => TestRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecord(TestRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await getRecords();
    final existingIdx = records.indexWhere((r) => r.id == record.id);
    if (existingIdx != -1) {
      records[existingIdx] = record;
    } else {
      records.insert(0, record);
    }
    await prefs.setString(_key, jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  static Future<void> deleteRecord(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await getRecords();
    records.removeWhere((r) => r.id == id);
    await prefs.setString(_key, jsonEncode(records.map((r) => r.toJson()).toList()));
  }
}
