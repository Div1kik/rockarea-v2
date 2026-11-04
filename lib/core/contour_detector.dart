import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Высокоточный локальный сегментатор границ по цветовому перепаду
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    const int maxDim = 450;
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

    // Считываем опорный цвет образца в точке касания
    double rSum = 0, gSum = 0, bSum = 0;
    int samples = 0;
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        final int px = (startX + dx).clamp(0, w - 1);
        final int py = (startY + dy).clamp(0, h - 1);
        final pixel = small.getPixel(px, py);
        rSum += pixel.r.toDouble();
        gSum += pixel.g.toDouble();
        bSum += pixel.b.toDouble();
        samples++;
      }
    }
    final double seedR = rSum / samples;
    final double seedG = gSum / samples;
    final double seedB = bSum / samples;

    const double colorTolerance = 55.0;

    final Uint8List mask = Uint8List(w * h);
    final List<int> queue = <int>[];

    final int startIdx = (startY * w) + startX;
    queue.add(startIdx);
    mask[startIdx] = 1;

    final List<math.Point<int>> objectPixels = [];
    final int maxRadius = (math.min(w, h) * 0.45).toInt();

    int iterations = 0;
    while (queue.isNotEmpty && iterations < 50000) {
      iterations++;
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
            mask[nIdx] = 1;

            final double dist = math.sqrt((nx - startX) * (nx - startX) + (ny - startY) * (ny - startY));
            if (dist <= maxRadius) {
              final p = small.getPixel(nx, ny);
              final double dr = p.r.toDouble() - seedR;
              final double dg = p.g.toDouble() - seedG;
              final double db = p.b.toDouble() - seedB;
              final double diff = math.sqrt(dr * dr + dg * dg + db * db);

              if (diff < colorTolerance && p.luminance < 210.0) {
                queue.add(nIdx);
              }
            }
          }
        }
      }
    }

    if (objectPixels.length < 30) {
      return _generateDefaultPolygon(normX, normY, 0.07);
    }

    // Вычисляем геометрический центр пятна
    double sumX = 0, sumY = 0;
    for (final p in objectPixels) {
      sumX += p.x;
      sumY += p.y;
    }
    final double avgX = sumX / objectPixels.length;
    final double avgY = sumY / objectPixels.length;

    // Выделяем граничные пиксели
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

    // Разбиваем на 12 направлений для точного огибания фигуры
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

    return contour.length >= 5 ? contour : _generateDefaultPolygon(normX, normY, 0.07);
  }

  static List<Offset> _generateDefaultPolygon(double cx, double cy, double r) {
    const int count = 8;
    final List<Offset> pts = [];
    for (int i = 0; i < count; i++) {
      final double ang = (2 * math.pi / count) * i;
      pts.add(Offset(
        (cx + r * math.cos(ang)).clamp(0.0, 1.0),
        (cy + r * math.sin(ang)).clamp(0.0, 1.0),
      ));
    }
    return pts;
  }
}
