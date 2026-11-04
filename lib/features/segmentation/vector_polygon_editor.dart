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
  static const double _hitRadius = 26.0;
  static const double _nodeRadius = 6.5;

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

  void _onTapDown(TapDownDetails details, BoxConstraints constraints) {
    final touch = details.localPosition;

    for (int i = _polygons.length - 1; i >= 0; i--) {
      if (PolygonMath.isPointInside(touch, _polygons[i].points)) {
        setState(() {
          _activePolygonIndex = i;
        });
        return;
      }
    }

    if (_decodedImage != null && !_isProcessing) {
      _autoDetectObjectAt(touch, constraints);
    }
  }

  void _autoDetectObjectAt(Offset touch, BoxConstraints constraints) {
    setState(() => _isProcessing = true);

    final normX = touch.dx / constraints.maxWidth;
    final normY = touch.dy / constraints.maxHeight;

    final detectedNormPoints = ContourDetector.extractContourAroundPoint(
      image: _decodedImage!,
      normX: normX,
      normY: normY,
    );

    setState(() {
      _isProcessing = false;
      final int nextNum = _polygons.length + 1;

      final screenPoints = detectedNormPoints.map((p) {
        return Offset(p.dx * constraints.maxWidth, p.dy * constraints.maxHeight);
      }).toList();

      _polygons.add(SamplePolygon(
        id: 'Образец №$nextNum',
        points: screenPoints,
      ));
      _activePolygonIndex = _polygons.length - 1;
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (_activePolygonIndex == -1 || _activePolygonIndex >= _polygons.length) return;
    final touch = details.localPosition;
    final poly = _polygons[_activePolygonIndex];
    final hitIndex = PolygonMath.findNearestPoint(touch, poly.points, _hitRadius);

    if (hitIndex != -1) {
      setState(() {
        _activePointIndex = hitIndex;
        _currentTouch = touch;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activePolygonIndex != -1 && _activePointIndex != -1) {
      setState(() {
        _polygons[_activePolygonIndex].points[_activePointIndex] = details.localPosition;
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
    double totalAreaCm2 = 0.0;
    for (final p in _polygons) {
      final pxArea = PolygonMath.computeShoelaceArea(p.points);
      totalAreaCm2 += (pxArea / _pixelsPerCm2);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: const Text('Планиметрия образцов', style: TextStyle(fontSize: 16)),
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
          return Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                      ),
                    ),
                    GestureDetector(
                      onTapDown: (details) => _onTapDown(details, constraints),
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: CustomPaint(
                        painter: _MultiPolygonPainter(
                          polygons: _polygons,
                          activeIndex: _activePolygonIndex,
                          activePointIndex: _activePointIndex,
                          nodeRadius: _nodeRadius,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    if (_isProcessing)
                      Container(
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(color: Color(0xFF10B981)),
                        ),
                      ),
                  ],
                ),
              ),

              // Нижняя таблица серии
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
                              child: Text('Тапните по камню для авто-определения границы',
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
        ..color = (isSelected ? const Color(0xFF10B981) : const Color(0xFF3B82F6)).withOpacity(0.38)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = isSelected ? const Color(0xFF10B981) : const Color(0xFF3B82F6)
        ..strokeWidth = isSelected ? 2.8 : 1.8
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
          canvas.drawCircle(poly.points[i], isNodeActive ? nodeRadius * 1.5 : nodeRadius, isNodeActive ? activeNodePaint : nodePaint);
          canvas.drawCircle(poly.points[i], isNodeActive ? nodeRadius * 1.5 : nodeRadius, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiPolygonPainter oldDelegate) => true;
}
