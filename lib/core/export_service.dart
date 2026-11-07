import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'archive_service.dart';
import '../features/strength/strength_calculator_sheet.dart';

class ExportService {
  /// Мгновенная запись CSV с директивой Excel sep=; и Windows CRLF
  static Future<File> _writeCsvFile({
    required String filename,
    required String content,
  }) async {
    File file;
    // Директива sep=; сообщает Microsoft Excel на ПК принудительно делить колонки по точке с запятой
    final formattedContent = 'sep=;\r\n$content';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(formattedContent)];

    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      file = File('${downloadDir.path}/$filename');
      await file.writeAsBytes(bytes, flush: false);
      return file;
    } catch (_) {
      final appDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      file = File('${appDir.path}/$filename');
      await file.writeAsBytes(bytes, flush: false);
      return file;
    }
  }

  /// 1. Ведомость «Площади»
  static Future<void> exportGeometryOnly({
    required BuildContext context,
    required TestRecord record,
    bool shareImmediately = false,
  }) async {
    final sb = StringBuffer();
    sb.write('ВЕДОМОСТЬ ПЛОЩАДЕЙ ОБРАЗЦОВ\r\n');
    sb.write('Серия;${record.id};Дата;${record.date}\r\n');
    sb.write('\r\n');
    sb.write('№;Наименование;Площадь, см2\r\n');

    for (int i = 0; i < record.samples.length; i++) {
      final s = record.samples[i];
      sb.write('${i + 1};${s.name};${s.areaCm2.toStringAsFixed(2)}\r\n');
    }

    final safeId = record.id.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'Площади_${safeId}.csv';
    final savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2563EB),
          content: Text('Файл сохранен в Загрузки:\n${savedFile.path}'),
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

  /// 2. Результаты испытаний ГОСТ 24941-81
  static Future<void> exportGostProtocol({
    required BuildContext context,
    required String seriesId,
    required List<SampleStrengthData> samples,
    required double avgTensile,
    required double avgComp,
    bool shareImmediately = false,
  }) async {
    final sb = StringBuffer();

    // 1-я строка: Высокая чистая шапка (без дефисов, переносы строк внутри кавычек)
    sb.write(
      '№;'
      '"Шифр\nпробы";;;'
      '"№ Скважины";'
      '"Интервал, м";'
      'Состояние;'
      '"Литологический\nтип";;'
      '"Площадь скола,\nсм2";'
      '"Разрушающая\nнагрузка, кН";'
      'K;'
      '"Предел прочности на\nрастяжение, МПа";'
      '"Среднее значение\nрастяжения, МПа";'
      '"Коэф.\nПересчета";'
      '"Шифр Коэф.\nПересчета";'
      '"Предел прочности на сжатие\nпо ГОСТ 24941-81, МПа";'
      '"Среднее значение\nсжатия, МПа"\r\n'
    );

    // 2-я строка: Номера граф
    sb.write('1;2;;;3;4;5;6;;7;8;9;10;11;;;12;13\r\n');

    final int startRow = 4; // С учетом служебной строки sep=; данные начинаются с 4 строки
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

      final colJ = s.areaCm2 > 0 ? s.areaCm2.toStringAsFixed(2) : '0.00';
      final colK = s.loadKn > 0 ? s.loadKn.toStringAsFixed(2) : '0.00';

      final colL = '"=ROUND(0.5076*(J$r^0.2506); 2)"';
      final colM = '"=IF(J$r>0; ROUND((7.5*K$r*L$r)/J$r; 2); 0)"';
      final colN = (i == 0) ? '"=ROUND(AVERAGE(M$startRow:M$endRow); 2)"' : '';
      final colO = '"=IF(M$r<=0; """"; IF(M$r<1; 12; IF(M$r<5; 16; 20)))"';
      final colP = '';
      final colQ = '"=IF(O$r<>""""; ROUND(M$r*O$r; 1); """")"';
      final colR = (i == 0) ? '"=IF(COUNT(Q$startRow:Q$endRow)>0; ROUND(AVERAGE(Q$startRow:Q$endRow); 1); """")"' : '';

      sb.write('$colA;$colB;$colC;$colD;$colE;$colF;$colG;$colH;$colI;$colJ;$colK;$colL;$colM;$colN;$colO;$colP;$colQ;$colR\r\n');
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
