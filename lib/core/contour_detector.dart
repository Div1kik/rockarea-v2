import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Высокоточный радиальный детектор границ с оптимизацией RDP до 6-10 ключевых вершин
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
    double gradientThreshold = 28.0,
  }) {
    final int cx = (normX * image.width).toInt().clamp(0, image.width - 1);
    final int cy = (normY * image.height).toInt().clamp(0, image.height - 1);

    const int rayCount = 32;
    final int maxRadius = (math.min(image.width, image.height) * 0.32).toInt();
    final List<Offset> rawPoints = [];

    for (int i = 0; i < rayCount; i++) {
      final double angle = (2 * math.pi / rayCount) * i;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);

      int bestDist = maxRadius;
      double maxGrad = 0.0;

      // Анализируем градиент вдоль луча с шагом в 2 пикселя
      for (int r = 12; r < maxRadius - 4; r += 2) {
        final int x1 = (cx + r * cosA).toInt();
        final int y1 = (cy + r * sinA).toInt();
        final int x2 = (cx + (r + 4) * cosA).toInt();
        final int y2 = (cy + (r + 4) * sinA).toInt();

        if (x2 < 0 || x2 >= image.width || y2 < 0 || y2 >= image.height) {
          bestDist = r;
          break;
        }

        final double lum1 = image.getPixel(x1, y1).luminance.toDouble();
        final double lum2 = image.getPixel(x2, y2).luminance.toDouble();
        final double grad = (lum2 - lum1).abs();

        if (grad > gradientThreshold && grad > maxGrad) {
          maxGrad = grad;
          bestDist = r + 2;
        }
      }

      final double px = ((cx + bestDist * cosA) / image.width).clamp(0.0, 1.0);
      final double py = ((cy + bestDist * sinA) / image.height).clamp(0.0, 1.0);
      rawPoints.add(Offset(px, py));
    }

    // Упрощаем замкнутый контур алгоритмом RDP (снижаем число узлов до ключевых)
    return _simplifyPolygonRDP(rawPoints, epsilon: 0.015);
  }

  static List<Offset> _simplifyPolygonRDP(List<Offset> points, {required double epsilon}) {
    if (points.length <= 6) return points;

    // Вспомогательный алгоритм Рамера-Дугласа-Пекера для замкнутых контуров
    final List<Offset> result = [];
    int maxIdx = 0;
    double maxDist = 0.0;

    for (int i = 1; i < points.length; i++) {
      final double dist = (points[i] - points[0]).distance;
      if (dist > maxDist) {
        maxDist = dist;
        maxIdx = i;
      }
    }

    final List<Offset> part1 = _rdpRecursive(points.sublist(0, maxIdx + 1), epsilon);
    final List<Offset> part2 = _rdpRecursive(points.sublist(maxIdx), epsilon);

    result.addAll(part1.take(part1.length - 1));
    result.addAll(part2);

    // Если точек осталось слишком мало — гарантируем минимум 6 для плавности круга
    if (result.length < 6) {
      final int step = math.max(1, points.length ~/ 8);
      return [for (int i = 0; i < points.length; i += step) points[i]];
    }

    return result;
  }

  static List<Offset> _rdpRecursive(List<Offset> points, double epsilon) {
    if (points.length < 3) return points;

    double maxDist = 0.0;
    int index = 0;
    final Offset start = points.first;
    final Offset end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final double d = _perpendicularDistance(points[i], start, end);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }

    if (maxDist > epsilon) {
      final List<Offset> left = _rdpRecursive(points.sublist(0, index + 1), epsilon);
      final List<Offset> right = _rdpRecursive(points.sublist(index), epsilon);
      return [...left.take(left.length - 1), ...right];
    } else {
      return [start, end];
    }
  }

  static double _perpendicularDistance(Offset p, Offset a, Offset b) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;
    final double mag = math.sqrt(dx * dx + dy * dy);
    if (mag == 0.0) return (p - a).distance;
    return ((p.dx - a.dx) * dy - (p.dy - a.dy) * dx).abs() / mag;
  }
}
