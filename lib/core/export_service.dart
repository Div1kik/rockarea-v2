import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'archive_service.dart';
import '../features/strength/strength_calculator_sheet.dart';

class ExportService {
  static Future<File> _writeCsvFile({
    required String filename,
    required String content,
  }) async {
    Directory? targetDir;

    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        targetDir = downloadDir;
      }
    }

    targetDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

    final file = File('${targetDir.path}/$filename');
    // UTF-8 BOM для корректного отображения кириллицы в Excel
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 1. Ведомость площадей (минималистичная)
  static Future<void> exportGeometryOnly({
    required BuildContext context,
    required TestRecord record,
    bool shareImmediately = false,
  }) async {
    final sb = StringBuffer();
    sb.writeln('ВЕДОМОСТЬ ПЛОЩАДЕЙ ОБРАЗЦОВ');
    sb.writeln('Серия;${record.id};Дата;${record.date}');
    sb.writeln('');
    sb.writeln('№;Наименование;Площадь, см2');

    for (int i = 0; i < record.samples.length; i++) {
      final s = record.samples[i];
      sb.writeln('${i + 1};${s.name};${s.areaCm2.toStringAsFixed(2).replaceAll('.', ',')}');
    }

    final safeId = record.id.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'Площади_${safeId}.csv';
    final savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2563EB),
          content: Text('Файл сохранен в Загрузки:\n${savedFile.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// 2. Результаты испытаний по ГОСТ 24941-81 с работающими формулами Excel
  static Future<void> exportGostProtocol({
    required BuildContext context,
    required String seriesId,
    required List<SampleStrengthData> samples,
    required double avgTensile,
    required double avgComp,
    bool shareImmediately = false,
  }) async {
    final sb = StringBuffer();

    // 1-я строка шапки (3 столбца шифра: B, C, D)
    sb.writeln(
      '№;'
      'Шифр пробы;;;'
      '№ Скважины;'
      'Интервал, м;'
      'Состояние;'
      'Литологический тип;;'
      'Площадь скола, см2;'
      'Разрушающая нагрузка, кН;'
      'K;'
      'Предел прочности на растяжение, МПа;'
      'Среднее значение предела прочности на растяжение, МПа;'
      'Коэф. Пересчета;'
      'Шифр Коэф. Пересчета;'
      'Предел прочности на сжатие (расчетным методом по ГОСТ 24941-81), МПа;'
      'Среднее значение предела прочности на сжатие (расчетным методом по ГОСТ 24941-81), МПа'
    );

    // 2-я строка шапки (Номера граф)
    sb.writeln('1;2;;;3;4;5;6;;7;8;9;10;11;;;12;13');

    final int startRow = 3;
    final int endRow = startRow + samples.length - 1;

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final r = startRow + i;

      final colA = '${i + 1}';
      final colB = s.part1;
      final colC = s.part2;
      final colD = s.part3;
      final colE = s.borehole;
      final colF = s.interval;
      final colG = s.condition;
      final colH = s.lithology;
      final colI = '';
      
      // Значения площади и нагрузки в числовом формате
      final colJ = s.areaCm2 > 0 ? s.areaCm2.toStringAsFixed(2).replaceAll('.', ',') : '0,00';
      final colK = s.loadKn > 0 ? s.loadKn.toStringAsFixed(2).replaceAll('.', ',') : '0,00';

      // Рабочие интернациональные формулы для CSV Excel:
      // K (Колонка L): K = 0.5076 * (S ^ 0.2506)
      final colL = '=ROUND(0.5076*POWER(J$r;0.2506);2)';

      // Предел прочности на растяжение (Колонка M): Sigma = (7.5 * P * K) / S
      final colM = '=IF(J$r>0;ROUND((7.5*K$r*L$r)/J$r;2);0)';

      // Среднее значение растяжения (Колонка N): строго по строкам текущей серии в 1-й строке
      final colN = (i == 0) ? '=ROUND(AVERAGE(M$startRow:M$endRow);2)' : '';

      // Коэф. пересчета (Колонка O): в зависимости от Sigma (<1 -> 12, <5 -> 16, иначе 20)
      final colO = '=IF(M$r<=0;"";IF(M$r<1;12;IF(M$r<5;16;20)))';
      final colP = '';

      // Предел прочности на сжатие Rc (Колонка Q): Rc = Sigma * Коэф
      final colQ = '=IF(O$r<>"";ROUND(M$r*O$r;1);"")';

      // Среднее значение сжатия (Колонка R)
      final colR = (i == 0) ? '=IF(COUNT(Q$startRow:Q$endRow)>0;ROUND(AVERAGE(Q$startRow:Q$endRow);1);"")' : '';

      sb.writeln('$colA;$colB;$colC;$colD;$colE;$colF;$colG;$colH;$colI;$colJ;$colK;$colL;$colM;$colN;$colO;$colP;$colQ;$colR');
    }

    final safeId = seriesId.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'Результаты_испытаний_${safeId}.csv';
    final savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Результаты испытаний сохранены:\n${savedFile.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
