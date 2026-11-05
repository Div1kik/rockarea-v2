import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Сегментация объекта: FloodFill связности + прореженный обход границы
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
    double colorTolerance = 48.0,
  }) {
    const int maxDim = 450;
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

    // Замер базового цвета в точке клика
    double rAcc = 0, gAcc = 0, bAcc = 0;
    int samples = 0;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        final px = (startX + dx).clamp(0, w - 1);
        final py = (startY + dy).clamp(0, h - 1);
        final p = small.getPixel(px, py);
        rAcc += p.r.toDouble();
        gAcc += p.g.toDouble();
        bAcc += p.b.toDouble();
        samples++;
      }
    }
    final double seedR = rAcc / samples;
    final double seedG = gAcc / samples;
    final double seedB = bAcc / samples;

    final Uint8List mask = Uint8List(w * h);
    final List<int> queue = <int>[];

    final int startIdx = (startY * w) + startX;
    queue.add(startIdx);
    mask[startIdx] = 1;

    int minX = startX, maxX = startX, minY = startY, maxY = startY;
    int pixelCount = 0;
    final int maxDist = (math.min(w, h) * 0.45).toInt();

    while (queue.isNotEmpty && pixelCount < 50000) {
      pixelCount++;
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
            final double d = math.sqrt((nx - startX) * (nx - startX) + (ny - startY) * (ny - startY));
            if (d <= maxDist) {
              final p = small.getPixel(nx, ny);
              final double dr = p.r.toDouble() - seedR;
              final double dg = p.g.toDouble() - seedG;
              final double db = p.b.toDouble() - seedB;
              final double diff = math.sqrt(dr * dr + dg * dg + db * db);

              // Объект: пока не вышли на белый фон бумаги (>185) и цвет не улетел в фон
              if (p.luminance < 188.0 && diff < (colorTolerance * 2.0)) {
                mask[nIdx] = 1;
                queue.add(nIdx);
              }
            }
          }
        }
      }
    }

    if (pixelCount < 30) {
      return _generateDefaultBox(normX, normY);
    }

    // Трассировка внешнего контура
    int startContourX = -1;
    int startContourY = -1;
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        if (mask[(y * w) + x] == 1) {
          startContourX = x;
          startContourY = y;
          break;
        }
      }
      if (startContourX != -1) break;
    }

    if (startContourX == -1) return _generateDefaultBox(normX, normY);

    const List<Point> neighbors = [
      Point(0, -1), Point(1, -1), Point(1, 0), Point(1, 1),
      Point(0, 1), Point(-1, 1), Point(-1, 0), Point(-1, -1),
    ];

    final List<Offset> rawBoundary = [];
    int currX = startContourX;
    int currY = startContourY;
    int backtrackDir = 0;
    int guard = 0;

    rawBoundary.add(Offset(currX / w, currY / h));

    while (guard < 2500) {
      guard++;
      int foundNext = -1;

      for (int i = 0; i < 8; i++) {
        final int checkIdx = (backtrackDir + i) % 8;
        final int nx = currX + neighbors[checkIdx].x;
        final int ny = currY + neighbors[checkIdx].y;

        if (nx >= 0 && nx < w && ny >= 0 && ny < h && mask[(ny * w) + nx] == 1) {
          currX = nx;
          currY = ny;
          foundNext = checkIdx;
          backtrackDir = (checkIdx + 5) % 8;
          break;
        }
      }

      if (foundNext == -1 || (currX == startContourX && currY == startContourY)) {
        break;
      }

      rawBoundary.add(Offset(currX / w, currY / h));
    }

    if (rawBoundary.length < 6) return _generateDefaultBox(normX, normY);

    // Равномерная выборка 8-12 точек по периметру, исключающая скучивание в одном месте
    const int targetPoints = 10;
    final List<Offset> cleanContour = [];
    final double step = rawBoundary.length / targetPoints;

    for (int i = 0; i < targetPoints; i++) {
      final int idx = (i * step).toInt().clamp(0, rawBoundary.length - 1);
      cleanContour.add(rawBoundary[idx]);
    }

    return cleanContour;
  }

  static List<Offset> _generateDefaultBox(double cx, double cy) {
    const double r = 0.05;
    return [
      Offset(cx - r, cy - r),
      Offset(cx + r, cy - r),
      Offset(cx + r, cy + r),
      Offset(cx - r, cy + r),
    ];
  }
}

class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}
