import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ContourDetector {
  /// Высокоточный детектор: ищет физический край объекта на белом листе А4
  static List<Offset> extractContourAroundPoint({
    required img.Image image,
    required double normX,
    required double normY,
  }) {
    const int maxDim = 500;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image small = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int cx = (normX * small.width).toInt().clamp(0, small.width - 1);
    final int cy = (normY * small.height).toInt().clamp(0, small.height - 1);

    final int w = small.width;
    final int h = small.height;

    // 16 радиальных лучей для детального огибания сложных контуров (плавники, хвосты, сколы)
    const int rayCount = 16;
    final int maxRadius = (math.min(w, h) * 0.45).toInt();
    final int minRadius = math.max(10, (math.min(w, h) * 0.03).toInt());

    // Порог чистого листа бумаги: всё, что светлее 180 по яркости — фон подложки
    const double paperLuminanceThreshold = 182.0;

    final List<double> distances = [];

    for (int i = 0; i < rayCount; i++) {
      final double angle = (2 * math.pi / rayCount) * i;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);

      int stopDist = maxRadius;

      for (int r = minRadius; r < maxRadius; r += 2) {
        final int px = (cx + r * cosA).toInt();
        final int py = (cy + r * sinA).toInt();

        if (px < 0 || px >= w || py < 0 || py >= h) {
          stopDist = r;
          break;
        }

        final pixel = small.getPixel(px, py);
        final double lum = pixel.luminance.toDouble();

        // Проверяем: стал ли пиксель белым фоном бумаги
        // Условие: высокая яркость И низкая насыщенность (белый/серый лист бумаги)
        final double maxChannel = math.max(pixel.r, math.max(pixel.g, pixel.b)).toDouble();
        final double minChannel = math.min(pixel.r, math.min(pixel.g, pixel.b)).toDouble();
        final double sat = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel;

        if (lum > paperLuminanceThreshold && sat < 0.22) {
          stopDist = r;
          break;
        }
      }
      distances.add(stopDist.toDouble());
    }

    // Сглаживание расстояний между соседними лучами (устранение западаний)
    final List<Offset> contour = [];
    for (int i = 0; i < rayCount; i++) {
      final double prev = distances[(i - 1 + rayCount) % rayCount];
      final double curr = distances[i];
      final double next = distances[(i + 1) % rayCount];
      final double smoothedDist = (prev + curr * 2.0 + next) / 4.0;

      final double angle = (2 * math.pi / rayCount) * i;
      final double normPointX = ((cx + smoothedDist * math.cos(angle)) / w).clamp(0.0, 1.0);
      final double normPointY = ((cy + smoothedDist * math.sin(angle)) / h).clamp(0.0, 1.0);
      contour.add(Offset(normPointX, normPointY));
    }

    return contour;
  }
}
