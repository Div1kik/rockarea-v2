import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Автоматический поиск контура объекта по точке касания (нормализованные координаты 0.0 - 1.0)
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
    double tolerance = 35.0,
  }) {
    final int startX = (normX * image.width).toInt().clamp(0, image.width - 1);
    final int startY = (normY * image.height).toInt().clamp(0, image.height - 1);

    // Уменьшаем масштаб для быстрого анализа без лагов интерфейса
    const int maxDim = 600;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image resized = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int targetX = (startX * scale).toInt().clamp(0, resized.width - 1);
    final int targetY = (startY * scale).toInt().clamp(0, resized.height - 1);

    final img.Pixel seedPixel = resized.getPixel(targetX, targetY);
    final double seedLum = seedPixel.luminance.toDouble();

    // Быстрый FloodFill (поиск связанных пикселей похожей яркости относительно фона)
    final int w = resized.width;
    final int h = resized.height;
    final Uint8List mask = Uint8List(w * h);
    final List<int> queue = <int>[];

    queue.add((targetY * w) + targetX);
    mask[(targetY * w) + targetX] = 1;

    int minX = targetX;
    int maxX = targetX;
    int minY = targetY;
    int maxY = targetY;

    int iterations = 0;
    while (queue.isNotEmpty && iterations < 40000) {
      iterations++;
      final int idx = queue.removeLast();
      final int cx = idx % w;
      final int cy = idx ~/ w;

      if (cx < minX) minX = cx;
      if (cx > maxX) maxX = cx;
      if (cy < minY) minY = cy;
      if (cy > maxY) maxY = cy;

      const List<int> dx = [-1, 1, 0, 0];
      const List<int> dy = [0, 0, -1, 1];

      for (int i = 0; i < 4; i++) {
        final int nx = cx + dx[i];
        final int ny = cy + dy[i];

        if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
          final int nIdx = (ny * w) + nx;
          if (mask[nIdx] == 0) {
            final double nLum = resized.getPixel(nx, ny).luminance.toDouble();
            // Разница яркости между пикселями образца
            if ((nLum - seedLum).abs() <= tolerance && nLum < 220) {
              mask[nIdx] = 1;
              queue.add(nIdx);
            }
          }
        }
      }
    }

    if (iterations < 50) return [];

    // Выделение граничных точек (Marching edge)
    final List<Offset> rawBoundary = [];
    for (int y = minY; y <= maxY; y += 2) {
      for (int x = minX; x <= maxX; x += 2) {
        final int idx = (y * w) + x;
        if (mask[idx] == 1) {
          final bool isEdge = (x == 0 || x == w - 1 || y == 0 || y == h - 1) ||
              mask[idx - 1] == 0 ||
              mask[idx + 1] == 0 ||
              mask[idx - w] == 0 ||
              mask[idx + w] == 0;

          if (isEdge) {
            rawBoundary.add(Offset(x / (w * scale), y / (h * scale)));
          }
        }
      }
    }

    if (rawBoundary.length < 5) return [];

    // Сортировка точек по полярному углу относительно центра масс
    double avgX = 0;
    double avgY = 0;
    for (final p in rawBoundary) {
      avgX += p.dx;
      avgY += p.dy;
    }
    avgX /= rawBoundary.length;
    avgY /= rawBoundary.length;
    final Offset center = Offset(avgX, avgY);

    rawBoundary.sort((a, b) {
      final double angA = math.atan2(a.dy - center.dy, a.dx - center.dx);
      final double angB = math.atan2(b.dy - center.dy, b.dx - center.dx);
      return angA.compareTo(angB);
    });

    // Упрощение полигона: берем 16 характерных вершин для удобного редактирования
    final List<Offset> simplified = [];
    final int step = math.max(1, rawBoundary.length ~/ 16);
    for (int i = 0; i < rawBoundary.length; i += step) {
      simplified.add(rawBoundary[i]);
    }

    return simplified;
  }
}
