import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'archive_service.dart';
import '../features/strength/strength_calculator_sheet.dart';

class ExportService {
  static Future<File> _writeCsvFile({
    required String filename,
    required String content,
  }) async {
    // Мгновенная запись во временный кэш без системных зависаний Android Scoped Storage
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');

    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 1. Ведомость площадей
  static Future<void> exportGeometryOnly({
    required BuildContext context,
    required TestRecord record,
    bool shareImmediately = true,
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

    await Share.shareXFiles(
      [XFile(savedFile.path)],
      subject: 'Площади_${safeId}',
      text: 'Ведомость площадей образцов',
    );
  }

  /// 2. Результаты испытаний по ГОСТ 24941-81 с работающими формулами Excel
  static Future<void> exportGostProtocol({
    required BuildContext context,
    required String seriesId,
    required List<SampleStrengthData> samples,
    required double avgTensile,
    required double avgComp,
    bool shareImmediately = true,
  }) async {
    final sb = StringBuffer();

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
      final colJ = s.areaCm2 > 0 ? s.areaCm2.toStringAsFixed(2).replaceAll('.', ',') : '0,00';
      final colK = s.loadKn > 0 ? s.loadKn.toStringAsFixed(2).replaceAll('.', ',') : '0,00';

      final colL = '=ROUND(0.5076*POWER(J$r;0.2506);2)';
      final colM = '=IF(J$r>0;ROUND((7.5*K$r*L$r)/J$r;2);0)';
      final colN = (i == 0) ? '=ROUND(AVERAGE(M$startRow:M$endRow);2)' : '';
      final colO = '=IF(M$r<=0;"";IF(M$r<1;12;IF(M$r<5;16;20)))';
      final colP = '';
      final colQ = '=IF(O$r<>"";ROUND(M$r*O$r;1);"")';
      final colR = (i == 0) ? '=IF(COUNT(Q$startRow:Q$endRow)>0;ROUND(AVERAGE(Q$startRow:Q$endRow);1);"")' : '';

      sb.writeln('$colA;$colB;$colC;$colD;$colE;$colF;$colG;$colH;$colI;$colJ;$colK;$colL;$colM;$colN;$colO;$colP;$colQ;$colR');
    }

    final safeId = seriesId.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'Результаты_испытаний_${safeId}.csv';
    final savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    await Share.shareXFiles(
      [XFile(savedFile.path)],
      subject: 'Результаты_испытаний_${safeId}',
      text: 'Протокол результатов испытаний ГОСТ 24941-81',
    );
  }
}
