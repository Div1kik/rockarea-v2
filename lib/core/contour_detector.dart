import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Двумерный волновой детектор с фильтрацией внутренних надписей и гравировок
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    const int maxDim = 400;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image small = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int w = small.width;
    final int h = small.height;

    final int startX = (normX * w).toInt().clamp(0, w - 1);
    final int startY = (normY * h).toInt().clamp(0, h - 1);

    // Порог чистого белого листа бумаги
    const double paperLuminance = 184.0;

    // Если тапнули прямо в белый фон
    if (small.getPixel(startX, startY).luminance > paperLuminance) {
      return _generateDefaultBox(normX, normY);
    }

    final Uint8List mask = Uint8List(w * h);
    final List<int> queue = <int>[];

    final int startIdx = (startY * w) + startX;
    queue.add(startIdx);
    mask[startIdx] = 1;

    final List<math.Point<int>> objectPixels = [];
    final int maxDist = (math.min(w, h) * 0.45).toInt();

    int count = 0;
    while (queue.isNotEmpty && count < 45000) {
      count++;
      final int idx = queue.removeLast();
      final int cx = idx % w;
      final int cy = idx ~/ w;

      objectPixels.add(math.Point<int>(cx, cy));

      const List<int> dx = [-1, 1, 0, 0];
      const List<int> dy = [0, 0, -1, 1];

      for (int i = 0; i < 4; i++) {
        final int nx = cx + dx[i];
        final int ny = cy + dy[i];

        if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
          final int nIdx = (ny * w) + nx;
          if (mask[nIdx] == 0) {
            final double d = math.sqrt((nx - startX) * (nx - startX) + (ny - startY) * (ny - startY));
            if (d <= maxDist) {
              final lum = small.getPixel(nx, ny).luminance.toDouble();

              // Не останавливаемся на мелких белых надписях:
              // Пиксель считается фоном только если вокруг него тоже фон
              bool isPaper = false;
              if (lum > paperLuminance) {
                int whiteNeighbors = 0;
                for (int s = 1; s <= 2; s++) {
                  final int sx = (nx + dx[i] * s).clamp(0, w - 1);
                  final int sy = (ny + dy[i] * s).clamp(0, h - 1);
                  if (small.getPixel(sx, sy).luminance > paperLuminance) {
                    whiteNeighbors++;
                  }
                }
                if (whiteNeighbors >= 2) isPaper = true;
              }

              if (!isPaper) {
                mask[nIdx] = 1;
                queue.add(nIdx);
              }
            }
          }
        }
      }
    }

    if (objectPixels.length < 35) {
      return _generateDefaultBox(normX, normY);
    }

    // Вычисляем центр фигуры
    double sumX = 0, sumY = 0;
    for (final p in objectPixels) {
      sumX += p.x;
      sumY += p.y;
    }
    final double avgX = sumX / objectPixels.length;
    final double avgY = sumY / objectPixels.length;

    // Выделяем краевые граничные пиксели
    final List<math.Point<int>> edgePoints = [];
    for (final p in objectPixels) {
      final int x = p.x;
      final int y = p.y;
      if (x == 0 || x == w - 1 || y == 0 || y == h - 1 ||
          mask[(y * w) + (x - 1)] == 0 ||
          mask[(y * w) + (x + 1)] == 0 ||
          mask[((y - 1) * w) + x] == 0 ||
          mask[((y + 1) * w) + x] == 0) {
        edgePoints.add(p);
      }
    }

    // Равномерный охват по 12 секторам
    const int sectors = 12;
    final List<math.Point<int>?> borderPoints = List.filled(sectors, null);
    final List<double> sectorDist = List.filled(sectors, 0.0);

    for (final p in edgePoints) {
      final double ang = math.atan2(p.y - avgY, p.x - avgX);
      int sector = (((ang + math.pi) / (2 * math.pi)) * sectors).floor() % sectors;

      final double d = (p.x - avgX) * (p.x - avgX) + (p.y - avgY) * (p.y - avgY);
      if (d > sectorDist[sector]) {
        sectorDist[sector] = d;
        borderPoints[sector] = p;
      }
    }

    final List<Offset> contour = [];
    for (int i = 0; i < sectors; i++) {
      final pt = borderPoints[i];
      if (pt != null) {
        contour.add(Offset(pt.x / w, pt.y / h));
      }
    }

    return contour.length >= 5 ? contour : _generateDefaultBox(normX, normY);
  }

  static List<Offset> _generateDefaultBox(double cx, double cy) {
    const double r = 0.05;
    return [
      Offset((cx - r).clamp(0.0, 1.0), (cy - r).clamp(0.0, 1.0)),
      Offset((cx + r).clamp(0.0, 1.0), (cy - r).clamp(0.0, 1.0)),
      Offset((cx + r).clamp(0.0, 1.0), (cy + r).clamp(0.0, 1.0)),
      Offset((cx - r).clamp(0.0, 1.0), (cy + r).clamp(0.0, 1.0)),
    ];
  }
}
