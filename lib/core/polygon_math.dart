import 'dart:math' as math;
import 'package:flutter/material.dart';

class PolygonMath {
  /// Расчет площади произвольного многоугольника в пикселях по формуле Гаусса
  static double computeShoelaceArea(List<Offset> points) {
    if (points.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      int next = (i + 1) % points.length;
      area += points[i].dx * points[next].dy - points[next].dx * points[i].dy;
    }
    return (area.abs()) / 2.0;
  }

  /// Поиск индекса вершины, ближайшей к точке касания (в радиусе захвата)
  static int findNearestPoint(Offset touch, List<Offset> points, double hitRadius) {
    for (int i = 0; i < points.length; i++) {
      if ((points[i] - touch).distance <= hitRadius) {
        return i;
      }
    }
    return -1;
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
    final double l2 = math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2) as double;
    if (l2 == 0) return (p - a).distance;
    final double t = math.max(0, math.min(1, ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2));
    final Offset projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - projection).distance;
  }
}
