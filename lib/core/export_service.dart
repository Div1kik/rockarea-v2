import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'archive_service.dart';
import '../features/strength/strength_calculator_sheet.dart';

class ExportService {
  /// Прямая запись CSV в системную папку Загрузки телефона
  static Future<File> _writeCsvFile({
    required String filename,
    required String content,
  }) async {
    Directory? targetDir;

    if (Platform.isAndroid) {
      final publicDownload = Directory('/storage/emulated/0/Download');
      try {
        if (await publicDownload.exists()) {
          targetDir = publicDownload;
        }
      } catch (_) {}
    }

    targetDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

    final file = File('${targetDir.path}/$filename');
    // UTF-8 BOM для безупречного распознавания кириллицы
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 1. Ведомость «Площади»
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

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Ведомость площадей');
    }
  }

  /// 2. Результаты испытаний ГОСТ 24941-81 с работающими русскими формулами Excel
  static Future<void> exportGostProtocol({
    required BuildContext context,
    required String seriesId,
    required List<SampleStrengthData> samples,
    required double avgTensile,
    required double avgComp,
    bool shareImmediately = false,
  }) async {
    final sb = StringBuffer();

    // Шапка таблицы (строго 18 столбцов: A - R)
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

    // Номера граф по ГОСТ
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

      // Числовые значения через запятую (для распознавания русским Excel)
      final colJ = s.areaCm2 > 0 ? s.areaCm2.toStringAsFixed(2).replaceAll('.', ',') : '0,00';
      final colK = s.loadKn > 0 ? s.loadKn.toStringAsFixed(2).replaceAll('.', ',') : '0,00';

      // 100% валидные формулы для русского Excel в CSV:
      // Все формулы заключены в кавычки "", числа записаны через запятую (0,5076 и 0,2506),
      // а функции названы на русском (ОКРУГЛ, ЕСЛИ, СРЗНАЧ).
      final colL = '"=ОКРУГЛ(0,5076*(J$r^0,2506);2)"';
      final colM = '"=ЕСЛИ(J$r>0;ОКРУГЛ((7,5*K$r*L$r)/J$r;2);0)"';
      final colN = (i == 0) ? '"=ОКРУГЛ(СРЗНАЧ(M$startRow:M$endRow);2)"' : '';
      final colO = '"=ЕСЛИ(M$r<=0;"""";ЕСЛИ(M$r<1;12;ЕСЛИ(M$r<5;16;20)))"';
      final colP = '';
      final colQ = '"=ЕСЛИ(O$r<>"""";ОКРУГЛ(M$r*O$r;1);"""")"';
      final colR = (i == 0) ? '"=ЕСЛИ(СЧЁТ(Q$startRow:Q$endRow)>0;ОКРУГЛ(СРЗНАЧ(Q$startRow:Q$endRow);1);"""")"' : '';

      sb.writeln('$colA;$colB;$colC;$colD;$colE;$colF;$colG;$colH;$colI;$colJ;$colK;$colL;$colM;$colN;$colO;$colP;$colQ;$colR');
    }

    final safeId = seriesId.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'Результаты_испытаний_${safeId}.csv';
    final savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Файл сохранен в Загрузки:\n${savedFile.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Результаты испытаний $seriesId');
    }
  }
}
