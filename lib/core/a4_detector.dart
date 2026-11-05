import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class A4Detector {
  static const double a4PhysicalAreaCm2 = 623.7;

  /// Начальная посадка рамки листа А4: по центру листа бумаги с отступами
  static List<Offset> detectA4Corners(img.Image image) {
    const int maxDim = 320;
    final double scale = (math.max(image.width, image.height) > maxDim)
        ? maxDim / math.max(image.width, image.height)
        : 1.0;

    final img.Image small = (scale < 1.0)
        ? img.copyResize(image, width: (image.width * scale).toInt(), height: (image.height * scale).toInt())
        : image;

    final int w = small.width;
    final int h = small.height;

    int minX = w, maxX = 0, minY = h, maxY = 0;
    int whiteCount = 0;

    for (int y = (h * 0.05).toInt(); y < (h * 0.95).toInt(); y += 2) {
      for (int x = (w * 0.05).toInt(); x < (w * 0.95).toInt(); x += 2) {
        if (small.getPixel(x, y).luminance > 180) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          whiteCount++;
        }
      }
    }

    if (whiteCount > (w * h * 0.15) && (maxX - minX) > (w * 0.35) && (maxY - minY) > (h * 0.25)) {
      return [
        Offset(minX / w, minY / h),
        Offset(maxX / w, minY / h),
        Offset(maxX / w, maxY / h),
        Offset(minX / w, maxY / h),
      ];
    }

    // Надежная стартовая рамка по центру горизонтального листа
    return const [
      Offset(0.10, 0.22),
      Offset(0.90, 0.22),
      Offset(0.90, 0.78),
      Offset(0.10, 0.78),
    ];
  }
}
