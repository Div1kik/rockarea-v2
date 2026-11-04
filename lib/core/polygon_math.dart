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
  /// Расчет площади произвольного многоугольника в пикселях по формуле Гаусса
  static double computeShoelaceArea(List<Offset> points) {
    if (points.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      final int next = (i + 1) % points.length;
      area += points[i].dx * points[next].dy - points[next].dx * points[i].dy;
    }
    return (area.abs()) / 2.0;
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
