import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Ровный контур объекта с фильтрацией градиента и автоматическим масштабом
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    final int cx = (normX * image.width).toInt().clamp(0, image.width - 1);
    final int cy = (normY * image.height).toInt().clamp(0, image.height - 1);

    // Усредняем яркость центральной точки образца (радиус 3 пикселя)
    double seedLum = 0.0;
    int sampleCount = 0;
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        final int sx = (cx + dx).clamp(0, image.width - 1);
        final int sy = (cy + dy).clamp(0, image.height - 1);
        seedLum += image.getPixel(sx, sy).luminance.toDouble();
        sampleCount++;
      }
    }
    seedLum /= sampleCount;

    const int rayCount = 8; // 8 узлов для быстрой и чистой ручной подгонки
    final int minR = (math.min(image.width, image.height) * 0.03).toInt().clamp(8, 60);
    final int maxR = (math.min(image.width, image.height) * 0.28).toInt();

    final List<double> distances = [];

    for (int i = 0; i < rayCount; i++) {
      final double angle = (2 * math.pi / rayCount) * i;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);

      int stopDist = maxR;
      for (int r = minR; r < maxR; r += 2) {
        final int px = (cx + r * cosA).toInt();
        final int py = (cy + r * sinA).toInt();

        if (px < 0 || px >= image.width || py < 0 || py >= image.height) {
          stopDist = r;
          break;
        }

        final double currentLum = image.getPixel(px, py).luminance.toDouble();

        // Срабатывание на границу листа: переход в ярко-белый фон (> 195) или скачок контраста
        if (currentLum > 195.0 || (currentLum - seedLum) > 35.0) {
          stopDist = r;
          break;
        }
      }
      distances.add(stopDist.toDouble());
    }

    // Сглаживание расстояний соседних лучей (ликвидация выбросов)
    final List<Offset> contour = [];
    for (int i = 0; i < rayCount; i++) {
      final double prev = distances[(i - 1 + rayCount) % rayCount];
      final double curr = distances[i];
      final double next = distances[(i + 1) % rayCount];
      final double smoothed = (prev + curr * 2.0 + next) / 4.0;

      final double angle = (2 * math.pi / rayCount) * i;
      final double normPointX = ((cx + smoothed * math.cos(angle)) / image.width).clamp(0.0, 1.0);
      final double normPointY = ((cy + smoothed * math.sin(angle)) / image.height).clamp(0.0, 1.0);
      contour.add(Offset(normPointX, normPointY));
    }

    return contour;
  }
}
