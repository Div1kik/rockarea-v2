import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;

class A4Detector {
  static const double a4PhysicalAreaCm2 = 623.7; // 21.0 x 29.7 см

  /// Обнаружение 4 углов листа А4 через выделение главной связной области бумаги
  static List<Offset> detectA4Corners(img.Image src) {
    const int targetWidth = 360;
    final double scale = targetWidth / src.width;
    final int targetHeight = (src.height * scale).toInt();
    final img.Image thumb = img.copyResize(src, width: targetWidth, height: targetHeight);

    // 1. Адаптивный порог яркости белого листа
    final List<int> lums = [];
    for (int y = 0; y < thumb.height; y += 2) {
      for (int x = 0; x < thumb.width; x += 2) {
        lums.add(img.getLuminance(thumb.getPixel(x, y)).toInt());
      }
    }
    lums.sort();
    final int paperLumThreshold = math.max(145, lums[(lums.length * 0.72).toInt()] - 28);

    // 2. Поиск самой крупной связной белой области (сам лист А4), игнорируя мелкие блики по углам стола
    final List<List<bool>> visited = List.generate(targetHeight, (_) => List.filled(targetWidth, false));
    List<math.Point<int>> largestComponent = [];

    const dx = [1, -1, 0, 0];
    const dy = [0, 0, 1, -1];

    for (int y = 4; y < targetHeight - 4; y += 3) {
      for (int x = 4; x < targetWidth - 4; x += 3) {
        if (visited[y][x]) continue;
        final lum = img.getLuminance(thumb.getPixel(x, y));
        if (lum < paperLumThreshold) continue;

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
            if (!visited[ny][nx] && img.getLuminance(thumb.getPixel(nx, ny)) >= paperLumThreshold) {
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

    // 3. Поиск 4 углов найденного листа А4
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
