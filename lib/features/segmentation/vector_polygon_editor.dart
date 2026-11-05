import 'package:flutter/material.dart';

class RockAreaLogo extends StatelessWidget {
  final double size;
  const RockAreaLogo({super.key, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _RockAreaLogoPainter(),
        ),
        const SizedBox(height: 12),
        const Text(
          'ROCKAREA',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'GEOMECHANICS & PLANIMETRY',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.bold,
            fontSize: 8,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _RockAreaLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;

    // Скругленный фон (глубокий сланцевый антрацит)
    final bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.22),
    );
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRRect(bgRRect, bgPaint);

    // Сетка калибровки керна
    final gridPaint = Paint()
      ..color = const Color(0xFF334155).withOpacity(0.35)
      ..strokeWidth = 1.0;

    for (double i = 0.25; i <= 0.75; i += 0.25) {
      canvas.drawLine(Offset(s * 0.18, s * i), Offset(s * 0.82, s * i), gridPaint);
      canvas.drawLine(Offset(s * i, s * 0.18), Offset(s * i, s * 0.82), gridPaint);
    }

    // Точки геометрии кристалла керна
    final pTop = Offset(s * 0.50, s * 0.19);
    final pLeft = Offset(s * 0.28, s * 0.33);
    final pRight = Offset(s * 0.72, s * 0.33);
    final pMidL = Offset(s * 0.36, s * 0.51);
    final pMidR = Offset(s * 0.64, s * 0.51);
    final pCenter = Offset(s * 0.50, s * 0.43);
    final pBottom = Offset(s * 0.50, s * 0.67);

    void drawFacet(List<Offset> points, Color color) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    // Грани керна
    drawFacet([pTop, pLeft, pMidL, pCenter], const Color(0xFF2563EB)); // Левая синяя
    drawFacet([pTop, pRight, pMidR, pCenter], const Color(0xFF60A5FA)); // Правая светло-синяя
    drawFacet([pLeft, pMidL, pBottom], const Color(0xFF1D4ED8));        // Нижняя темно-синяя
    drawFacet([pMidL, pMidR, pBottom], const Color(0xFFF97316));        // Центральная оранжевая (акцент)
    drawFacet([pRight, pMidR, pBottom], const Color(0xFF3B82F6));       // Правая синяя

    // Узлы разметки (маркеры планиметрии)
    void drawNode(Offset o, Color inner, Color border) {
      canvas.drawCircle(o, s * 0.022, Paint()..color = inner);
      canvas.drawCircle(o, s * 0.022, Paint()..color = border..strokeWidth = 1.5..style = PaintingStyle.stroke);
    }

    drawNode(pTop, Colors.white, const Color(0xFF2563EB));
    drawNode(pLeft, Colors.white, const Color(0xFF2563EB));
    drawNode(pRight, Colors.white, const Color(0xFF2563EB));
    drawNode(pMidL, const Color(0xFFF97316), Colors.white);
    drawNode(pMidR, const Color(0xFFF97316), Colors.white);
    drawNode(pBottom, Colors.white, const Color(0xFFF97316));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
