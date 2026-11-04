import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'archive_service.dart';

class ExportService {
  /// Сохранение CSV напрямую в локальную память телефона
  static Future<String?> exportSelectedRecordsToCsv(List<TestRecord> records) async {
    if (records.isEmpty) return null;

    final StringBuffer buffer = StringBuffer();
    // Разделитель ';' для корректного открытия в Excel (ГОСТ / РФ локаль)
    buffer.writeln('ID_Серии;Дата_Время;Шифр_Образца;Площадь_px2;Площадь_см2;Суммарная_Площадь_см2');

    for (final rec in records) {
      for (int i = 0; i < rec.samples.length; i++) {
        final sample = rec.samples[i];
        final String totalStr = (i == 0) ? rec.totalAreaCm2.toStringAsFixed(2) : '';
        buffer.writeln(
          '${rec.id};${rec.date};${sample.name};${sample.areaPx.toStringAsFixed(0)};${sample.areaCm2.toStringAsFixed(2)};$totalStr',
        );
      }
    }

    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (downloadDir.existsSync()) {
          targetDir = downloadDir;
        }
      }
      targetDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

      final String fileName = 'RockArea_Export_${DateTime.now().millisecondsSinceEpoch}.csv';
      final File file = File('${targetDir.path}/$fileName');
      await file.writeAsString(buffer.toString());

      return file.path;
    } catch (e) {
      return null;
    }
  }
}
