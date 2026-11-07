import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;

class A4Detector {
  static const double a4PhysicalAreaCm2 = 623.7; // 21.0 x 29.7 см

  /// Обнаружение углов белого листа А4 с устойчивостью к теням и фону
  static List<Offset> detectA4Corners(img.Image src) {
    // Масштабируем до удобного разрешения для быстрого и помехоустойчивого анализа
    const int targetWidth = 400;
    final double scale = targetWidth / src.width;
    final int targetHeight = (src.height * scale).toInt();
    final img.Image thumb = img.copyResize(src, width: targetWidth, height: targetHeight);

    // 1. Поиск средней яркости белой бумаги (гистограммный порог)
    final List<int> lums = [];
    for (int y = 0; y < thumb.height; y++) {
      for (int x = 0; x < thumb.width; x++) {
        final pixel = thumb.getPixel(x, y);
        lums.add(img.getLuminance(pixel).toInt());
      }
    }
    lums.sort();
    // Берём 75-й перцентиль яркости как ориентир светлого листа
    final int paperLumThreshold = math.max(140, lums[(lums.length * 0.75).toInt()] - 35);

    // 2. Сбор координат ярких пикселей бумаги
    final List<math.Point<int>> whitePoints = [];
    for (int y = (thumb.height * 0.05).toInt(); y < (thumb.height * 0.95).toInt(); y++) {
      for (int x = (thumb.width * 0.05).toInt(); x < (thumb.width * 0.95).toInt(); x++) {
        final p = thumb.getPixel(x, y);
        if (img.getLuminance(p) >= paperLumThreshold) {
          whitePoints.add(math.Point(x, y));
        }
      }
    }

    if (whitePoints.length < 500) {
      // Запасные координаты с отступами, если лист не удалось выделить контрастом
      return const [
        Offset(0.08, 0.06),
        Offset(0.92, 0.06),
        Offset(0.92, 0.94),
        Offset(0.08, 0.94),
      ];
    }

    // 3. Поиск крайних вершин листа четырёхугольника через проекции
    math.Point<int> tl = whitePoints.first;
    math.Point<int> tr = whitePoints.first;
    math.Point<int> br = whitePoints.first;
    math.Point<int> bl = whitePoints.first;

    int minSum = 999999, maxSum = -999999;
    int minDiff = 999999, maxDiff = -999999;

    for (final pt in whitePoints) {
      final int sum = pt.x + pt.y;
      final int diff = pt.x - pt.y;

      if (sum < minSum) { minSum = sum; tl = pt; }
      if (sum > maxSum) { maxSum = sum; br = pt; }
      if (diff > maxDiff) { maxDiff = diff; tr = pt; }
      if (diff < minDiff) { minDiff = diff; bl = pt; }
    }

    return [
      Offset(tl.x / thumb.width, tl.y / thumb.height),
      Offset(tr.x / thumb.width, tr.y / thumb.height),
      Offset(br.x / thumb.width, br.y / thumb.height),
      Offset(bl.x / thumb.width, bl.y / thumb.height),
    ];
  }
}
