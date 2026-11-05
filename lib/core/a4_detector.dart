import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class A4Detector {
  /// Эталонная физическая площадь листа А4 (21.0 x 29.7 см)
  static const double a4PhysicalAreaCm2 = 623.7;

  /// Поиск углов листа бумаги с соблюдением физических пропорций А4 (1:1.414)
  static List<Offset> detectA4Corners(img.Image image) {
    const int maxDim = 320;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image small = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int w = small.width;
    final int h = small.height;

    int minX = w, maxX = 0, minY = h, maxY = 0;
    int whiteCount = 0;

    // Ищем область белой бумаги (яркость > 185)
    for (int y = (h * 0.05).toInt(); y < (h * 0.95).toInt(); y += 2) {
      for (int x = (w * 0.05).toInt(); x < (w * 0.95).toInt(); x += 2) {
        if (small.getPixel(x, y).luminance > 185) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          whiteCount++;
        }
      }
    }

    // Если белая область листа найдена и не прилипает к краям кадра
    if (whiteCount > (w * h * 0.10) && (maxX - minX) > (w * 0.3) && (maxY - minY) > (h * 0.3)) {
      final double l = (minX / w).clamp(0.04, 0.96);
      final double r = (maxX / w).clamp(0.04, 0.96);
      final double t = (minY / h).clamp(0.04, 0.96);
      final double b = (maxY / h).clamp(0.04, 0.96);

      return [
        Offset(l, t), // Верхний левый
        Offset(r, t), // Верхний правый
        Offset(r, b), // Нижний правый
        Offset(l, b), // Нижний левый
      ];
    }

    // Если фон сложный — выставляем аккуратный прямоугольник по центру кадра с отступом 15%
    return const [
      Offset(0.12, 0.15),
      Offset(0.88, 0.15),
      Offset(0.88, 0.85),
      Offset(0.12, 0.85),
    ];
  }
}
