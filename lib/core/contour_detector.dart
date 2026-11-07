import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Высокоточное сегментирование образца на белом листе А4
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    const int maxDim = 600;
    final double scale = (image.width > image.height)
        ? maxDim / image.width
        : maxDim / image.height;

    final int tw = (image.width * scale).toInt();
    final int th = (image.height * scale).toInt();
    final img.Image thumb = img.copyResize(image, width: tw, height: th);

    final int startX = (normX * tw).toInt().clamp(0, tw - 1);
    final int startY = (normY * th).toInt().clamp(0, th - 1);

    // 1. Оценка яркости белой бумаги вокруг образца (по краям кадра)
    int bgLumSum = 0;
    int bgCount = 0;
    for (int x = 5; x < tw; x += 15) {
      bgLumSum += img.getLuminance(thumb.getPixel(x, 5)).toInt();
      bgLumSum += img.getLuminance(thumb.getPixel(x, th - 6)).toInt();
      bgCount += 2;
    }
    final double avgPaperLum = bgCount > 0 ? bgLumSum / bgCount : 220.0;
    final double objectThreshold = math.max(110.0, avgPaperLum - 35.0);

    // 2. Волновой поиск (BFS) границы образца
    final List<List<bool>> visited = List.generate(th, (_) => List.filled(tw, false));
    final List<math.Point<int>> queue = [math.Point(startX, startY)];
    visited[startY][startX] = true;

    final List<math.Point<int>> boundaryPoints = [];
    int scannedCount = 0;

    const dx = [1, -1, 0, 0, 1, 1, -1, -1];
    const dy = [0, 0, 1, -1, 1, -1, 1, -1];

    while (queue.isNotEmpty && scannedCount < 60000) {
      final curr = queue.removeLast();
      scannedCount++;

      bool isEdge = false;
      for (int i = 0; i < 4; i++) {
        final nx = curr.x + dx[i];
        final ny = curr.y + dy[i];

        if (nx < 0 || nx >= tw || ny < 0 || ny >= th) {
          isEdge = true;
          continue;
        }

        final lum = img.getLuminance(thumb.getPixel(nx, ny));
        // Граница: переход от образца к яркому фону листа А4
        if (lum >= objectThreshold) {
          isEdge = true;
        } else if (!visited[ny][nx]) {
          visited[ny][nx] = true;
          queue.add(math.Point(nx, ny));
        }
      }

      if (isEdge) {
        boundaryPoints.add(curr);
      }
    }

    if (boundaryPoints.length < 10) {
      // Если контраст не обнаружен, формируем компактный начальный полигон вокруг точки клика
      const double r = 0.04;
      return [
        Offset(normX - r, normY - r),
        Offset(normX + r, normY - r),
        Offset(normX + r, normY + r),
        Offset(normX - r, normY + r),
      ];
    }

    // 3. Радиальная фильтрация и сглаживание вершин (лучевой контур по углу)
    final double cx = startX.toDouble();
    final double cy = startY.toDouble();
    const int sectors = 36;
    final List<double> maxDistances = List.filled(sectors, 0.0);
    final List<math.Point<int>?> sectorPoints = List.filled(sectors, null);

    for (final pt in boundaryPoints) {
      final double angle = math.atan2(pt.y - cy, pt.x - cx) + math.pi; // 0..2PI
      final int sector = ((angle / (2 * math.pi)) * sectors).toInt().clamp(0, sectors - 1);
      final double dist = math.sqrt(math.pow(pt.x - cx, 2) + math.pow(pt.y - cy, 2));

      if (dist > maxDistances[sector]) {
        maxDistances[sector] = dist;
        sectorPoints[sector] = pt;
      }
    }

    final List<Offset> normalizedResult = [];
    for (int i = 0; i < sectors; i++) {
      final pt = sectorPoints[i];
      if (pt != null) {
        normalizedResult.add(Offset(pt.x / tw, pt.y / th));
      }
    }

    return normalizedResult.length >= 4
        ? normalizedResult
        : [
            Offset(normX - 0.04, normY - 0.04),
            Offset(normX + 0.04, normY - 0.04),
            Offset(normX + 0.04, normY + 0.04),
            Offset(normX - 0.04, normY + 0.04),
          ];
  }
}
