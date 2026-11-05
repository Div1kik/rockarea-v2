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
    Directory? targetDir;

    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        targetDir = downloadDir;
      }
    }

    targetDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

    final file = File('${targetDir.path}/$filename');
    
    // Корректный UTF-8 с BOM для гарантированного открытия кириллицы в Excel и Google Таблицах
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Экспорт только площадей: Номер, Наименование, Площадь (см2)
  static Future<void> exportGeometryOnly({
    required BuildContext context,
    required TestRecord record,
    required bool shareImmediately,
  }) async {
    final sb = StringBuffer();
    sb.writeln('ВЕДОМОСТЬ ПЛОЩАДЕЙ ОБРАЗЦОВ');
    sb.writeln('Серия;${record.id};Дата;${record.date}');
    sb.writeln('');
    sb.writeln('№;Наименование;Площадь, см2');

    for (int i = 0; i < record.samples.length; i++) {
      final s = record.samples[i];
      sb.writeln('${i + 1};${s.name};${s.areaCm2.toStringAsFixed(2)}');
    }

    final safeId = record.id.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'Площади_${safeId}.csv';
    final savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2563EB),
          content: Text('Таблица сохранена в Загрузки:\n${savedFile.path}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Ведомость площадей');
    }
  }

  /// Полная таблица: Расчёт нагрузки
  static Future<void> exportGostProtocol({
    required BuildContext context,
    required String seriesId,
    required List<SampleStrengthData> samples,
    required double avgTensile,
    required double avgComp,
    required bool shareImmediately,
  }) async {
    final sb = StringBuffer();

    // Шапка бланка испытаний
    sb.writeln('№;Шифр (Часть 1);Шифр (Часть 2);Шифр (Часть 3);Скважина;Интервал;Состояние;Литотип;Площадь скола S, см2;Нагрузка P, кН;K;Растяжение, МПа;Ср. растяжение, МПа;Коэф. пересчета;Сжатие Rc, МПа;Ср. сжатие Rc, МПа');

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final isFirst = (i == 0);

      final col1 = '${i + 1}';
      final colP1 = s.part1;
      final colP2 = s.part2;
      final colP3 = s.part3;
      final colBore = s.borehole;
      final colInt = s.interval;
      final colCond = s.condition;
      final colLith = s.lithology;
      final colS = s.areaCm2.toStringAsFixed(2);
      final colP = s.loadKn > 0 ? s.loadKn.toStringAsFixed(2) : '-';
      final colK = s.coeffK.toStringAsFixed(2);
      final colSigma = s.tensileStrengthMpa > 0 ? s.tensileStrengthMpa.toStringAsFixed(2) : '-';
      final colAvgSigma = isFirst ? (avgTensile > 0 ? avgTensile.toStringAsFixed(2) : '-') : '';
      final colO = s.conversionCoeff > 0 ? s.conversionCoeff.toInt().toString() : '-';
      final colRc = s.compStrengthMpa > 0 ? s.compStrengthMpa.toStringAsFixed(1) : '-';
      final colAvgRc = isFirst ? (avgComp > 0 ? avgComp.toStringAsFixed(1) : '-') : '';

      sb.writeln('$col1;$colP1;$colP2;$colP3;$colBore;$colInt;$colCond;$colLith;$colS;$colP;$colK;$colSigma;$colAvgSigma;$colO;$colRc;$colAvgRc');
    }

    final safeId = seriesId.replaceAll(RegExp(r'[^\w\d]'), '_');
    final filename = 'Расчет_нагрузки_${safeId}.csv';
    final savedFile = await _writeCsvFile(filename: filename, content: sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Расчёт нагрузки сохранён в Загрузки:\n${savedFile.path}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(savedFile.path)], text: 'Расчёт нагрузки образцов');
    }
  }
}
