import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Адаптивный ROI-сканер границы керна на светлой лабораторной подложке
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    final int cx = (normX * image.width).toInt().clamp(0, image.width - 1);
    final int cy = (normY * image.height).toInt().clamp(0, image.height - 1);

    // 1. Оцениваем фоновую яркость образца в точке касания (ядро)
    double sampleLum = 0.0;
    int sampleCount = 0;
    final int kernelR = math.max(2, (image.width * 0.005).toInt());

    for (int dy = -kernelR; dy <= kernelR; dy += 2) {
      for (int dx = -kernelR; dx <= kernelR; dx += 2) {
        final int sx = (cx + dx).clamp(0, image.width - 1);
        final int sy = (cy + dy).clamp(0, image.height - 1);
        sampleLum += image.getPixel(sx, sy).luminance.toDouble();
        sampleCount++;
      }
    }
    sampleLum = (sampleCount > 0) ? sampleLum / sampleCount : 100.0;

    // 2. Параметры радиального сканирования
    const int rayCount = 8;
    final int minRadius = math.max(12, (math.min(image.width, image.height) * 0.02).toInt());
    final int maxRadius = (math.min(image.width, image.height) * 0.35).toInt();
    final int step = math.max(3, (image.width * 0.003).toInt());

    final List<double> rawDistances = [];

    // 3. Сканирование лучами с поиском границы перехода в бумагу
    for (int i = 0; i < rayCount; i++) {
      final double angle = (2 * math.pi / rayCount) * i;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);

      int detectedDist = maxRadius;

      for (int r = minRadius; r < maxRadius; r += step) {
        final int px = (cx + r * cosA).toInt();
        final int py = (cy + r * sinA).toInt();

        if (px < 0 || px >= image.width || py < 0 || py >= image.height) {
          detectedDist = r;
          break;
        }

        final double currentLum = image.getPixel(px, py).luminance.toDouble();

        // Критерий границы: выход на белый/светлый лист (>190) 
        // или резкий контрастный скачок относительно тела образца (>40 единиц)
        if (currentLum > 192.0 || (currentLum - sampleLum) > 42.0) {
          detectedDist = r;
          break;
        }
      }
      rawDistances.add(detectedDist.toDouble());
    }

    // 4. Сглаживание соседних лучей (ликвидация западаний в тени и щели скола)
    final List<Offset> contour = [];
    for (int i = 0; i < rayCount; i++) {
      final double prev = rawDistances[(i - 1 + rayCount) % rayCount];
      final double curr = rawDistances[i];
      final double next = rawDistances[(i + 1) % rayCount];

      final double smoothR = (prev + curr * 2.0 + next) / 4.0;
      final double angle = (2 * math.pi / rayCount) * i;

      final double normPointX = ((cx + smoothR * math.cos(angle)) / image.width).clamp(0.0, 1.0);
      final double normPointY = ((cy + smoothR * math.sin(angle)) / image.height).clamp(0.0, 1.0);
      contour.add(Offset(normPointX, normPointY));
    }

    return contour;
  }
}
