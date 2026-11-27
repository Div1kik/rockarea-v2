import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;

class A4Detector {
  static const double a4PhysicalAreaCm2 = 623.7; // 21.0 x 29.7 см

  /// Обнаружение 4 углов белого листа А4 с отсечением теплого оттенка деревянного стола
  static List<Offset> detectA4Corners(img.Image src) {
    const int targetWidth = 360;
    final double scale = targetWidth / src.width;
    final int targetHeight = (src.height * scale).toInt();
    final img.Image thumb = img.copyResize(src, width: targetWidth, height: targetHeight);

    bool isPaperPixel(img.Pixel p) {
      final double lum = img.getLuminance(p).toDouble();
      // Белая/серая бумага в тени нейтральна по цвету (R близко к B), а бежевый стол имеет сильный завал в красный/желтый (R - B > 22)
      final double warmTint = (p.r - p.b).toDouble();
      return lum >= 115.0 && warmTint < 20.0;
    }

    // Проверяем, не является ли весь кадр уже обрезанным сканом/фото листа А4
    int brightBorderCount = 0;
    int totalBorderCount = 0;
    for (int x = 0; x < targetWidth; x += 4) {
      if (isPaperPixel(thumb.getPixel(x, 2))) brightBorderCount++;
      if (isPaperPixel(thumb.getPixel(x, targetHeight - 3))) brightBorderCount++;
      totalBorderCount += 2;
    }
    for (int y = 0; y < targetHeight; y += 4) {
      if (isPaperPixel(thumb.getPixel(2, y))) brightBorderCount++;
      if (isPaperPixel(thumb.getPixel(targetWidth - 3, y))) brightBorderCount++;
      totalBorderCount += 2;
    }

    if (totalBorderCount > 0 && (brightBorderCount / totalBorderCount) > 0.80) {
      return const [
        Offset(0.0, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 1.0),
        Offset(0.0, 1.0),
      ];
    }

    final List<List<bool>> visited = List.generate(targetHeight, (_) => List.filled(targetWidth, false));
    List<math.Point<int>> largestComponent = [];

    const dx = [1, -1, 0, 0];
    const dy = [0, 0, 1, -1];

    for (int y = 4; y < targetHeight - 4; y += 3) {
      for (int x = 4; x < targetWidth - 4; x += 3) {
        if (visited[y][x]) continue;
        if (!isPaperPixel(thumb.getPixel(x, y))) continue;

        final List<math.Point<int>> comp = [];
        final List<math.Point<int>> q = [math.Point(x, y)];
        visited[y][x] = true;

        while (q.isNotEmpty) {
          final curr = q.removeLast();
          comp.add(curr);
          for (int i = 0; i < 4; i++) {
            final nx = curr.x + dx[i];
            final ny = curr.y + dy[i];
            if (nx < 2 || nx >= targetWidth - 2 || ny < 2 || ny >= targetHeight - 2) continue;
            if (!visited[ny][nx] && isPaperPixel(thumb.getPixel(nx, ny))) {
              visited[ny][nx] = true;
              q.add(math.Point(nx, ny));
            }
          }
        }

        if (comp.length > largestComponent.length) {
          largestComponent = comp;
        }
      }
    }

    if (largestComponent.length < (targetWidth * targetHeight * 0.12)) {
      return const [
        Offset(0.08, 0.06),
        Offset(0.92, 0.06),
        Offset(0.92, 0.94),
        Offset(0.08, 0.94),
      ];
    }

    math.Point<int> tl = largestComponent.first;
    math.Point<int> tr = largestComponent.first;
    math.Point<int> br = largestComponent.first;
    math.Point<int> bl = largestComponent.first;

    int minSum = 999999, maxSum = -999999;
    int minDiff = 999999, maxDiff = -999999;

    for (final pt in largestComponent) {
      final int sum = pt.x + pt.y;
      final int diff = pt.x - pt.y;

      if (sum < minSum) { minSum = sum; tl = pt; }
      if (sum > maxSum) { maxSum = sum; br = pt; }
      if (diff > maxDiff) { maxDiff = diff; tr = pt; }
      if (diff < minDiff) { minDiff = diff; bl = pt; }
    }

    return [
      Offset(tl.x / targetWidth, tl.y / targetHeight),
      Offset(tr.x / targetWidth, tr.y / targetHeight),
      Offset(br.x / targetWidth, br.y / targetHeight),
      Offset(bl.x / targetWidth, bl.y / targetHeight),
    ];
  }
}
