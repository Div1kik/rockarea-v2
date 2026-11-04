import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Радиальный сканер границы: выпускает 16 лучей из точки клика и ищет край контраста
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
    double tolerance = 35.0,
  }) {
    final int cx = (normX * image.width).toInt().clamp(0, image.width - 1);
    final int cy = (normY * image.height).toInt().clamp(0, image.height - 1);

    final img.Pixel seedPixel = image.getPixel(cx, cy);
    final double seedLum = seedPixel.luminance.toDouble();

    const int rayCount = 16;
    final int maxRadius = (math.min(image.width, image.height) * 0.28).toInt();
    final List<Offset> contour = [];

    for (int i = 0; i < rayCount; i++) {
      final double angle = (2 * math.pi / rayCount) * i;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);

      int foundDist = maxRadius;
      for (int r = 10; r < maxRadius; r += 3) {
        final int rx = (cx + r * cosA).toInt();
        final int ry = (cy + r * sinA).toInt();

        if (rx < 0 || rx >= image.width || ry < 0 || ry >= image.height) {
          foundDist = r;
          break;
        }

        final double lum = image.getPixel(rx, ry).luminance.toDouble();
        // Граница: если яркость скакнула (переход с образца на белый лист)
        if ((lum - seedLum).abs() > tolerance || lum > 215) {
          foundDist = r;
          break;
        }
      }

      // Нормализуем координаты обратно в диапазон 0.0 - 1.0
      final double normPointX = ((cx + foundDist * cosA) / image.width).clamp(0.0, 1.0);
      final double normPointY = ((cy + foundDist * sinA) / image.height).clamp(0.0, 1.0);
      contour.add(Offset(normPointX, normPointY));
    }

    return contour;
  }
}
