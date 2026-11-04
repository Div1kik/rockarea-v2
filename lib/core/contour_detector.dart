import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Адаптивный поиск границы: ровный 8-узловой полигон без колючих артефактов
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    final int cx = (normX * image.width).toInt().clamp(0, image.width - 1);
    final int cy = (normY * image.height).toInt().clamp(0, image.height - 1);

    final img.Pixel seedPixel = image.getPixel(cx, cy);
    final double seedLum = seedPixel.luminance.toDouble();

    // 8 лучей для создания аккуратного полигона без «пилы»
    const int rayCount = 8;
    final int minRadius = (math.min(image.width, image.height) * 0.05).toInt();
    final int maxRadius = (math.min(image.width, image.height) * 0.22).toInt();
    final List<double> radii = [];

    for (int i = 0; i < rayCount; i++) {
      final double angle = (2 * math.pi / rayCount) * i;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);

      int stopDist = maxRadius;
      for (int r = minRadius; r < maxRadius; r += 3) {
        final int rx = (cx + r * cosA).toInt();
        final int ry = (cy + r * sinA).toInt();

        if (rx < 0 || rx >= image.width || ry < 0 || ry >= image.height) {
          stopDist = r;
          break;
        }

        final double lum = image.getPixel(rx, ry).luminance.toDouble();
        // Детекция резкого выхода на светлый фон бумаги (> 200) или скачка яркости
        if ((lum - seedLum) > 30.0 || lum > 205.0) {
          stopDist = r;
          break;
        }
      }
      radii.add(stopDist.toDouble());
    }

    // Сглаживание радиусов соседних лучей (устранение колючих выбросов)
    final List<double> smoothedRadii = List.filled(rayCount, 0.0);
    for (int i = 0; i < rayCount; i++) {
      final prev = radii[(i - 1 + rayCount) % rayCount];
      final curr = radii[i];
      final next = radii[(i + 1) % rayCount];
      smoothedRadii[i] = (prev + curr * 2.0 + next) / 4.0;
    }

    final List<Offset> polygon = [];
    for (int i = 0; i < rayCount; i++) {
      final double angle = (2 * math.pi / rayCount) * i;
      final double r = smoothedRadii[i];
      final double px = ((cx + r * math.cos(angle)) / image.width).clamp(0.0, 1.0);
      final double py = ((cy + r * math.sin(angle)) / image.height).clamp(0.0, 1.0);
      polygon.add(Offset(px, py));
    }

    return polygon;
  }
}
