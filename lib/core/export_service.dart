import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'archive_service.dart';
import '../features/strength/strength_calculator_sheet.dart';

class ExportService {
  /// Прямое сохранение в системную папку «Загрузки» Android или fallback в Docs
  static Future<File> _writeToStorage({
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
    // Добавляем UTF-8 BOM для корректного открытия кириллицы в Excel на ПК и смартфонах
    final List<int> bytes = [0xEF, 0xBB, 0xBF, ...content.codeUnits];
    await file.writeAsBytes(bytes);
    return file;
  }

  /// 1. Экспорт ТОЛЬКО геометрических размеров (планиметрия для аттестации)
  static Future<void> exportGeometryOnly({
    required BuildContext context,
    required TestRecord record,
    required bool shareImmediately,
  }) async {
    final sb = StringBuffer();
    sb.writeln('ВЕДОМОСТЬ ГЕОМЕТРИЧЕСКИХ ПАРАМЕТРОВ И ПЛОЩАДЕЙ ОБРАЗЦОВ');
    sb.writeln('Серия:;${record.id};Дата:;${record.date}');
    sb.writeln('Общая площадь серии, см2:;${record.totalAreaCm2.toStringAsFixed(2)}');
    sb.writeln('');
    sb.writeln('№ п/п;Шифр образца;Площадь скола, см2;Площадь контура, px');

    for (int i = 0; i < record.samples.length; i++) {
      final s = record.samples[i];
      sb.writeln('${i + 1};${s.name};${s.areaCm2.toStringAsFixed(2)};${s.areaPx.toStringAsFixed(0)}');
    }

    final safeId = record.id.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'RockArea_Геометрия_${safeId}.csv';
    final savedFile = await _writeToStorage(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2563EB),
          content: Text('Файл геометрии сохранён в Загрузки:\n${savedFile.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Ведомость площадей образцов керна');
    }
  }

  /// 2. Экспорт протокола ГОСТ 24941-81 с шапкой 1-в-1 по бланку Excel
  static Future<void> exportGostProtocol({
    required BuildContext context,
    required String seriesId,
    required List<SampleStrengthData> samples,
    required double avgTensile,
    required double avgComp,
    required bool shareImmediately,
  }) async {
    final sb = StringBuffer();

    // Строка 1 шапки (точное совпадение по столбцам A-R Excel)
    sb.writeln('№;Шифр пробы;;;№ Скважины;Интервал, м;Состояние;Литологический тип;Площадь скола, см2;Разрушающая нагрузка, кН;K;Предел прочности на растяжение, МПа;Среднее значение предела прочности на растяжение, МПа;Коэф. Пересчета;Шифр Коэф. Пересчета;Предел прочности на сжатие (расчетным методом по ГОСТ 24941-81), МПа;Среднее значение предела прочности на сжатие (расчетным методом по ГОСТ 24941-81), МПа');

    // Строка 2 нумерации колонок бланка (1..13)
    sb.writeln('1;2;;;3;4;5;6;7;8;9;10;11;;;12;13');

    // Заполнение строк с данными образцов
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final isFirst = (i == 0);

      final col1 = '${i + 1}';
      final col2_1 = s.part1;
      final col2_2 = s.part2;
      final col2_3 = s.part3;
      final col3 = s.borehole;
      final col4 = s.interval;
      final col5 = s.condition;
      final col6 = s.lithology;
      final col7 = s.areaCm2.toStringAsFixed(2);
      final col8 = s.loadKn > 0 ? s.loadKn.toStringAsFixed(2) : '0,00';
      final col9 = s.coeffK.toStringAsFixed(2);
      final col10 = s.tensileStrengthMpa > 0 ? s.tensileStrengthMpa.toStringAsFixed(2) : '-';
      final col11 = isFirst ? (avgTensile > 0 ? avgTensile.toStringAsFixed(2) : '-') : '';
      final colO = s.conversionCoeff > 0 ? s.conversionCoeff.toInt().toString() : '-';
      final colP = '-';
      final col12 = s.compStrengthMpa > 0 ? s.compStrengthMpa.toStringAsFixed(1) : '-';
      final col13 = isFirst ? (avgComp > 0 ? avgComp.toStringAsFixed(1) : '-') : '';

      sb.writeln('$col1;$col2_1;$col2_2;$col2_3;$col3;$col4;$col5;$col6;$col7;$col8;$col9;$col10;$col11;$colO;$colP;$col12;$col13');
    }

    final safeId = seriesId.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'ГОСТ_24941_${safeId}.csv';
    final savedFile = await _writeToStorage(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Протокол ГОСТ 24941-81 сохранён в Загрузки:\n${savedFile.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Протокол испытаний по ГОСТ 24941-81');
    }
  }
}
