import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Высокоточное сегментирование образца на белом листе А4 с подавлением теней и сглаживанием полигона
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    const int maxDim = 750;
    final double scale = (image.width > image.height)
        ? maxDim / image.width
        : maxDim / image.height;

    final int tw = (image.width * scale).toInt();
    final int th = (image.height * scale).toInt();
    final img.Image thumb = img.copyResize(image, width: tw, height: th, interpolation: img.Interpolation.linear);

    final int startX = (normX * tw).toInt().clamp(1, tw - 2);
    final int startY = (normY * th).toInt().clamp(1, th - 2);

    // 1. Локальная оценка цвета бумаги в кольце вокруг точки касания (радиус 60..140 px)
    // Это спасает при неравномерном освещении листа лампой
    final List<double> paperLums = [];
    final List<double> paperChroma = [];
    for (int dy = -140; dy <= 140; dy += 8) {
      for (int dx = -140; dx <= 140; dx += 8) {
        final distSq = dx * dx + dy * dy;
        if (distSq < 3600 || distSq > 19600) continue;
        final px = startX + dx;
        final py = startY + dy;
        if (px < 2 || px >= tw - 2 || py < 2 || py >= th - 2) continue;

        final p = thumb.getPixel(px, py);
        final lum = img.getLuminance(p).toDouble();
        if (lum > 145) {
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
        ? paperLums[(paperLums.length * 0.70).toInt()]
        : 220.0;
    final double localPaperChroma = paperChroma.isNotEmpty
        ? paperChroma[(paperChroma.length * 0.50).toInt()]
        : 12.0;

    // Цветовой профиль центра образца (точки клика)
    final centerPixel = thumb.getPixel(startX, startY);
    final double centerLum = img.getLuminance(centerPixel).toDouble();
    final double centerChroma = (math.max(centerPixel.r, math.max(centerPixel.g, centerPixel.b)) -
            math.min(centerPixel.r, math.min(centerPixel.g, centerPixel.b)))
        .toDouble();

    // Адаптивный порог: для светлых минералов (кварц/известняк) порог мягче и учитывает цветность
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

      // Подавление мягкой серой тени на бумаге: тень темнее бумаги на 15-30 ед., но почти не имеет цветности,
      // тогда как порода либо заметно темнее, либо имеет цветовой сдвиг относительно белой бумаги
      if (lum < lumThreshold) {
        if (lum > localPaperLum - 38 && (chroma - localPaperChroma).abs() < 6.0 && centerChroma > 12.0) {
          return false; // Отсекаем мягкую тень
        }
        return true;
      }
      if (isLightRock && (chroma - localPaperChroma) > 10.0) {
        return true;
      }
      return false;
    }

    // 2. Построение бинарной маски образца через BFS от точки касания
    final List<List<bool>> mask = List.generate(th, (_) => List.filled(tw, false));
    final List<math.Point<int>> queue = [math.Point(startX, startY)];
    mask[startY][startX] = true;

    int minX = startX, maxX = startX, minY = startY, maxY = startY;
    int pixelCount = 0;

    const dirsX = [1, -1, 0, 0];
    const dirsY = [0, 0, 1, -1];

    while (queue.isNotEmpty && pixelCount < 120000) {
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

    if (pixelCount < 25) {
      return _fallbackBox(normX, normY);
    }

    // 3. Морфологическое закрытие (заполнение мелких бликов/пор внутри скола) в ограничивающем прямоугольнике
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

    // 4. Упорядоченная трассировка внешнего контура (Moore-Neighbor Tracing) — сохраняет вогнутые края
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
    int backtrackDir = 0; // Пришли сверху-слева

    for (int step = 0; step < 8000; step++) {
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

    // 5. Аппроксимация полигона Рамера–Дугласа–Пекера (убирает лесенку пикселей)
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
