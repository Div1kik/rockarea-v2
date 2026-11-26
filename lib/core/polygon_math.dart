import 'dart:math' as math;
import 'package:flutter/material.dart';

class SamplePolygon {
  String id;
  List<Offset> points;
  Color color;

  SamplePolygon({
    required this.id,
    required this.points,
    this.color = const Color(0xFF10B981),
  });
}

class PolygonMath {
  /// Расчет площади произвольного многоугольника по формуле Гаусса (Шнурования)
  static double computeShoelaceArea(List<Offset> points) {
    if (points.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      final int next = (i + 1) % points.length;
      area += points[i].dx * points[next].dy - points[next].dx * points[i].dy;
    }
    return (area.abs()) / 2.0;
  }

  /// Построение матрицы гомографии 3x3: экранные координаты углов А4 -> реальные см (21.0 x 29.7 см)
  static List<double>? computeA4Homography(List<Offset> a4ScreenCorners) {
    if (a4ScreenCorners.length != 4) return null;

    // Определяем ориентацию листа на экране (портретная или альбомная)
    final double topWidth = (a4ScreenCorners[1] - a4ScreenCorners[0]).distance;
    final double leftHeight = (a4ScreenCorners[3] - a4ScreenCorners[0]).distance;
    final bool isLandscape = topWidth > leftHeight;

    final double wCm = isLandscape ? 29.7 : 21.0;
    final double hCm = isLandscape ? 21.0 : 29.7;

    final List<Offset> dst = [
      const Offset(0.0, 0.0),
      Offset(wCm, 0.0),
      Offset(wCm, hCm),
      Offset(0.0, hCm),
    ];

    // Решаем систему 8x8 методом Гаусса для матрицы H = [h0..h7, 1]
    final List<List<double>> a = List.generate(8, (_) => List.filled(9, 0.0));
    for (int i = 0; i < 4; i++) {
      final double x = a4ScreenCorners[i].dx;
      final double y = a4ScreenCorners[i].dy;
      final double u = dst[i].dx;
      final double v = dst[i].dy;

      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }

    for (int col = 0; col < 8; col++) {
      int pivot = col;
      for (int row = col + 1; row < 8; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) {
          pivot = row;
        }
      }
      if (a[pivot][col].abs() < 1e-10) return null;

      final temp = a[col];
      a[col] = a[pivot];
      a[pivot] = temp;

      final double div = a[col][col];
      for (int j = col; j <= 8; j++) {
        a[col][j] /= div;
      }

      for (int row = 0; row < 8; row++) {
        if (row != col) {
          final double factor = a[row][col];
          for (int j = col; j <= 8; j++) {
            a[row][j] -= factor * a[col][j];
          }
        }
      }
    }

    return [
      a[0][8], a[1][8], a[2][8],
      a[3][8], a[4][8], a[5][8],
      a[6][8], a[7][8], 1.0,
    ];
  }

  /// Перевод точки с экрана в истинные сантиметры на плоскости листа А4
  static Offset projectPointToA4Cm(Offset p, List<double> h) {
    final double denom = h[6] * p.dx + h[7] * p.dy + h[8];
    if (denom.abs() < 1e-9) return Offset.zero;
    final double xCm = (h[0] * p.dx + h[1] * p.dy + h[2]) / denom;
    final double yCm = (h[3] * p.dx + h[4] * p.dy + h[5]) / denom;
    return Offset(xCm, yCm);
  }

  /// Точный расчет площади образца в см2 с полной компенсацией наклона камеры
  static double computeCorrectedAreaCm2({
    required List<Offset> polygonPoints,
    required List<Offset> a4ScreenCorners,
    required double fallbackPixelsPerCm2,
  }) {
    if (polygonPoints.length < 3) return 0.0;
    final h = computeA4Homography(a4ScreenCorners);
    if (h == null) {
      return computeShoelaceArea(polygonPoints) / fallbackPixelsPerCm2;
    }

    final projectedCmPoints = polygonPoints.map((pt) => projectPointToA4Cm(pt, h)).toList();
    return computeShoelaceArea(projectedCmPoints);
  }

  /// Поиск индекса вершины, ближайшей к точке касания
  static int findNearestPoint(Offset touch, List<Offset> points, double hitRadius) {
    for (int i = 0; i < points.length; i++) {
      if ((points[i] - touch).distance <= hitRadius) {
        return i;
      }
    }
    return -1;
  }

  /// Проверка, попал ли тап внутрь замкнутого полигона (Ray-Casting)
  static bool isPointInside(Offset p, List<Offset> points) {
    if (points.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
      final bool intersect = ((points[i].dy > p.dy) != (points[j].dy > p.dy)) &&
          (p.dx < (points[j].dx - points[i].dx) * (p.dy - points[i].dy) / (points[j].dy - points[i].dy) + points[i].dx);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Поиск ближайшего отрезка для вставки новой точки по тапу
  static int findNearestEdgeIndex(Offset touch, List<Offset> points, double maxDist) {
    if (points.length < 3) return -1;
    int bestIndex = -1;
    double minDistance = double.infinity;

    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      final dist = _pointToSegmentDistance(touch, p1, p2);
      if (dist < minDistance && dist <= maxDist) {
        minDistance = dist;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  static double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;
    final double l2 = dx * dx + dy * dy;
    if (l2 == 0) return (p - a).distance;

    final double t = math.max(0.0, math.min(1.0, ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / l2));
    final Offset projection = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - projection).distance;
  }
}
