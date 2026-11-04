import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'archive_service.dart';

class ExportService {
  /// Экспорт выбранных серий в CSV с системным сохранением
  static Future<bool> exportSelectedRecordsToCsv(List<TestRecord> records) async {
    if (records.isEmpty) return false;

    final StringBuffer buffer = StringBuffer();
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

    final directory = await getApplicationDocumentsDirectory();
    final String fileName = 'RockArea_${DateTime.now().millisecondsSinceEpoch}.csv';
    final File file = File('${directory.path}/$fileName');
    await file.writeAsString(buffer.toString());

    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      text: 'Экспорт журнала испытаний RockArea Core v2',
      subject: 'Лабораторные испытания керна',
    );

    return result.status == ShareResultStatus.success || result.status == ShareResultStatus.dismissed;
  }
}
