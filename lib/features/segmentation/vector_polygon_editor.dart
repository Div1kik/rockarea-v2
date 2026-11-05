import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/a4_detector.dart';
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
  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _transformController = TransformationController();
  final List<SamplePolygon> _polygons = [];

  int _activePolygonIndex = -1;
  int _activePointIndex = -1;

  bool _isA4CalibMode = false;
  List<Offset> _a4Corners = [];
  int _activeA4CornerIndex = -1;

  bool _isDraggingWholeObject = false;
  Offset? _lastLocalTouch;
  Offset? _magnifierScreenPos;

  img.Image? _decodedImage;
  bool _isProcessing = false;

  double _pixelsPerCm2 = 520.0;
  static const double _edgeHitThreshold = 28.0;
  static const double _a4CornerHitRadius = 55.0;

  @override
  void initState() {
    super.initState();
    _loadImageAndCalibrate();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadImageAndCalibrate() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (mounted && decoded != null) {
      final detectedCorners = A4Detector.detectA4Corners(decoded);
      setState(() {
        _decodedImage = decoded;
        _a4Corners = detectedCorners;
      });
    }
  }

  void _recalculateScale(Size canvasSize) {
    if (_a4Corners.length < 4) return;
    final screenCorners = _a4Corners.map((p) {
      return Offset(p.dx * canvasSize.width, p.dy * canvasSize.height);
    }).toList();

    final a4PxArea = PolygonMath.computeShoelaceArea(screenCorners);
    if (a4PxArea > 1000) {
      _pixelsPerCm2 = a4PxArea / A4Detector.a4PhysicalAreaCm2;
    }
  }

  Offset? _screenToCanvas(Offset screenPos) {
    final RenderBox? box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final Offset local = box.globalToLocal(screenPos);
    return Offset(
      local.dx.clamp(0.0, box.size.width),
      local.dy.clamp(0.0, box.size.height),
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    final localPos = _screenToCanvas(e.position);
    if (localPos == null) return;

    final RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final Size canvasSize = box.size;

    _lastLocalTouch = localPos;
    _magnifierScreenPos = e.position;

    // 1. Калибровка А4: захват угла
    if (_isA4CalibMode && _a4Corners.length == 4) {
      for (int i = 0; i < _a4Corners.length; i++) {
        final cornerPos = Offset(_a4Corners[i].dx * canvasSize.width, _a4Corners[i].dy * canvasSize.height);
        if ((cornerPos - localPos).distance <= _a4CornerHitRadius) {
          setState(() {
            _activeA4CornerIndex = i;
          });
          return;
        }
      }
      return;
    }

    // 2. Создание узла на отрезке активного контура
    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];
      final edgeIdx = PolygonMath.findNearestEdgeIndex(localPos, poly.points, _edgeHitThreshold);

      if (edgeIdx != -1) {
        setState(() {
          poly.points.insert(edgeIdx + 1, localPos);
          _activePointIndex = edgeIdx + 1;
          _isDraggingWholeObject = false;
        });
        return;
      }

      // Захват узла
      final nodeHit = PolygonMath.findNearestPoint(localPos, poly.points, 28.0);
      if (nodeHit != -1) {
        setState(() {
          _activePointIndex = nodeHit;
          _isDraggingWholeObject = false;
        });
        return;
      }

      // Перемещение фигуры
      if (PolygonMath.isPointInside(localPos, poly.points)) {
        setState(() {
          _isDraggingWholeObject = true;
          _activePointIndex = -1;
        });
        return;
      }
    }

    // 3. Выбор полигона
    for (int i = _polygons.length - 1; i >= 0; i--) {
      if (PolygonMath.isPointInside(localPos, _polygons[i].points)) {
        setState(() {
          _activePolygonIndex = i;
          _activePointIndex = -1;
          _isDraggingWholeObject = true;
        });
        return;
      }
    }

    // 4. Автозахват объекта
    if (_decodedImage != null && !_isProcessing) {
      _autoDetectObjectAt(localPos, canvasSize);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final localPos = _screenToCanvas(e.position);
    if (localPos == null) return;

    final RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final Size canvasSize = box.size;
    _magnifierScreenPos = e.position;

    // Перемещение маркера А4
    if (_isA4CalibMode && _activeA4CornerIndex != -1) {
      setState(() {
        _a4Corners[_activeA4CornerIndex] = Offset(
          (localPos.dx / canvasSize.width).clamp(0.0, 1.0),
          (localPos.dy / canvasSize.height).clamp(0.0, 1.0),
        );
      });
      _recalculateScale(canvasSize);
      return;
    }

    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];

      if (_activePointIndex != -1 && _activePointIndex < poly.points.length) {
        setState(() {
          poly.points[_activePointIndex] = localPos;
        });
      } else if (_isDraggingWholeObject && _lastLocalTouch != null) {
        final delta = localPos - _lastLocalTouch!;
        setState(() {
          for (int i = 0; i < poly.points.length; i++) {
            poly.points[i] = Offset(
              (poly.points[i].dx + delta.dx).clamp(0.0, canvasSize.width),
              (poly.points[i].dy + delta.dy).clamp(0.0, canvasSize.height),
            );
          }
        });
      }
    }
    _lastLocalTouch = localPos;
  }

  void _handlePointerEnd() {
    setState(() {
      _activePointIndex = -1;
      _activeA4CornerIndex = -1;
      _isDraggingWholeObject = false;
      _magnifierScreenPos = null;
      _lastLocalTouch = null;
    });
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
          TextButton.icon(
            onPressed: () => setState(() {
              _isA4CalibMode = !_isA4CalibMode;
              _activePointIndex = -1;
            }),
            icon: Icon(Icons.crop_free, size: 18, color: _isA4CalibMode ? const Color(0xFF2563EB) : const Color(0xFF64748B)),
            label: Text(
              _isA4CalibMode ? 'А4 (Вкл)' : 'Калибровка А4',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _isA4CalibMode ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
            ),
          ),
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

          _recalculateScale(canvasSize);

          final bool isManipulating = _activePointIndex != -1 || _activeA4CornerIndex != -1 || _isDraggingWholeObject;

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1.0,
                      maxScale: 4.5,
                      panEnabled: !isManipulating,
                      scaleEnabled: !isManipulating,
                      child: Center(
                        child: SizedBox(
                          key: _canvasKey,
                          width: canvasSize.width,
                          height: canvasSize.height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(widget.imagePath), fit: BoxFit.fill),

                              if (_isA4CalibMode && _a4Corners.length == 4)
                                CustomPaint(
                                  painter: _A4CalibPainter(
                                    corners: _a4Corners.map((p) => Offset(p.dx * canvasSize.width, p.dy * canvasSize.height)).toList(),
                                    activeCornerIndex: _activeA4CornerIndex,
                                  ),
                                ),

                              CustomPaint(
                                painter: _CleanPolygonPainter(
                                  polygons: _polygons,
                                  activeIndex: _activePolygonIndex,
                                  activePointIndex: _activePointIndex,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: (_) => _handlePointerEnd(),
                        onPointerCancel: (_) => _handlePointerEnd(),
                      ),
                    ),

                    if (_magnifierScreenPos != null && (_activePointIndex != -1 || _activeA4CornerIndex != -1))
                      Positioned(
                        left: (_magnifierScreenPos!.dx - 55).clamp(10.0, constraints.maxWidth - 120.0),
                        top: (_magnifierScreenPos!.dy - 145).clamp(10.0, constraints.maxHeight - 120.0),
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
                          focalPointOffset: const Offset(0, 90),
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

              // Нижняя панель
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('ОБЩАЯ ПЛОЩАДЬ СЕРИИ',
                                        style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('${_pixelsPerCm2.toStringAsFixed(0)} px/см²',
                                          style: const TextStyle(fontSize: 9, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                Text('${totalAreaCm2.toStringAsFixed(2)} см²',
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF97316),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('В журнал', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: _polygons.isNotEmpty ? _saveToArchive : null,
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFFE2E8F0), height: 1),
                    Expanded(
                      child: _isA4CalibMode
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Режим калибровки А4',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                  const SizedBox(height: 4),
                                  const Text('Подтяните 4 синих маркера по углам листа бумаги на столе.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    ),
                                    onPressed: () => setState(() => _isA4CalibMode = false),
                                    child: const Text('Готово к разметке', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            )
                          : _polygons.isEmpty
                              ? const Center(
                                  child: Text('Коснитесь объекта для авто-сегментации контура',
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
                                        subtitle: isSelected
                                            ? const Text('Тап по линии — создать узел. Зажав центр — сдвинуть.',
                                                style: TextStyle(fontSize: 10, color: Color(0xFF64748B)))
                                            : null,
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

class _A4CalibPainter extends CustomPainter {
  final List<Offset> corners;
  final int activeCornerIndex;

  _A4CalibPainter({required this.corners, required this.activeCornerIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;

    final framePaint = Paint()
      ..color = const Color(0xFF2563EB).withOpacity(0.85)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(path, framePaint);

    final cornerPaint = Paint()..color = const Color(0xFF2563EB);
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < corners.length; i++) {
      final isSelected = (i == activeCornerIndex);
      final r = isSelected ? 12.0 : 8.5;
      canvas.drawCircle(corners[i], r, cornerPaint);
      canvas.drawCircle(corners[i], r, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _A4CalibPainter oldDelegate) => true;
}

class _CleanPolygonPainter extends CustomPainter {
  final List<SamplePolygon> polygons;
  final int activeIndex;
  final int activePointIndex;

  _CleanPolygonPainter({
    required this.polygons,
    required this.activeIndex,
    required this.activePointIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int p = 0; p < polygons.length; p++) {
      final poly = polygons[p];
      if (poly.points.length < 3) continue;

      final bool isSelected = (p == activeIndex);

      final fillPaint = Paint()
        ..color = (isSelected ? const Color(0xFFF97316) : const Color(0xFF94A3B8)).withOpacity(0.32)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = isSelected ? const Color(0xFFF97316) : const Color(0xFF64748B)
        ..strokeWidth = isSelected ? 2.5 : 1.5
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(poly.points.first.dx, poly.points.first.dy);
      for (int i = 1; i < poly.points.length; i++) {
        path.lineTo(poly.points[i].dx, poly.points[i].dy);
      }
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      if (isSelected && activePointIndex != -1 && activePointIndex < poly.points.length) {
        final nodePaint = Paint()..color = const Color(0xFFF97316);
        final borderPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        canvas.drawCircle(poly.points[activePointIndex], 8.0, nodePaint);
        canvas.drawCircle(poly.points[activePointIndex], 8.0, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CleanPolygonPainter oldDelegate) => true;
}
