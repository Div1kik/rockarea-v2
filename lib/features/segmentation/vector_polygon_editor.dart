import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/archive_service.dart';
import '../../core/contour_detector.dart';
import '../../core/polygon_math.dart';

class VectorPolygonEditor extends StatefulWidget {
  final String imagePath;
  const VectorPolygonEditor({super.key, required this.imagePath});

  @override
  State<VectorPolygonEditor> createState() => _VectorPolygonEditorState();
}

class _VectorPolygonEditorState extends State<VectorPolygonEditor> {
  final List<SamplePolygon> _polygons = [];
  int _activePolygonIndex = -1;
  int _activePointIndex = -1;
  Offset? _dragPosition;

  img.Image? _decodedImage;
  bool _isProcessing = false;

  final double _pixelsPerCm2 = 1400.0;
  static const double _hitRadius = 48.0;
  static const double _nodeRadius = 7.5;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (mounted) {
      setState(() {
        _decodedImage = decoded;
      });
    }
  }

  void _onTapDown(TapDownDetails details, Size canvasSize) {
    final touch = details.localPosition;

    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];
      final hitIndex = PolygonMath.findNearestPoint(touch, poly.points, _hitRadius);
      if (hitIndex != -1) {
        setState(() {
          _activePointIndex = hitIndex;
          _dragPosition = touch;
        });
        return;
      }
    }

    for (int i = _polygons.length - 1; i >= 0; i--) {
      if (PolygonMath.isPointInside(touch, _polygons[i].points)) {
        setState(() {
          _activePolygonIndex = i;
          _activePointIndex = -1;
        });
        return;
      }
    }

    if (_decodedImage != null && !_isProcessing) {
      _autoDetectObjectAt(touch, canvasSize);
    }
  }

  void _autoDetectObjectAt(Offset touch, Size canvasSize) {
    setState(() => _isProcessing = true);

    final normX = (touch.dx / canvasSize.width).clamp(0.0, 1.0);
    final normY = (touch.dy / canvasSize.height).clamp(0.0, 1.0);

    final detectedNormPoints = ContourDetector.extractContourAroundPoint(
      image: _decodedImage!,
      normX: normX,
      normY: normY,
    );

    setState(() {
      _isProcessing = false;
      final int nextNum = _polygons.length + 1;

      final points = detectedNormPoints.map((p) {
        return Offset(p.dx * canvasSize.width, p.dy * canvasSize.height);
      }).toList();

      _polygons.add(SamplePolygon(
        id: 'Образец №$nextNum',
        points: points,
      ));
      _activePolygonIndex = _polygons.length - 1;
      _activePointIndex = -1;
    });
  }

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    final touch = details.localPosition;
    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];
      final hitIndex = PolygonMath.findNearestPoint(touch, poly.points, _hitRadius);
      if (hitIndex != -1) {
        setState(() {
          _activePointIndex = hitIndex;
          _dragPosition = touch;
        });
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_activePolygonIndex != -1 && _activePointIndex != -1) {
      final clampedPos = Offset(
        details.localPosition.dx.clamp(0.0, canvasSize.width),
        details.localPosition.dy.clamp(0.0, canvasSize.height),
      );

      setState(() {
        _polygons[_activePolygonIndex].points[_activePointIndex] = clampedPos;
        _dragPosition = clampedPos;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _activePointIndex = -1;
      _dragPosition = null;
    });
  }

  void _editSampleName(int index) {
    final controller = TextEditingController(text: _polygons[index].id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Шифр образца', style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF0F172A)),
          decoration: const InputDecoration(
            hintText: 'Например: Керн 12-А',
            hintStyle: TextStyle(color: Color(0xFF94A3B8)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF97316))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEA580C), width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF97316), foregroundColor: Colors.white),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _polygons[index].id = controller.text.trim();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToArchive() async {
    if (_polygons.isEmpty) return;

    double totalArea = 0.0;
    final List<SampleItem> samples = [];

    for (final p in _polygons) {
      final px = PolygonMath.computeShoelaceArea(p.points);
      final cm2 = px / _pixelsPerCm2;
      totalArea += cm2;
      samples.add(SampleItem(name: p.id, areaPx: px, areaCm2: cm2));
    }

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final record = TestRecord(
      id: 'Серия #${now.millisecondsSinceEpoch.toString().substring(8)}',
      date: dateStr,
      imagePath: widget.imagePath,
      totalAreaCm2: totalArea,
      samples: samples,
    );

    await ArchiveService.saveRecord(record);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2563EB),
          content: Text('Серия испытаний успешно сохранена в журнал!'),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double imgAspect = (_decodedImage != null && _decodedImage!.height > 0)
        ? _decodedImage!.width / _decodedImage!.height
        : 1.0;

    double totalAreaCm2 = 0.0;
    for (final p in _polygons) {
      final pxArea = PolygonMath.computeShoelaceArea(p.points);
      totalAreaCm2 += (pxArea / _pixelsPerCm2);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Планиметрия керна', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add, color: Color(0xFFF97316)),
            tooltip: 'Сохранить в журнал',
            onPressed: _polygons.isNotEmpty ? _saveToArchive : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
            tooltip: 'Удалить активный объект',
            onPressed: _activePolygonIndex != -1
                ? () => setState(() {
                      _polygons.removeAt(_activePolygonIndex);
                      _activePolygonIndex = _polygons.isNotEmpty ? _polygons.length - 1 : -1;
                      _activePointIndex = -1;
                    })
                : null,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenAspect = constraints.maxWidth / constraints.maxHeight;
          final Size canvasSize = (screenAspect > imgAspect)
              ? Size(constraints.maxHeight * imgAspect, constraints.maxHeight)
              : Size(constraints.maxWidth, constraints.maxWidth / imgAspect);

          return Column(
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Image.file(File(widget.imagePath), fit: BoxFit.fill),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MultiPolygonPainter(
                              polygons: _polygons,
                              activeIndex: _activePolygonIndex,
                              activePointIndex: _activePointIndex,
                              nodeRadius: _nodeRadius,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) => _onTapDown(details, canvasSize),
                            onPanStart: (details) => _onPanStart(details, canvasSize),
                            onPanUpdate: (details) => _onPanUpdate(details, canvasSize),
                            onPanEnd: _onPanEnd,
                          ),
                        ),
                        if (_dragPosition != null && _activePointIndex != -1)
                          Positioned(
                            left: _dragPosition!.dx - 55,
                            top: _dragPosition!.dy - 125,
                            child: RawMagnifier(
                              decoration: const MagnifierDecoration(
                                shape: CircleBorder(
                                  side: BorderSide(color: Color(0xFFF97316), width: 3),
                                ),
                                shadows: [
                                  BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4)),
                                ],
                              ),
                              size: const Size(110, 110),
                              magnificationScale: 2.2,
                              focalPointOffset: const Offset(0, 70),
                            ),
                          ),
                        if (_isProcessing)
                          Container(
                            color: Colors.black26,
                            child: const Center(child: CircularProgressIndicator(color: Color(0xFFF97316))),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                height: 220,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -3))],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ОБЩАЯ ПЛОЩАДЬ СЕРИИ',
                                  style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              Text('${totalAreaCm2.toStringAsFixed(2)} см²',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF97316),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('В журнал', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: _polygons.isNotEmpty ? _saveToArchive : null,
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFFE2E8F0), height: 1),
                    Expanded(
                      child: _polygons.isEmpty
                          ? const Center(
                              child: Text('Коснитесь камня на фото для выделения контура',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                            )
                          : ListView.builder(
                              itemCount: _polygons.length,
                              itemBuilder: (context, idx) {
                                final poly = _polygons[idx];
                                final pxArea = PolygonMath.computeShoelaceArea(poly.points);
                                final cm2Area = pxArea / _pixelsPerCm2;
                                final isSelected = (idx == _activePolygonIndex);

                                return Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFFFF7ED) : Colors.transparent,
                                    border: Border(
                                      left: BorderSide(
                                        color: isSelected ? const Color(0xFFF97316) : Colors.transparent,
                                        width: 4,
                                      ),
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: isSelected ? const Color(0xFFF97316) : const Color(0xFFE2E8F0),
                                      child: Text('${idx + 1}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: isSelected ? Colors.white : const Color(0xFF475569),
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    title: Row(
                                      children: [
                                        Text(poly.id,
                                            style: TextStyle(
                                                color: const Color(0xFF0F172A),
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => _editSampleName(idx),
                                          child: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF94A3B8)),
                                        ),
                                      ],
                                    ),
                                    trailing: Text('${cm2Area.toStringAsFixed(2)} см²',
                                        style: const TextStyle(
                                            fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                    onTap: () => setState(() => _activePolygonIndex = idx),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MultiPolygonPainter extends CustomPainter {
  final List<SamplePolygon> polygons;
  final int activeIndex;
  final int activePointIndex;
  final double nodeRadius;

  _MultiPolygonPainter({
    required this.polygons,
    required this.activeIndex,
    required this.activePointIndex,
    required this.nodeRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int p = 0; p < polygons.length; p++) {
      final poly = polygons[p];
      if (poly.points.length < 3) continue;

      final bool isSelected = (p == activeIndex);

      final fillPaint = Paint()
        ..color = (isSelected ? const Color(0xFFF97316) : const Color(0xFF94A3B8)).withOpacity(0.35)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B)
        ..strokeWidth = isSelected ? 2.5 : 1.5
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(poly.points.first.dx, poly.points.first.dy);
      for (int i = 1; i < poly.points.length; i++) {
        path.lineTo(poly.points[i].dx, poly.points[i].dy);
      }
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      if (isSelected) {
        final nodePaint = Paint()..color = Colors.white;
        final activeNodePaint = Paint()..color = const Color(0xFFF97316);
        final borderPaint = Paint()
          ..color = const Color(0xFF2563EB)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        for (int i = 0; i < poly.points.length; i++) {
          final isNodeActive = (i == activePointIndex);
          canvas.drawCircle(poly.points[i], isNodeActive ? nodeRadius * 1.5 : nodeRadius, isNodeActive ? activeNodePaint : nodePaint);
          canvas.drawCircle(poly.points[i], isNodeActive ? nodeRadius * 1.5 : nodeRadius, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiPolygonPainter oldDelegate) => true;
}
