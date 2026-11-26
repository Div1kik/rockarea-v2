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
    const int maxDim = 800;
    final double scale = (image.width > image.height)
        ? maxDim / image.width
        : maxDim / image.height;

    final int tw = (image.width * scale).toInt();
    final int th = (image.height * scale).toInt();
    final img.Image thumb = img.copyResize(image, width: tw, height: th, interpolation: img.Interpolation.linear);

    final int startX = (normX * tw).toInt().clamp(2, tw - 3);
    final int startY = (normY * th).toInt().clamp(2, th - 3);

    // 1. Локальная оценка яркости и цветности бумаги вокруг точки касания
    final List<double> paperLums = [];
    final List<double> paperChroma = [];
    for (int dy = -120; dy <= 120; dy += 8) {
      for (int dx = -120; dx <= 120; dx += 8) {
        final distSq = dx * dx + dy * dy;
        if (distSq < 2500 || distSq > 14400) continue;
        final px = startX + dx;
        final py = startY + dy;
        if (px < 2 || px >= tw - 2 || py < 2 || py >= th - 2) continue;

        final p = thumb.getPixel(px, py);
        final lum = img.getLuminance(p).toDouble();
        if (lum > 110) {
          paperLums.add(lum);
          final maxC = math.max(p.r, math.max(p.g, p.b)).toDouble();
          final minC = math.min(p.r, math.min(p.g, p.b)).toDouble();
          paperChroma.add(maxC - minC);
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

    final centerPixel = thumb.getPixel(startX, startY);
    final double centerLum = img.getLuminance(centerPixel).toDouble();
    final double centerChroma = (math.max(centerPixel.r, math.max(centerPixel.g, centerPixel.b)) -
            math.min(centerPixel.r, math.min(centerPixel.g, centerPixel.b)))
        .toDouble();

    // Определяем режим: под пальцем сама бумага (обведенный ручкой контур) или объемный камень
    final bool isPaperInside = (centerLum - localPaperLum).abs() < 22.0 &&
        (centerChroma - localPaperChroma).abs() < 12.0;

    if (isPaperInside) {
      return _extractHandDrawnContour(
        thumb: thumb,
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
      final p = thumb.getPixel(x, y);
      final double lum = img.getLuminance(p).toDouble();
      final double chroma = (math.max(p.r, math.max(p.g, p.b)) -
              math.min(p.r, math.min(p.g, p.b)))
          .toDouble();

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
        if (nx <= 1 || nx >= tw - 2 || ny <= 1 || ny >= th - 2) continue;
        if (!mask[ny][nx] && isRockPixel(nx, ny)) {
          mask[ny][nx] = true;
          queue.add(math.Point(nx, ny));
        }
      }
    }

    if (pixelCount < 25) return _fallbackBox(normX, normY);
    return _traceAndSimplifyMask(mask, tw, th, minX, minY, maxX, maxY, normX, normY);
  }

  /// Режим 2: Заливка замкнутого контура, обведенного ручкой/карандашом на листе А4
  static List<Offset> _extractHandDrawnContour({
    required img.Image thumb,
    required int tw,
    required int th,
    required int startX,
    required int startY,
    required double localPaperLum,
    required double normX,
    required double normY,
  }) {
    // 1. Строим карту линий чернил/карандаша (локальный контраст против сглаженного фона)
    final List<List<bool>> inkWall = List.generate(th, (_) => List.filled(tw, false));

    for (int y = 2; y < th - 2; y++) {
      for (int x = 2; x < tw - 2; x++) {
        final double lum = img.getLuminance(thumb.getPixel(x, y)).toDouble();
        // Сравниваем с соседними пикселями на расстоянии 4 px (ловит даже тонкую линию карандаша)
        final double lLeft = img.getLuminance(thumb.getPixel(math.max(0, x - 4), y)).toDouble();
        final double lRight = img.getLuminance(thumb.getPixel(math.min(tw - 1, x + 4), y)).toDouble();
        final double lUp = img.getLuminance(thumb.getPixel(x, math.max(0, y - 4))).toDouble();
        final double lDown = img.getLuminance(thumb.getPixel(x, math.min(th - 1, y + 4))).toDouble();

        final double localBg = math.max(math.max(lLeft, lRight), math.max(lUp, lDown));
        if ((localBg - lum) > 16.0 || lum < localPaperLum - 26.0) {
          inkWall[y][x] = true;
        }
      }
    }

    // 2. Утолщаем стенку контура на 1 px (dilation), чтобы закрыть микроразрывы линии ручки
    final List<List<bool>> thickWall = List.generate(th, (_) => List.filled(tw, false));
    for (int y = 2; y < th - 2; y++) {
      for (int x = 2; x < tw - 2; x++) {
        if (inkWall[y][x]) {
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              thickWall[y + dy][x + dx] = true;
            }
          }
        }
      }
    }

    // Очищаем точку старта (если пользователь случайно ткнул прямо в цифру площади внутри контура)
    for (int dy = -4; dy <= 4; dy++) {
      for (int dx = -4; dx <= 4; dx++) {
        final sx = (startX + dx).clamp(1, tw - 2);
        final sy = (startY + dy).clamp(1, th - 2);
        thickWall[sy][sx] = false;
      }
    }

    // 3. Заливка (BFS) от точки касания до границ ручки
    final List<List<bool>> filled = List.generate(th, (_) => List.filled(tw, false));
    final List<math.Point<int>> queue = [math.Point(startX, startY)];
    filled[startY][startX] = true;

    int minX = startX, maxX = startX, minY = startY, maxY = startY;
    int count = 0;
    // Ограничение: один контур не может занимать больше 35% всего листа А4 (защита от утечки наружу)
    final int maxAllowedPixels = (tw * th * 0.35).toInt();

    const dirsX = [1, -1, 0, 0];
    const dirsY = [0, 0, 1, -1];

    while (queue.isNotEmpty) {
      final curr = queue.removeLast();
      count++;
      if (count > maxAllowedPixels) {
        // Контур не замкнут и заливка вытекла на весь лист
        return _fallbackBox(normX, normY);
      }

      if (curr.x < minX) minX = curr.x;
      if (curr.x > maxX) maxX = curr.x;
      if (curr.y < minY) minY = curr.y;
      if (curr.y > maxY) maxY = curr.y;

      for (int i = 0; i < 4; i++) {
        final nx = curr.x + dirsX[i];
        final ny = curr.y + dirsY[i];
        if (nx <= 2 || nx >= tw - 3 || ny <= 2 || ny >= th - 3) continue;
        if (!filled[ny][nx] && !thickWall[ny][nx]) {
          filled[ny][nx] = true;
          queue.add(math.Point(nx, ny));
        }
      }
    }

    if (count < 40) return _fallbackBox(normX, normY);

    // 4. Включаем написанные ручкой цифры внутри контура в общую маску (заливка дырок внутри ограничивающего блока)
    final int bx0 = math.max(1, minX - 2);
    final int by0 = math.max(1, minY - 2);
    final int bx1 = math.min(tw - 2, maxX + 2);
    final int by1 = math.min(th - 2, maxY + 2);

    // Отмечаем внешний фон вокруг ограничивающего прямоугольника, всё что не внешний фон — внутри контура
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

    final List<List<bool>> solidMask = List.generate(th, (_) => List.filled(tw, false));
    for (int y = by0; y <= by1; y++) {
      for (int x = bx0; x <= bx1; x++) {
        if (!outside[y][x]) {
          solidMask[y][x] = true;
        }
      }
    }

    return _traceAndSimplifyMask(solidMask, tw, th, bx0, by0, bx1, by1, normX, normY);
  }

  static List<Offset> _traceAndSimplifyMask(
    List<List<bool>> mask,
    int tw,
    int th,
    int minX,
    int minY,
    int maxX,
    int maxY,
    double normX,
    double normY,
  ) {
    final int bx0 = math.max(1, minX - 2);
    final int by0 = math.max(1, minY - 2);
    final int bx1 = math.min(tw - 2, maxX + 2);
    final int by1 = math.min(th - 2, maxY + 2);

    final List<List<bool>> closed = List.generate(th, (_) => List.filled(tw, false));
    for (int y = by0; y <= by1; y++) {
      for (int x = bx0; x <= bx1; x++) {
        int neighbors = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (mask[y + dy][x + dx]) neighbors++;
          }
        }
        closed[y][x] = neighbors >= 4;
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

    final simplified = _rdpSimplify(rawContour, 1.8);
    if (simplified.length < 4) return _fallbackBox(normX, normY);

    return simplified.map((p) => Offset(p.dx / tw, p.dy / th)).toList();
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
