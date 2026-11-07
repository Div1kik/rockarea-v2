import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class A4Detector {
  static const double a4PhysicalAreaCm2 = 623.7; // 21.0 x 29.7 см

  /// Обнаружение 4 углов листа А4 с фильтрацией фона
  static List<Offset> detectA4Corners(img.Image src) {
    // Уменьшаем копию для быстрой и устойчивой к шумам обработки
    const int targetWidth = 400;
    final double scale = targetWidth / src.width;
    final int targetHeight = (src.height * scale).round();
    final img.Image small = img.copyResize(src, width: targetWidth, height: targetHeight);

    // Вычисляем среднюю яркость и гистограмму для поиска порога белой бумаги
    int sumLum = 0;
    final int totalPixels = small.width * small.height;
    final List<int> lumValues = List<int>.filled(totalPixels, 0);

    int idx = 0;
    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final pixel = small.getPixel(x, y);
        final int l = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        lumValues[idx++] = l;
        sumLum += l;
      }
    }

    lumValues.sort();
    // Порог бумаги: отсекаем верхние 35% самых ярких пикселей сцены
    final int paperThreshold = lumValues[(totalPixels * 0.65).clamp(0, totalPixels - 1)];

    final List<math.Point<int>> paperPoints = [];
    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final pixel = small.getPixel(x, y);
        final int l = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        if (l >= paperThreshold) {
          paperPoints.add(math.Point(x, y));
        }
      }
    }

    if (paperPoints.length < 500) {
      // Резервная рамка по умолчанию с отступом 8%
      return const [
        Offset(0.08, 0.08),
        Offset(0.92, 0.08),
        Offset(0.92, 0.92),
        Offset(0.08, 0.92),
      ];
    }

    // Поиск экстремальных углов четырёхугольника (минимизация/максимизация x+y и x-y)
    math.Point<int> topLeft = paperPoints.first;
    math.Point<int> topRight = paperPoints.first;
    math.Point<int> bottomRight = paperPoints.first;
    math.Point<int> bottomLeft = paperPoints.first;

    int minSum = 999999;
    int maxSum = -999999;
    int minDiff = 999999;
    int maxDiff = -999999;

    for (final p in paperPoints) {
      final int sum = p.x + p.y;
      final int diff = p.x - p.y;

      if (sum < minSum) {
        minSum = sum;
        topLeft = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        bottomRight = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        topRight = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        bottomLeft = p;
      }
    }

    return [
      Offset(topLeft.x / small.width, topLeft.y / small.height),
      Offset(topRight.x / small.width, topRight.y / small.height),
      Offset(bottomRight.x / small.width, bottomRight.y / small.height),
      Offset(bottomLeft.x / small.width, bottomLeft.y / small.height),
    ];
  }
}
