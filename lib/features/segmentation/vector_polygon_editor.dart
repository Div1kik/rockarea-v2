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
  Offset? _currentTouch;

  img.Image? _decodedImage;
  bool _isProcessing = false;

  final double _pixelsPerCm2 = 1400.0;
  static const double _hitRadius = 44.0;
  static const double _nodeRadius = 7.0;

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

  void _handleTapOrDragStart(Offset touch, BoxConstraints constraints, double imgAspect) {
    final canvasSize = _calculateFittedImageSize(constraints, imgAspect);
    final dxOffset = (constraints.maxWidth - canvasSize.width) / 2;
    final dyOffset = (constraints.maxHeight - canvasSize.height) / 2;

    final localX = touch.dx - dxOffset;
    final localY = touch.dy - dyOffset;
    final localTouch = Offset(localX, localY);

    if (localX < 0 || localX > canvasSize.width || localY < 0 || localY > canvasSize.height) {
      return;
    }

    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];
      final hitIndex = PolygonMath.findNearestPoint(localTouch, poly.points, _hitRadius);
      if (hitIndex != -1) {
        setState(() {
          _activePointIndex = hitIndex;
          _currentTouch = touch;
        });
        return;
      }
    }

    for (int i = _polygons.length - 1; i >= 0; i--) {
      if (PolygonMath.isPointInside(localTouch, _polygons[i].points)) {
        setState(() {
          _activePolygonIndex = i;
          _activePointIndex = -1;
        });
        return;
      }
    }

    if (_decodedImage != null && !_isProcessing) {
      _autoDetectObjectAt(localTouch, canvasSize);
    }
  }

  Size _calculateFittedImageSize(BoxConstraints constraints, double imgAspect) {
    final screenAspect = constraints.maxWidth / constraints.maxHeight;
    if (screenAspect > imgAspect) {
      return Size(constraints.maxHeight * imgAspect, constraints.maxHeight);
    } else {
      return Size(constraints.maxWidth, constraints.maxWidth / imgAspect);
    }
  }

  void _autoDetectObjectAt(Offset localTouch, Size canvasSize) {
    setState(() => _isProcessing = true);

    final normX = localTouch.dx / canvasSize.width;
    final normY = localTouch.dy / canvasSize.height;

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

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints, double imgAspect) {
    if (_activePolygonIndex != -1 && _activePointIndex != -1) {
      final canvasSize = _calculateFittedImageSize(constraints, imgAspect);
      final dxOffset = (constraints.maxWidth - canvasSize.width) / 2;
      final dyOffset = (constraints.maxHeight - canvasSize.height) / 2;

      final localTouch = Offset(
        (details.localPosition.dx - dxOffset).clamp(0.0, canvasSize.width),
        (details.localPosition.dy - dyOffset).clamp(0.0, canvasSize.height),
      );

      setState(() {
        _polygons[_activePolygonIndex].points[_activePointIndex] = localTouch;
        _currentTouch = details.localPosition;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _activePointIndex = -1;
      _currentTouch = null;
    });
  }

  void _editSampleName(int index) {
    final controller = TextEditingController(text: _polygons[index].id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131C2E),
        title: const Text('Шифр образца', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Например: Керн 12-А',
            hintStyle: TextStyle(color: Color(0xFF64748B)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF10B981))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _polygons[index].id = controller.text.trim();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
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
          backgroundColor: Color(0xFF10B981),
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
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: const Text('Планиметрия керна', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF131C2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add, color: Color(0xFF10B981)),
            tooltip: 'Сохранить в архив',
            onPressed: _polygons.isNotEmpty ? _saveToArchive : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Удалить активный объект',
            onPressed: _activePolygonIndex != -1
                ? () => setState(() {
                      _polygons.removeAt(_activePolygonIndex);
                      _activePolygonIndex = _polygons.isNotEmpty ? _polygons.length - 1 : -1;
                    })
                : null,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = _calculateFittedImageSize(constraints, imgAspect);
          final dxOffset = (constraints.maxWidth - canvasSize.width) / 2;
          final dyOffset = (constraints.maxHeight - canvasSize.height) / 2;

          return Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: SizedBox(
                        width: canvasSize.width,
                        height: canvasSize.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(widget.imagePath), fit: BoxFit.contain),
                            CustomPaint(
                              painter: _MultiPolygonPainter(
                                polygons: _polygons,
                                activeIndex: _activePolygonIndex,
                                activePointIndex: _activePointIndex,
                                nodeRadius: _nodeRadius,
                              ),
                              size: Size.infinite,
                            ),
                          ],
                        ),
                      ),
                    ),

                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _handleTapOrDragStart(details.localPosition, constraints, imgAspect),
                      onPanStart: (details) => _handleTapOrDragStart(details.localPosition, constraints, imgAspect),
                      onPanUpdate: (details) => _onPanUpdate(details, constraints, imgAspect),
                      onPanEnd: _onPanEnd,
                    ),

                    if (_currentTouch != null && _activePointIndex != -1)
                      Positioned(
                        left: (_currentTouch!.dx - 45).clamp(10.0, constraints.maxWidth - 100.0),
                        top: (_currentTouch!.dy - 110).clamp(10.0, constraints.maxHeight - 100.0),
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF10B981), width: 2.5),
                            color: const Color(0xCC000000),
                            boxShadow: const [
                              BoxShadow(color: Color(0x99000000), blurRadius: 8),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.gps_fixed, color: Color(0xFF10B981), size: 30),
                          ),
                        ),
                      ),

                    if (_isProcessing)
                      Container(
                        color: Colors.black45,
                        child: const Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
                      ),
                  ],
                ),
              ),

              Container(
                height: 220,
                decoration: const BoxDecoration(
                  color: Color(0xFF131C2E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ОБЩАЯ ПЛОЩАДЬ СЕРИИ',
                                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                              Text('${totalAreaCm2.toStringAsFixed(2)} см²',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('В архив', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: _polygons.isNotEmpty ? _saveToArchive : null,
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF243048), height: 1),
                    Expanded(
                      child: _polygons.isEmpty
                          ? const Center(
                              child: Text('Тапните по образцу для выделения границы',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            )
                          : ListView.builder(
                              itemCount: _polygons.length,
                              itemBuilder: (context, idx) {
                                final poly = _polygons[idx];
                                final pxArea = PolygonMath.computeShoelaceArea(poly.points);
                                final cm2Area = pxArea / _pixelsPerCm2;
                                final isSelected = (idx == _activePolygonIndex);

                                return Container(
                                  color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
                                  child: ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: isSelected ? const Color(0xFF10B981) : const Color(0xFF334155),
                                      child: Text('${idx + 1}',
                                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                    title: Row(
                                      children: [
                                        Text(poly.id,
                                            style: TextStyle(
                                                color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () => _editSampleName(idx),
                                          child: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF94A3B8)),
                                        ),
                                      ],
                                    ),
                                    trailing: Text('${cm2Area.toStringAsFixed(2)} см²',
                                        style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
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
        ..color = (isSelected ? const Color(0xFF10B981) : const Color(0xFF3B82F6)).withOpacity(0.35)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = isSelected ? const Color(0xFF10B981) : const Color(0xFF3B82F6)
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
        final activeNodePaint = Paint()..color = const Color(0xFFF59E0B);
        final borderPaint = Paint()
          ..color = const Color(0xFF10B981)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        for (int i = 0; i < poly.points.length; i++) {
          final isNodeActive = (i == activePointIndex);
          canvas.drawCircle(poly.points[i], isNodeActive ? nodeRadius * 1.6 : nodeRadius, isNodeActive ? activeNodePaint : nodePaint);
          canvas.drawCircle(poly.points[i], isNodeActive ? nodeRadius * 1.6 : nodeRadius, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiPolygonPainter oldDelegate) => true;
}
