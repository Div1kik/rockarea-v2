import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Сегментирование как реальных образцов породы на А4, так и контуров, обведенных ручкой/карандашом
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    const int maxDim = 820;
    final double scale = (image.width > image.height)
        ? maxDim / image.width
        : maxDim / image.height;

    final int tw = (image.width * scale).toInt();
    final int th = (image.height * scale).toInt();
    final img.Image thumb = img.copyResize(
      image,
      width: tw,
      height: th,
      interpolation: img.Interpolation.linear,
    );

    final List<List<double>> lumMap = List.generate(th, (_) => List.filled(tw, 0.0));
    final List<List<double>> chromaMap = List.generate(th, (_) => List.filled(tw, 0.0));

    for (int y = 0; y < th; y++) {
      for (int x = 0; x < tw; x++) {
        final p = thumb.getPixel(x, y);
        lumMap[y][x] = img.getLuminance(p).toDouble();
        final maxC = math.max(p.r, math.max(p.g, p.b)).toDouble();
        final minC = math.min(p.r, math.min(p.g, p.b)).toDouble();
        chromaMap[y][x] = maxC - minC;
      }
    }

    // Легкий 3x3 blur по яркости для подавления зернистости бумаги
    final List<List<double>> smoothLum = List.generate(th, (y) => List<double>.from(lumMap[y]));
    for (int y = 1; y < th - 1; y++) {
      for (int x = 1; x < tw - 1; x++) {
        double sum = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            sum += lumMap[y + dy][x + dx];
          }
        }
        smoothLum[y][x] = sum / 9.0;
      }
    }

    final int startX = (normX * tw).toInt().clamp(4, tw - 5);
    final int startY = (normY * th).toInt().clamp(4, th - 5);

    // 1. Локальная оценка яркости и цветности бумаги вокруг точки касания
    final List<double> paperLums = [];
    final List<double> paperChroma = [];
    for (int dy = -110; dy <= 110; dy += 7) {
      for (int dx = -110; dx <= 110; dx += 7) {
        final distSq = dx * dx + dy * dy;
        if (distSq < 2000 || distSq > 12100) continue;
        final px = startX + dx;
        final py = startY + dy;
        if (px < 2 || px >= tw - 2 || py < 2 || py >= th - 2) continue;

        final lum = smoothLum[py][px];
        if (lum > 105) {
          paperLums.add(lum);
          paperChroma.add(chromaMap[py][px]);
        }
      }
    }

    paperLums.sort();
    paperChroma.sort();
    final double localPaperLum = paperLums.isNotEmpty
        ? paperLums[(paperLums.length * 0.65).toInt()]
        : 200.0;
    final double localPaperChroma = paperChroma.isNotEmpty
        ? paperChroma[(paperChroma.length * 0.50).toInt()]
        : 12.0;

    final double centerLum = smoothLum[startY][startX];
    final double centerChroma = chromaMap[startY][startX];

    final bool isPaperInside = (centerLum - localPaperLum).abs() < 24.0 &&
        (centerChroma - localPaperChroma).abs() < 12.0;

    if (isPaperInside) {
      return _extractHandDrawnMultiPass(
        smoothLum: smoothLum,
        tw: tw,
        th: th,
        startX: startX,
        startY: startY,
        localPaperLum: localPaperLum,
        normX: normX,
        normY: normY,
      );
    }

    // Режим 1: Объемный образец породы на белом листе
    final bool isLightRock = centerLum > localPaperLum - 55;
    final double lumThreshold = isLightRock
        ? localPaperLum - 18.0
        : localPaperLum - 34.0;

    bool isRockPixel(int x, int y) {
      final double lum = smoothLum[y][x];
      final double chroma = chromaMap[y][x];

      if (lum < lumThreshold) {
        if (lum > localPaperLum - 38 && (chroma - localPaperChroma).abs() < 6.0 && centerChroma > 12.0) {
          return false;
        }
        return true;
      }
      if (isLightRock && (chroma - localPaperChroma) > 10.0) {
        return true;
      }
      return false;
    }

    final List<List<bool>> mask = List.generate(th, (_) => List.filled(tw, false));
    final List<math.Point<int>> queue = [math.Point(startX, startY)];
    mask[startY][startX] = true;

    int minX = startX, maxX = startX, minY = startY, maxY = startY;
    int pixelCount = 0;

    const dirsX = [1, -1, 0, 0];
    const dirsY = [0, 0, 1, -1];

    while (queue.isNotEmpty && pixelCount < 140000) {
      final curr = queue.removeLast();
      pixelCount++;

      if (curr.x < minX) minX = curr.x;
      if (curr.x > maxX) maxX = curr.x;
      if (curr.y < minY) minY = curr.y;
      if (curr.y > maxY) maxY = curr.y;

      for (int i = 0; i < 4; i++) {
        final nx = curr.x + dirsX[i];
        final ny = curr.y + dirsY[i];
        if (nx <= 2 || nx >= tw - 3 || ny <= 2 || ny >= th - 3) continue;
        if (!mask[ny][nx] && isRockPixel(nx, ny)) {
          mask[ny][nx] = true;
          queue.add(math.Point(nx, ny));
        }
      }
    }

    if (pixelCount < 25) return _fallbackBox(normX, normY);
    return _traceAndSmoothMask(mask, tw, th, minX, minY, maxX, maxY, normX, normY, isHandDrawn: false);
  }

  /// Многоуровневая эскалация чувствительности (3 прохода), чтобы поймать даже очень тонкий карандаш
  static List<Offset> _extractHandDrawnMultiPass({
    required List<List<double>> smoothLum,
    required int tw,
    required int th,
    required int startX,
    required int startY,
    required double localPaperLum,
    required double normX,
    required double normY,
  }) {
    // Предварительно считаем карту перепадов яркости (8 направлений + градиент Собеля)
    final List<List<double>> edgeStrength = List.generate(th, (_) => List.filled(tw, 0.0));

    for (int y = 5; y < th - 5; y++) {
      for (int x = 5; x < tw - 5; x++) {
        final double lum = smoothLum[y][x];
        // Максимальный светлый фон в радиусе 5 px по 8 направлениям
        double localBg = lum;
        for (int dy = -5; dy <= 5; dy += 5) {
          for (int dx = -5; dx <= 5; dx += 5) {
            if (dx == 0 && dy == 0) continue;
            final v = smoothLum[y + dy][x + dx];
            if (v > localBg) localBg = v;
          }
        }
        final double drop = localBg - lum;
        final double globalDrop = (localPaperLum - lum) * 0.45;
        edgeStrength[y][x] = math.max(drop, globalDrop);
      }
    }

    // 3 попытки от нормальной линии к сверхтонкому карандашу
    final List<double> thresholds = [6.5, 4.6, 3.3];
    final List<int> dilateRadii = [1, 1, 2];

    for (int pass = 0; pass < thresholds.length; pass++) {
      final result = _tryFloodHandDrawn(
        edgeStrength: edgeStrength,
        tw: tw,
        th: th,
        startX: startX,
        startY: startY,
        edgeThreshold: thresholds[pass],
        wallRadius: dilateRadii[pass],
        normX: normX,
        normY: normY,
      );
      if (result != null) {
        return result;
      }
    }

    return _fallbackBox(normX, normY);
  }

  static List<Offset>? _tryFloodHandDrawn({
    required List<List<double>> edgeStrength,
    required int tw,
    required int th,
    required int startX,
    required int startY,
    required double edgeThreshold,
    required int wallRadius,
    required double normX,
    required double normY,
  }) {
    final List<List<bool>> thickWall = List.generate(th, (_) => List.filled(tw, false));
    for (int y = 3; y < th - 3; y++) {
      for (int x = 3; x < tw - 3; x++) {
        if (edgeStrength[y][x] > edgeThreshold) {
          for (int dy = -wallRadius; dy <= wallRadius; dy++) {
            for (int dx = -wallRadius; dx <= wallRadius; dx++) {
              if (dx.abs() + dy.abs() <= wallRadius + 1) {
                thickWall[y + dy][x + dx] = true;
              }
            }
          }
        }
      }
    }

    // Очищаем точку старта (на случай тапа прямо на цифру внутри контура)
    for (int dy = -5; dy <= 5; dy++) {
      for (int dx = -5; dx <= 5; dx++) {
        final sx = (startX + dx).clamp(2, tw - 3);
        final sy = (startY + dy).clamp(2, th - 3);
        thickWall[sy][sx] = false;
      }
    }

    final List<List<bool>> filled = List.generate(th, (_) => List.filled(tw, false));
    final List<math.Point<int>> queue = [math.Point(startX, startY)];
    filled[startY][startX] = true;

    int minX = startX, maxX = startX, minY = startY, maxY = startY;
    int count = 0;
    final int maxAllowedPixels = (tw * th * 0.25).toInt();

    const dirsX = [1, -1, 0, 0];
    const dirsY = [0, 0, 1, -1];

    while (queue.isNotEmpty) {
      final curr = queue.removeLast();
      count++;
      if (count > maxAllowedPixels) {
        return null; // Протечка наружу — переходим к следующему более строгому проходу
      }

      if (curr.x < minX) minX = curr.x;
      if (curr.x > maxX) maxX = curr.x;
      if (curr.y < minY) minY = curr.y;
      if (curr.y > maxY) maxY = curr.y;

      for (int i = 0; i < 4; i++) {
        final nx = curr.x + dirsX[i];
        final ny = curr.y + dirsY[i];
        if (nx <= 3 || nx >= tw - 4 || ny <= 3 || ny >= th - 4) continue;
        if (!filled[ny][nx] && !thickWall[ny][nx]) {
          filled[ny][nx] = true;
          queue.add(math.Point(nx, ny));
        }
      }
    }

    if (count < 45) return null;

    // Заполняем все внутренние "острова" (цифры и пометки внутри контура)
    final int bx0 = math.max(2, minX - 5);
    final int by0 = math.max(2, minY - 5);
    final int bx1 = math.min(tw - 3, maxX + 5);
    final int by1 = math.min(th - 3, maxY + 5);

    final List<List<bool>> outside = List.generate(th, (_) => List.filled(tw, false));
    final List<math.Point<int>> outQ = [math.Point(bx0, by0)];
    outside[by0][bx0] = true;

    while (outQ.isNotEmpty) {
      final c = outQ.removeLast();
      for (int i = 0; i < 4; i++) {
        final nx = c.x + dirsX[i];
        final ny = c.y + dirsY[i];
        if (nx < bx0 || nx > bx1 || ny < by0 || ny > by1) continue;
        if (!outside[ny][nx] && !filled[ny][nx]) {
          outside[ny][nx] = true;
          outQ.add(math.Point(nx, ny));
        }
      }
    }

    // Точная компенсация толщины стенки (крест +-1 px + диагональ), чтобы лечь ровно по оси карандаша
    final List<List<bool>> solidMask = List.generate(th, (_) => List.filled(tw, false));
    final int compRadius = wallRadius;
    for (int y = by0; y <= by1; y++) {
      for (int x = bx0; x <= bx1; x++) {
        if (!outside[y][x]) {
          for (int dy = -compRadius; dy <= compRadius; dy++) {
            for (int dx = -compRadius; dx <= compRadius; dx++) {
              if (dx.abs() + dy.abs() <= compRadius + 1) {
                final py = (y + dy).clamp(1, th - 2);
                final px = (x + dx).clamp(1, tw - 2);
                solidMask[py][px] = true;
              }
            }
          }
        }
      }
    }

    return _traceAndSmoothMask(solidMask, tw, th, bx0, by0, bx1, by1, normX, normY, isHandDrawn: true);
  }

  static List<Offset> _traceAndSmoothMask(
    List<List<bool>> mask,
    int tw,
    int th,
    int minX,
    int minY,
    int maxX,
    int maxY,
    double normX,
    double normY, {
    required bool isHandDrawn,
  }) {
    final int bx0 = math.max(3, minX - 4);
    final int by0 = math.max(3, minY - 4);
    final int bx1 = math.min(tw - 4, maxX + 4);
    final int by1 = math.min(th - 4, maxY + 4);

    final List<List<bool>> closed = List.generate(th, (_) => List.filled(tw, false));
    for (int y = by0; y <= by1; y++) {
      for (int x = bx0; x <= bx1; x++) {
        int count = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (mask[y + dy][x + dx]) count++;
          }
        }
        closed[y][x] = count >= 4;
      }
    }

    math.Point<int>? firstEdge;
    for (int y = by0; y <= by1 && firstEdge == null; y++) {
      for (int x = bx0; x <= bx1; x++) {
        if (closed[y][x]) {
          firstEdge = math.Point(x, y);
          break;
        }
      }
    }

    if (firstEdge == null) return _fallbackBox(normX, normY);

    const mooreDx = [-1, 0, 1, 1, 1, 0, -1, -1];
    const mooreDy = [-1, -1, -1, 0, 1, 1, 1, 0];

    final List<Offset> rawContour = [];
    math.Point<int> current = firstEdge;
    int backtrackDir = 0;

    for (int step = 0; step < 9000; step++) {
      rawContour.add(Offset(current.x.toDouble(), current.y.toDouble()));
      bool foundNext = false;

      for (int i = 0; i < 8; i++) {
        final int dir = (backtrackDir + i) % 8;
        final int nx = current.x + mooreDx[dir];
        final int ny = current.y + mooreDy[dir];

        if (nx >= 0 && nx < tw && ny >= 0 && ny < th && closed[ny][nx]) {
          current = math.Point(nx, ny);
          backtrackDir = (dir + 5) % 8;
          foundNext = true;
          break;
        }
      }

      if (!foundNext || (current == firstEdge && rawContour.length > 6)) {
        break;
      }
    }

    if (rawContour.length < 6) return _fallbackBox(normX, normY);

    final simplified = _rdpSimplify(rawContour, isHandDrawn ? 2.5 : 3.2);
    if (simplified.length < 4) return _fallbackBox(normX, normY);

    final smoothed = _chaikinSmooth(simplified);
    return smoothed.map((p) => Offset(p.dx / tw, p.dy / th)).toList();
  }

  static List<Offset> _chaikinSmooth(List<Offset> pts) {
    if (pts.length < 4) return pts;
    final List<Offset> out = [];
    for (int i = 0; i < pts.length; i++) {
      final p0 = pts[i];
      final p1 = pts[(i + 1) % pts.length];
      out.add(Offset(0.75 * p0.dx + 0.25 * p1.dx, 0.75 * p0.dy + 0.25 * p1.dy));
      out.add(Offset(0.25 * p0.dx + 0.75 * p1.dx, 0.25 * p0.dy + 0.75 * p1.dy));
    }
    return out;
  }

  static List<Offset> _rdpSimplify(List<Offset> points, double epsilon) {
    if (points.length < 3) return points;
    double maxDist = 0.0;
    int index = 0;
    final end = points.length - 1;

    for (int i = 1; i < end; i++) {
      final d = _perpendicularDistance(points[i], points[0], points[end]);
      if (d > maxDist) {
        index = i;
        maxDist = d;
      }
    }

    if (maxDist > epsilon) {
      final left = _rdpSimplify(points.sublist(0, index + 1), epsilon);
      final right = _rdpSimplify(points.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [points[0], points[end]];
    }
  }

  static double _perpendicularDistance(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final mag = math.sqrt(dx * dx + dy * dy);
    if (mag < 1e-9) return (p - a).distance;
    return ((p.dx - a.dx) * dy - (p.dy - a.dy) * dx).abs() / mag;
  }

  static List<Offset> _fallbackBox(double normX, double normY) {
    const double r = 0.04;
    return [
      Offset(normX - r, normY - r),
      Offset(normX + r, normY - r),
      Offset(normX + r, normY + r),
      Offset(normX - r, normY + r),
    ];
  }
}
