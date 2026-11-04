import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Классическая сегментация: FloodFill связности + трассировка границы Мура (Moore-Neighbor)
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
    double colorTolerance = 45.0,
  }) {
    // 1. Приводим к рабочему разрешению для мгновенного анализа
    const int maxDim = 480;
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

    // Замер базового цвета образца в точке тапа (усреднение 3x3)
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

    // 2. Бинарная сегментация связной области (FloodFill)
    final Uint8List mask = Uint8List(w * h);
    final List<int> queue = <int>[];

    final int startIdx = (startY * w) + startX;
    queue.add(startIdx);
    mask[startIdx] = 1;

    int minX = startX, maxX = startX, minY = startY, maxY = startY;
    int pixelCount = 0;
    final int maxDist = (math.min(w, h) * 0.45).toInt();

    while (queue.isNotEmpty && pixelCount < 60000) {
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

              // Пиксель принадлежит объекту, если он не ушел в белый фон бумаги (>190)
              // и находится в пределах цветового разброса породы
              if (p.luminance < 192.0 && diff < (colorTolerance * 1.8)) {
                mask[nIdx] = 1;
                queue.add(nIdx);
              }
            }
          }
        }
      }
    }

    if (pixelCount < 30) {
      return _fallbackBox(normX, normY);
    }

    // 3. Трассировка внешнего контура Мура (Moore-Neighbor Tracing)
    // Находим верхний левый пиксель маски
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

    if (startContourX == -1) return _fallbackBox(normX, normY);

    // 8-связные соседи по часовой стрелке
    const List<Point> neighbors = [
      Point(0, -1), Point(1, -1), Point(1, 0), Point(1, 1),
      Point(0, 1), Point(-1, 1), Point(-1, 0), Point(-1, -1),
    ];

    final List<Offset> boundary = [];
    int currX = startContourX;
    int currY = startContourY;
    int backtrackDir = 0;

    int guard = 0;
    boundary.add(Offset(currX / w, currY / h));

    while (guard < 3000) {
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
          backtrackDir = (checkIdx + 5) % 8; // Поворот направления
          break;
        }
      }

      if (foundNext == -1 || (currX == startContourX && currY == startContourY)) {
        break;
      }

      boundary.add(Offset(currX / w, currY / h));
    }

    if (boundary.length < 8) return _fallbackBox(normX, normY);

    // 4. Сжатие контура (Ramer-Douglas-Peucker) до 10-14 точных ключевых вершин
    return _simplifyPolygon(boundary, epsilon: 0.012);
  }

  static List<Offset> _simplifyPolygon(List<Offset> points, {required double epsilon}) {
    if (points.length <= 8) return points;

    // Прореживаем шагом перед RDP
    final int step = math.max(1, points.length ~/ 120);
    final List<Offset> sampled = [for (int i = 0; i < points.length; i += step) points[i]];

    // RDP
    int maxIdx = 0;
    double maxDist = 0.0;
    for (int i = 1; i < sampled.length - 1; i++) {
      final double d = _distToSegment(sampled[i], sampled.first, sampled.last);
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxDist > epsilon && maxIdx > 0) {
      final left = _simplifyPolygon(sampled.sublist(0, maxIdx + 1), epsilon: epsilon);
      final right = _simplifyPolygon(sampled.sublist(maxIdx), epsilon: epsilon);
      final result = [...left.take(left.length - 1), ...right];
      return result.length >= 6 ? result : sampled;
    } else {
      return [sampled.first, sampled.last];
    }
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;
    final double l2 = dx * dx + dy * dy;
    if (l2 == 0) return (p - a).distance;
    final double t = math.max(0.0, math.min(1.0, ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / l2));
    final Offset proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  static List<Offset> _fallbackBox(double cx, double cy) {
    const double r = 0.06;
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
