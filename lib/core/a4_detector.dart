import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class A4Detector {
  static const double a4PhysicalAreaCm2 = 623.7;

  /// Автоматический градиентный поиск листа бумаги А4 на столе
  static List<Offset> detectA4Corners(img.Image image) {
    const int maxDim = 360;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image small = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int w = small.width;
    final int h = small.height;

    // Считаем среднюю яркость в центральной области кадра
    double centerLum = 0;
    int cCount = 0;
    for (int y = (h * 0.3).toInt(); y < (h * 0.7).toInt(); y += 3) {
      for (int x = (w * 0.3).toInt(); x < (w * 0.7).toInt(); x += 3) {
        centerLum += small.getPixel(x, y).luminance;
        cCount++;
      }
    }
    final double avgCenterLum = cCount > 0 ? centerLum / cCount : 200.0;
    final double whiteThresh = math.max(165.0, avgCenterLum * 0.88);

    // Поиск границ белого пятна бумаги от центра наружу
    int top = 0, bottom = h - 1, left = 0, right = w - 1;

    // Поиск верхней границы (сканируем сверху вниз к центру)
    for (int y = (h * 0.1).toInt(); y < (h * 0.5).toInt(); y++) {
      int whites = 0;
      for (int x = (w * 0.25).toInt(); x < (w * 0.75).toInt(); x += 2) {
        if (small.getPixel(x, y).luminance > whiteThresh) whites++;
      }
      if (whites > (w * 0.25)) {
        top = y;
        break;
      }
    }

    // Поиск нижней границы (сканируем снизу вверх к центру)
    for (int y = (h * 0.9).toInt(); y > (h * 0.5).toInt(); y--) {
      int whites = 0;
      for (int x = (w * 0.25).toInt(); x < (w * 0.75).toInt(); x += 2) {
        if (small.getPixel(x, y).luminance > whiteThresh) whites++;
      }
      if (whites > (w * 0.25)) {
        bottom = y;
        break;
      }
    }

    // Поиск левой границы
    for (int x = (w * 0.05).toInt(); x < (w * 0.5).toInt(); x++) {
      int whites = 0;
      for (int y = (h * 0.3).toInt(); y < (h * 0.7).toInt(); y += 2) {
        if (small.getPixel(x, y).luminance > whiteThresh) whites++;
      }
      if (whites > (h * 0.2)) {
        left = x;
        break;
      }
    }

    // Поиск правой границы
    for (int x = (w * 0.95).toInt(); x > (w * 0.5).toInt(); x--) {
      int whites = 0;
      for (int y = (h * 0.3).toInt(); y < (h * 0.7).toInt(); y += 2) {
        if (small.getPixel(x, y).luminance > whiteThresh) whites++;
      }
      if (whites > (h * 0.2)) {
        right = x;
        break;
      }
    }

    final double l = (left / w).clamp(0.04, 0.45);
    final double r = (right / w).clamp(0.55, 0.96);
    final double t = (top / h).clamp(0.08, 0.48);
    final double b = (bottom / h).clamp(0.52, 0.92);

    return [
      Offset(l, t), // Верхний левый
      Offset(r, t), // Верхний правый
      Offset(r, b), // Нижний правый
      Offset(l, b), // Нижний левый
    ];
  }
}
