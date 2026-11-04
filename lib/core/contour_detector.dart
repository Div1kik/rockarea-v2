import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Сегментация объекта на белом листе бумаги через FloodFill связности
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    // 1. Масштабируем для быстрого и стабильного анализа без подвисаний
    const int maxDim = 500;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image small = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int startX = (normX * small.width).toInt().clamp(0, small.width - 1);
    final int startY = (normY * small.height).toInt().clamp(0, small.height - 1);

    final int w = small.width;
    final int h = small.height;

    // 2. Порог бумаги: большинство лабораторных листов имеют яркость > 180-190
    const double paperThreshold = 185.0;

    // Проверяем: если тапнули прямо в белый лист — отступаем
    if (small.getPixel(startX, startY).luminance > paperThreshold) {
      return _generateDefaultBox(normX, normY, 0.08);
    }

    final Uint8List visited = Uint8List(w * h);
    final List<int> queue = <int>[];

    final int startIdx = (startY * w) + startX;
    queue.add(startIdx);
    visited[startIdx] = 1;

    final List<Point<int>> objectPixels = [];

    // Максимальный радиус поиска от тапа (чтобы не уйти на соседние образцы)
    final int maxSearchDist = (math.min(w, h) * 0.35).toInt();

    int iterations = 0;
    while (queue.isNotEmpty && iterations < 50000) {
      iterations++;
      final int idx = queue.removeLast();
      final int cx = idx % w;
      final int cy = idx ~/ w;

      objectPixels.add(Point<int>(cx, cy));

      const List<int> dx = [-1, 1, 0, 0];
      const List<int> dy = [0, 0, -1, 1];

      for (int i = 0; i < 4; i++) {
        final int nx = cx + dx[i];
        final int ny = cy + dy[i];

        if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
          final int nIdx = (ny * w) + nx;
          if (visited[nIdx] == 0) {
            visited[nIdx] = 1;

            final double dist = math.sqrt(math.pow(nx - startX, 2) + math.pow(ny - startY, 2));
            if (dist <= maxSearchDist) {
              final double lum = small.getPixel(nx, ny).luminance.toDouble();
              // Все, что темнее чистого белого листа бумаги — тело объекта
              if (lum < paperThreshold) {
                queue.add(nIdx);
              }
            }
          }
        }
      }
    }

    if (objectPixels.length < 30) {
      return _generateDefaultBox(normX, normY, 0.08);
    }

    // 3. Находим крайние граничные точки по 8 направлениям компаса
    int minX = w, maxX = 0, minY = h, maxY = 0;
    double sumX = 0, sumY = 0;

    for (final p in objectPixels) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      sumX += p.x;
      sumY += p.y;
    }

    final double avgX = sumX / objectPixels.length;
    final double avgY = sumY / objectPixels.length;

    // Ищем самые удаленные точки пятна по 8 секторам от центра масс
    const int sectors = 8;
    final List<Point<int>?> extremePoints = List.filled(sectors, null);
    final List<double> maxDistances = List.filled(sectors, 0.0);

    for (final p in objectPixels) {
      final double ang = math.atan2(p.y - avgY, p.x - avgX);
      int sector = (((ang + math.pi) / (2 * math.pi)) * sectors).floor() % sectors;

      final double d = math.pow(p.x - avgX, 2) + math.pow(p.y - avgY, 2) as double;
      if (d > maxDistances[sector]) {
        maxDistances[sector] = d;
        extremePoints[sector] = p;
      }
    }

    final List<Offset> contour = [];
    for (int i = 0; i < sectors; i++) {
      final pt = extremePoints[i];
      if (pt != null) {
        contour.add(Offset(pt.x / w, pt.y / h));
      }
    }

    if (contour.length < 4) {
      return [
        Offset(minX / w, minY / h),
        Offset(maxX / w, minY / h),
        Offset(maxX / w, maxY / h),
        Offset(minX / w, maxY / h),
      ];
    }

    return contour;
  }

  static List<Offset> _generateDefaultBox(double cx, double cy, double r) {
    return [
      Offset((cx - r).clamp(0.0, 1.0), (cy - r).clamp(0.0, 1.0)),
      Offset((cx + r).clamp(0.0, 1.0), (cy - r).clamp(0.0, 1.0)),
      Offset((cx + r).clamp(0.0, 1.0), (cy + r).clamp(0.0, 1.0)),
      Offset((cx - r).clamp(0.0, 1.0), (cy + r).clamp(0.0, 1.0)),
    ];
  }
}
