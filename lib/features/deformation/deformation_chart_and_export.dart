import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'deformation_models.dart';

class DeformationChartCard extends StatefulWidget {
  final DeformationRecord record;
  const DeformationChartCard({super.key, required this.record});

  @override
  State<DeformationChartCard> createState() => _DeformationChartCardState();
}

class _DeformationChartCardState extends State<DeformationChartCard> {
  final GlobalKey _chartBoundaryKey = GlobalKey();
  bool _isSavingPng = false;

  Future<void> _exportChartPng() async {
    if (_isSavingPng) return;
    setState(() => _isSavingPng = true);
    try {
      final boundary = _chartBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      final safeCipher = (widget.record.cipher.isNotEmpty ? widget.record.cipher : widget.record.id)
          .replaceAll(RegExp(r'[^\w\dА-Яа-я]'), '_');
      final filename = 'График_деформаций_$safeCipher.png';

      File file;
      try {
        final downloadDir = Directory('/storage/emulated/0/Download');
        file = File('${downloadDir.path}/$filename');
        await file.writeAsBytes(pngBytes, flush: true);
      } catch (_) {
        final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        file = File('${dir.path}/$filename');
        await file.writeAsBytes(pngBytes, flush: true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2563EB),
            content: Text('График сохранен:\n${file.path}'),
            action: SnackBarAction(
              label: 'Отправить',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(file.path)]),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPng = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.show_chart, size: 18, color: Color(0xFF2563EB)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Диаграмма деформирования σ — ε₁, ε₂',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                  ),
                ),
                IconButton(
                  icon: _isSavingPng
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined, size: 20, color: Color(0xFF2563EB)),
                  tooltip: 'Сохранить график PNG',
                  onPressed: _exportChartPng,
                ),
              ],
            ),
          ),
          RepaintBoundary(
            key: _chartBoundaryKey,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.record.cipher.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 4),
                      child: Text(
                        'Проба: ${widget.record.cipher} •${widget.record.lithotype.name}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                    ),
                  SizedBox(
                    height: 240,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _StressStrainPainter(record: widget.record),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legendDot(const Color(0xFF2563EB), 'Нагружение (E₀, μ)'),
                      const SizedBox(width: 14),
                      _legendDot(const Color(0xFFF97316), 'Упругая разгрузка (E, ν)'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 3, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _StressStrainPainter extends CustomPainter {
  final DeformationRecord record;
  _StressStrainPainter({required this.record});

  @override
  void paint(Canvas canvas, Size size) {
    final double eGpa = record.modulusYoungEGpa;
    final double e0Gpa = record.modulusDeformationE0Gpa;
    final double nu = record.poissonNu;
    final double mu = record.transverseStrainMu;
    double rcMpa = record.equivalentRcMpa;
    if (rcMpa <= 0) rcMpa = eGpa > 0 ? (eGpa * 1000.0) / 300.0 : 50.0;

    if (eGpa <= 0 || e0Gpa <= 0) return;

    const double padLeft = 36.0;
    const double padRight = 14.0;
    const double padTop = 14.0;
    const double padBottom = 26.0;

    final double plotW = size.width - padLeft - padRight;
    final double plotH = size.height - padTop - padBottom;
    // Ось X=0 сдвинута на 34% от левого края области построения (влево идет поперечная e2, вправо - продольная e1)
    final double originX = padLeft + plotW * 0.34;
    final double originY = padTop + plotH;

    // Расчет характерных точек кривой (деформации в 10^-3, т.е. мм/м)
    final double sigma1 = rcMpa * 0.12;
    final double sigma2 = rcMpa * 0.50;
    final double sigmaPeak = rcMpa;

    // E в ГПа = 1000 МПа => e (в 10^-3) = sigma (МПа) / E (ГПа)
    final double e1AtS1 = (sigma1 / e0Gpa) * 1.15; // Начальное обжатие микротрещин
    final double e1AtS2 = sigma2 / e0Gpa;
    final double e1ElasticDrop = (sigma2 - sigma1) / eGpa;
    final double e1AtUnload = e1AtS2 - e1ElasticDrop;
    final double e1AtPeak = (sigmaPeak / e0Gpa) * 1.25;

    final double e2AtS1 = -mu * e1AtS1 * 0.85;
    final double e2AtS2 = -mu * e1AtS2;
    final double e2ElasticDrop = nu * e1ElasticDrop;
    final double e2AtUnload = e2AtS2 + e2ElasticDrop;
    final double e2AtPeak = -mu * e1AtPeak * 1.35; // Дилатансия перед разрушением

    final double maxRight = math.max(e1AtPeak * 1.12, 0.5);
    final double maxLeft = math.max(e2AtPeak.abs() * 1.15, 0.25);
    final double maxSigma = sigmaPeak * 1.12;

    final double rightSpanPx = (padLeft + plotW) - originX;
    final double leftSpanPx = originX - padLeft;

    Offset toCanvas(double eps, double sigma) {
      final double x = eps >= 0
          ? originX + (eps / maxRight) * rightSpanPx
          : originX - (eps.abs() / maxLeft) * leftSpanPx;
      final double y = originY - (sigma / maxSigma) * plotH;
      return Offset(x, y);
    }

    // Сетка
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 4; i++) {
      final y = originY - (plotH * i / 4);
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + plotW, y), gridPaint);
    }

    // Оси координат
    final axisPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 1.3;
    canvas.drawLine(Offset(padLeft, originY), Offset(padLeft + plotW, originY), axisPaint);
    canvas.drawLine(Offset(originX, padTop), Offset(originX, originY), axisPaint);

    // Кривая 1: Продольная деформация (вправо, синяя)
    final p0 = toCanvas(0, 0);
    final p1 = toCanvas(e1AtS1, sigma1);
    final p2 = toCanvas(e1AtS2, sigma2);
    final pPeak = toCanvas(e1AtPeak, sigmaPeak);

    final longPath = Path()
      ..moveTo(p0.dx, p0.dy)
      ..quadraticBezierTo((p0.dx + p1.dx) * 0.55, (p0.dy + p1.dy) * 0.45, p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..quadraticBezierTo(
        p2.dx + (pPeak.dx - p2.dx) * 0.35,
        p2.dy + (pPeak.dy - p2.dy) * 0.75,
        pPeak.dx,
        pPeak.dy,
      );

    canvas.drawPath(
      longPath,
      Paint()
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke,
    );

    // Петля упругой разгрузки по продольной оси (оранжевая)
    final pUnload = toCanvas(e1AtUnload, sigma1);
    canvas.drawLine(
      p2,
      pUnload,
      Paint()
        ..color = const Color(0xFFF97316)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Кривая 2: Поперечная деформация (влево, синяя)
    final t1 = toCanvas(e2AtS1, sigma1);
    final t2 = toCanvas(e2AtS2, sigma2);
    final tPeak = toCanvas(e2AtPeak, sigmaPeak);

    final transPath = Path()
      ..moveTo(p0.dx, p0.dy)
      ..quadraticBezierTo((p0.dx + t1.dx) * 0.55, (p0.dy + t1.dy) * 0.45, t1.dx, t1.dy)
      ..lineTo(t2.dx, t2.dy)
      ..quadraticBezierTo(
        t2.dx + (tPeak.dx - t2.dx) * 0.25,
        t2.dy + (tPeak.dy - t2.dy) * 0.72,
        tPeak.dx,
        tPeak.dy,
      );

    canvas.drawPath(
      transPath,
      Paint()
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke,
    );

    // Петля упругой разгрузки по поперечной оси (оранжевая)
    final tUnload = toCanvas(e2AtUnload, sigma1);
    canvas.drawLine(
      t2,
      tUnload,
      Paint()
        ..color = const Color(0xFFF97316)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Точки ключевых ступеней
    final dotPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawCircle(p2, 3.2, dotPaint);
    canvas.drawCircle(t2, 3.2, dotPaint);
    canvas.drawCircle(pPeak, 3.5, Paint()..color = const Color(0xFFDC2626));

    // Подписи осей и значений
    void drawLabel(String text, Offset pos, {Color color = const Color(0xFF475569), double fontSize = 9.5, bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }

    drawLabel('σ, МПа', Offset(originX + 4, padTop - 2), bold: true);
    drawLabel('Rc=${rcMpa.toStringAsFixed(0)}', Offset(2, pPeak.dy - 5), fontSize: 8.5);
    drawLabel('σ₂=${sigma2.toStringAsFixed(0)}', Offset(2, p2.dy - 5), fontSize: 8.5);
    drawLabel('← ε₂ (·10⁻³)', Offset(padLeft, originY + 6), fontSize: 9);
    drawLabel('ε₁ (·10⁻³) →', Offset(padLeft + plotW - 58, originY + 6), fontSize: 9);

    drawLabel(
      'E=${eGpa.toStringAsFixed(1)} ГПа',
      Offset(p2.dx + 4, p2.dy - 14),
      color: const Color(0xFFEA580C),
      bold: true,
    );
    drawLabel(
      'E₀=${e0Gpa.toStringAsFixed(1)} ГПа',
      Offset(p1.dx + 4, p1.dy + 2),
      color: const Color(0xFF2563EB),
      bold: true,
    );
  }

  @override
  bool shouldRepaint(covariant _StressStrainPainter oldDelegate) => true;
}

class DeformationExportService {
  static Future<void> exportDeformationCsv({
    required BuildContext context,
    required List<DeformationRecord> records,
    bool shareImmediately = false,
  }) async {
    if (records.isEmpty) return;

    final sb = StringBuffer();
    sb.write(
      '№;'
      '"Шифр пробы";'
      '"Скважина";'
      '"Интервал, м";'
      '"Литологический тип";'
      '"Состояние";'
      '"Методика определения";'
      '"Пористость n, %";'
      '"Предел прочности Rc, МПа";'
      '"Модуль упругости E, ГПа";'
      '"Модуль деформации E0, ГПа";'
      '"Коэф. Пуассона ν";'
      '"Коэф. попереч. деф. μ"\r\n',
    );
    sb.write('1;2;3;4;5;6;7;8;9;10;11;12;13\r\n');

    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      final methodStr = r.method == DeformationCalcMethod.indenters
          ? 'Сф. инденторы (ГОСТ 24941-81 / 59958-2021)'
          : 'Копер Протодьяконова (ГОСТ 21153.1-75) + пористость';
      final porStr = r.porosityPercent != null ? r.porosityPercent!.toStringAsFixed(1) : '-';

      sb.write(
        '${i + 1};' '${r.cipher.isNotEmpty ? r.cipher : r.id};'
        '${r.borehole};'
        '${r.interval};'
        '${r.lithotype.name};'
        '${r.condition};'
        '"$methodStr";'
        '$porStr;'
        '${r.equivalentRcMpa.toStringAsFixed(1)};'
        '${r.modulusYoungEGpa.toStringAsFixed(2)};' '${r.modulusDeformationE0Gpa.toStringAsFixed(2)};'
        '${r.poissonNu.toStringAsFixed(3)};' '${r.transverseStrainMu.toStringAsFixed(3)}\r\n',
      );
    }

    final formatted = 'sep=;\r\n${sb.toString()}';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(formatted)];

    final now = DateTime.now();
    final filename = records.length == 1
        ? 'Деформации_${(records.first.cipher.isNotEmpty ? records.first.cipher : records.first.id).replaceAll(RegExp(r'[^\w\dА-Яа-я]'), '_')}.csv'
        : 'Ведомость_деформаций_${now.day.toString().padLeft(2, '0')}_${now.month.toString().padLeft(2, '0')}.csv';

    File file;
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      file = File('${downloadDir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Ведомость сохранена в Загрузки:\n${file.path}'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Отправить',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(file.path)]),
          ),
        ),
      );
    }

    if (shareImmediately) {
      await Share.shareXFiles([XFile(file.path)], text: 'Деформационные характеристики (ГОСТ)');
    }
  }
}
