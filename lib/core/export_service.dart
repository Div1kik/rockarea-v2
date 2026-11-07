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
    final Directory baseDir = await getApplicationDocumentsDirectory();
    final File file = File('${baseDir.path}/$filename');
    final List<int> bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
    await file.writeAsBytes(bytes, flush: false);
    return file;
  }

  static Future<void> exportGeometryOnly({
    required BuildContext context,
    required TestRecord record,
    bool shareImmediately = false,
  }) async {
    final StringBuffer sb = StringBuffer();
    sb.writeln('ВЕДОМОСТЬ ПЛОЩАДЕЙ ОБРАЗЦОВ');
    sb.writeln('Серия;${record.id};Дата;${record.date}');
    sb.writeln('');
    sb.writeln('№;Наименование;Площадь, см2');

    for (int i = 0; i < record.samples.length; i++) {
      final s = record.samples[i];
      sb.writeln('${i + 1};${s.name};${s.areaCm2.toStringAsFixed(2)}');
    }

    final String safeId = record.id.replaceAll(RegExp(r'[^\w\d]'), '_');
    final String filename = 'Площади_${safeId}.csv';
    final File savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2563EB),
          content: Text('Файл сохранён:\n$filename'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Отправить',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(savedFile.path)]),
          ),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Ведомость площадей');
    }
  }

  static Future<void> exportGostProtocol({
    required BuildContext context,
    required String seriesId,
    required List<SampleStrengthData> samples,
    required double avgTensile,
    required double avgComp,
    bool shareImmediately = false,
  }) async {
    final StringBuffer sb = StringBuffer();

    // Графа 4 (Интервал, м) занимает 2 колонки, графа 6 (Литотип) — 1 колонку
    sb.writeln(
      '№;'
      '"Шифр\nпробы";;;'
      '"№ Скважины";'
      '"Интервал от,\nм";"Интервал до,\nм";'
      'Состояние;'
      '"Литологический\nтип";'
      '"Площадь скола,\nсм2";'
      '"Разрушающая\nнагрузка, кН";'
      'K;'
      '"Предел прочности на\nрастяжение, МПа";'
      '"Среднее значение\nрастяжения, МПа";'
      '"Коэф.\nПересчета";'
      '"Шифр Коэф.\nПересчета";'
      '"Предел прочности на сжатие\nпо ГОСТ 24941-81, МПа";'
      '"Среднее значение\nсжатия, МПа"'
    );

    // Номера граф
    sb.writeln('1;2;;;3;4;;5;6;7;8;9;10;11;;;12;13');

    final int startRow = 3;
    final int endRow = startRow + samples.length - 1;

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final int r = startRow + i;

      final colA = '${i + 1}';
      final colB = s.part1;
      final colC = s.part2;
      final colD = s.part3;
      final colE = s.borehole;
      final colF = s.interval; // Интервал от
      final colG = '-';        // Интервал до
      final colH = s.condition;
      final colI = s.lithology;

      final colJ = s.areaCm2 > 0 ? s.areaCm2.toStringAsFixed(2) : '0.00';
      final colK = s.loadKn > 0 ? s.loadKn.toStringAsFixed(2) : '0.00';

      final colL = '"=ROUND(0.5076*(J$r^0.2506); 2)"';
      final colM = '"=IF(J$r>0; ROUND((7.5*K$r*L$r)/J$r; 2); 0)"';
      final colN = (i == 0) ? '"=ROUND(AVERAGE(M$startRow:M$endRow); 2)"' : '';
      final colO = '"=IF(M$r<=0; """"; IF(M$r<1; 12; IF(M$r<5; 16; 20)))"';
      final colP = '';
      final colQ = '"=IF(O$r<>""""; ROUND(M$r*O$r; 1); """")"';
      final colR = (i == 0) ? '"=IF(COUNT(Q$startRow:Q$endRow)>0; ROUND(AVERAGE(Q$startRow:Q$endRow); 1); """")"' : '';

      sb.writeln('$colA;$colB;$colC;$colD;$colE;$colF;$colG;$colH;$colI;$colJ;$colK;$colL;$colM;$colN;$colO;$colP;$colQ;$colR');
    }

    final String safeId = seriesId.replaceAll(RegExp(r'[^\w\d]'), '_');
    final String filename = 'Результаты_испытаний_${safeId}.csv';
    final File savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Файл сформирован:\n$filename'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Отправить',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(savedFile.path)]),
          ),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Результаты испытаний $seriesId');
    }
  }
}
