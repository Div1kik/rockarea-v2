import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class A4Detector {
  /// Эталонная физическая площадь листа А4 (21.0 x 29.7 см)
  static const double a4PhysicalAreaCm2 = 623.7;

  /// Автоматический поиск 4 углов самого яркого и крупного прямоугольника (листа А4)
  static List<Offset> detectA4Corners(img.Image image) {
    const int maxDim = 300;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image small = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int w = small.width;
    final int h = small.height;

    int minX = w, maxX = 0, minY = h, maxY = 0;
    int whitePixelCount = 0;

    // Ищем границы самого светлого участка кадра (бумага: яркость > 185)
    for (int y = 0; y < h; y += 2) {
      for (int x = 0; x < w; x += 2) {
        final lum = small.getPixel(x, y).luminance;
        if (lum > 185) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          whitePixelCount++;
        }
      }
    }

    // Если лист уверенно найден в кадре
    if (whitePixelCount > (w * h * 0.08) && maxX > minX + 40 && maxY > minY + 40) {
      return [
        Offset(minX / w, minY / h), // Левый верхний
        Offset(maxX / w, minY / h), // Правый верхний
        Offset(maxX / w, maxY / h), // Правый нижний
        Offset(minX / w, maxY / h), // Левый нижний
      ];
    }

    // Дефолтная рамка А4 по центру кадра (отступ 15%)
    return const [
      Offset(0.15, 0.15),
      Offset(0.85, 0.15),
      Offset(0.85, 0.85),
      Offset(0.15, 0.85),
    ];
  }
}
