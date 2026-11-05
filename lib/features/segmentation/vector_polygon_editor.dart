import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/a4_detector.dart';
import '../../core/archive_service.dart';
import '../../core/contour_detector.dart';
import '../../core/polygon_math.dart';
import '../strength/strength_calculator_sheet.dart';

class _HistoryItem {
  final List<SamplePolygon> polygons;
  final int activeIndex;
  _HistoryItem({required this.polygons, required this.activeIndex});
}

class VectorPolygonEditor extends StatefulWidget {
  final String imagePath;
  const VectorPolygonEditor({super.key, required this.imagePath});

  @override
  State<VectorPolygonEditor> createState() => _VectorPolygonEditorState();
}

class _VectorPolygonEditorState extends State<VectorPolygonEditor> {
  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _transformController = TransformationController();

  List<SamplePolygon> _polygons = [];
  final List<_HistoryItem> _history = [];
  final Map<int, SampleStrengthData> _strengthDataMap = {};

  int _activePolygonIndex = -1;
  int _activePointIndex = -1;

  bool _isA4CalibMode = false;
  bool _isLassoMode = false;
  bool _isEraserMode = false;
  double _eraserRadius = 24.0;

  final List<Offset> _lassoPoints = [];
  final List<Offset> _eraserStroke = [];

  List<Offset> _a4Corners = [];

  bool _isDraggingWholeObject = false;
  Offset? _lastLocalTouch;
  Offset? _targetNodeLocal;

  img.Image? _decodedImage;
  bool _isProcessing = false;

  double _pixelsPerCm2 = 520.0;
  static const double _edgeHitThreshold = 18.0;

  int _pointerCount = 0;
  bool _isPanningOrZooming = false;
  Offset? _tapDownPosition;

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

  Future<bool> _confirmExit() async {
    if (_polygons.isEmpty) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Прекратить разметку?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('Несохранённые контуры серии будут утеряны. Выйти?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _saveToHistory() {
    final snapshot = _polygons.map((poly) {
      return SamplePolygon(id: poly.id, points: List<Offset>.from(poly.points));
    }).toList();

    _history.add(_HistoryItem(polygons: snapshot, activeIndex: _activePolygonIndex));
    if (_history.length > 25) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      final item = _history.removeLast();
      _polygons = item.polygons;
      _activePolygonIndex = item.activeIndex.clamp(-1, _polygons.length - 1);
      _activePointIndex = -1;
      _isDraggingWholeObject = false;
    });
  }

  void _recalculateScale(Size canvasSize) {
    if (_a4Corners.length < 4) return;
    final screenCorners = _a4Corners.map((p) => Offset(p.dx * canvasSize.width, p.dy * canvasSize.height)).toList();
    final a4PxArea = PolygonMath.computeShoelaceArea(screenCorners);
    if (a4PxArea > 1000) {
      _pixelsPerCm2 = a4PxArea / A4Detector.a4PhysicalAreaCm2;
    }
  }

  Offset? _screenToCanvas(Offset screenPos) {
    final RenderBox? box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final Offset local = box.globalToLocal(screenPos);
    return Offset(local.dx.clamp(0.0, box.size.width), local.dy.clamp(0.0, box.size.height));
  }

  // Обрезка выпирающих лучей ластиком
  void _applyEraserCut() {
    if (_eraserStroke.length < 2 || _activePolygonIndex == -1) return;
    final poly = _polygons[_activePolygonIndex];
    if (poly.points.length < 4) return;

    _saveToHistory();

    // Удаляем из активного контура вершины, попавшие под мазок ластика
    final List<Offset> updated = [];
    for (final pt in poly.points) {
      bool hit = false;
      for (final ePt in _eraserStroke) {
        if ((pt - ePt).distance <= _eraserRadius) {
          hit = true;
          break;
        }
      }
      if (!hit) updated.add(pt);
    }

    if (updated.length >= 3) {
      setState(() {
        poly.points = updated;
      });
    }
  }

  void _showEraserSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Диаметр срезающего ластика', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: _eraserRadius * 2,
                    height: _eraserRadius * 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFDC2626), width: 2),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _eraserRadius,
                min: 10.0,
                max: 60.0,
                activeColor: const Color(0xFFDC2626),
                onChanged: (val) {
                  setSheetState(() => _eraserRadius = val);
                  setState(() => _eraserRadius = val);
                },
              ),
              Text('${_eraserRadius.toStringAsFixed(0)} px', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointerCount++;
    if (_pointerCount >= 2) {
      _isPanningOrZooming = true;
      _activePointIndex = -1;
      _isDraggingWholeObject = false;
      return;
    }

    _isPanningOrZooming = false;
    _tapDownPosition = e.position;
    final localPos = _screenToCanvas(e.position);
    if (localPos == null) return;

    _lastLocalTouch = localPos;
    if (_isA4CalibMode) return;

    if (_isEraserMode) {
      setState(() {
        _eraserStroke.clear();
        _eraserStroke.add(localPos);
      });
      return;
    }

    if (_isLassoMode) {
      _saveToHistory();
      setState(() {
        _lassoPoints.clear();
        _lassoPoints.add(localPos);
        _targetNodeLocal = localPos;
      });
      return;
    }

    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];
      final nodeHit = PolygonMath.findNearestPoint(localPos, poly.points, 24.0);
      if (nodeHit != -1) {
        _saveToHistory();
        setState(() {
          _activePointIndex = nodeHit;
          _targetNodeLocal = poly.points[nodeHit];
          _isDraggingWholeObject = false;
        });
        return;
      }

      final edgeIdx = PolygonMath.findNearestEdgeIndex(localPos, poly.points, _edgeHitThreshold);
      if (edgeIdx != -1) {
        _saveToHistory();
        setState(() {
          poly.points.insert(edgeIdx + 1, localPos);
          _activePointIndex = edgeIdx + 1;
          _targetNodeLocal = localPos;
          _isDraggingWholeObject = false;
        });
        return;
      }

      if (PolygonMath.isPointInside(localPos, poly.points)) {
        _saveToHistory();
        setState(() {
          _isDraggingWholeObject = true;
          _activePointIndex = -1;
        });
        return;
      }
    }

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
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_isPanningOrZooming || _pointerCount > 1) return;
    final localPos = _screenToCanvas(e.position);
    if (localPos == null) return;

    final RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final Size canvasSize = box.size;

    if (_isEraserMode) {
      setState(() {
        _eraserStroke.add(localPos);
      });
      return;
    }

    if (_isLassoMode) {
      setState(() {
        if (_lassoPoints.isEmpty || (_lassoPoints.last - localPos).distance > 4.0) {
          _lassoPoints.add(localPos);
          _targetNodeLocal = localPos; // Активирует лупу во время лассо
        }
      });
      return;
    }

    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];
      if (_activePointIndex != -1 && _activePointIndex < poly.points.length) {
        setState(() {
          poly.points[_activePointIndex] = localPos;
          _targetNodeLocal = localPos;
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

  void _onPointerUp(PointerUpEvent e) {
    _pointerCount = (_pointerCount - 1).clamp(0, 5);

    if (_isEraserMode && _eraserStroke.isNotEmpty) {
      _applyEraserCut();
      setState(() {
        _eraserStroke.clear();
        _isEraserMode = false;
      });
      return;
    }

    if (_isLassoMode && _lassoPoints.length > 5) {
      final int nextNum = _polygons.length + 1;
      setState(() {
        _polygons.add(SamplePolygon(id: 'БАМ 1 $nextNum', points: List<Offset>.from(_lassoPoints)));
        _activePolygonIndex = _polygons.length - 1;
        _lassoPoints.clear();
        _isLassoMode = false;
        _targetNodeLocal = null;
      });
      return;
    }

    if (!_isPanningOrZooming && _pointerCount == 0 && _tapDownPosition != null && !_isA4CalibMode && !_isLassoMode && !_isEraserMode) {
      final double travel = (e.position - _tapDownPosition!).distance;
      if (travel < 10.0 && _activePointIndex == -1 && !_isDraggingWholeObject) {
        final localPos = _screenToCanvas(e.position);
        if (localPos != null && _decodedImage != null && !_isProcessing) {
          final RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
          bool insideExisting = false;
          for (final p in _polygons) {
            if (PolygonMath.isPointInside(localPos, p.points)) {
              insideExisting = true;
              break;
            }
          }
          if (!insideExisting) {
            _autoDetectObjectAt(localPos, box.size);
          }
        }
      }
    }

    if (_pointerCount == 0) {
      setState(() {
        _activePointIndex = -1;
        _isDraggingWholeObject = false;
        _targetNodeLocal = null;
        _lastLocalTouch = null;
        _tapDownPosition = null;
        _isPanningOrZooming = false;
      });
    }
  }

  void _autoDetectObjectAt(Offset touch, Size canvasSize) {
    setState(() => _isProcessing = true);
    _saveToHistory();

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
      final points = detectedNormPoints.map((p) => Offset(p.dx * canvasSize.width, p.dy * canvasSize.height)).toList();

      _polygons.add(SamplePolygon(id: 'БАМ 1 $nextNum', points: points));
      _activePolygonIndex = _polygons.length - 1;
      _activePointIndex = -1;
    });
  }

  void _openStrengthCalculator() {
    final List<SampleStrengthData> items = [];
    for (int i = 0; i < _polygons.length; i++) {
      final p = _polygons[i];
      final area = PolygonMath.computeShoelaceArea(p.points) / _pixelsPerCm2;
      final raw = p.id.split(RegExp(r'\s+'));
      final existing = _strengthDataMap[i];

      items.add(SampleStrengthData(
        part1: existing?.part1 ?? (raw.isNotEmpty ? raw[0] : 'БАМ'),
        part2: existing?.part2 ?? (raw.length > 1 ? raw[1] : '1'),
        part3: existing?.part3 ?? (raw.length > 2 ? raw[2] : '${i + 1}'),
        areaCm2: area,
        loadKn: existing?.loadKn ?? 0.0,
        condition: existing?.condition ?? 'n',
      ));
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StrengthCalculatorSheet(
          title: 'Расчёт нагрузки',
          initialSamples: items,
          onSaved: (updated) {
            for (int i = 0; i < updated.length; i++) {
              _strengthDataMap[i] = updated[i];
              _polygons[i].id = '${updated[i].part1} ${updated[i].part2} ${updated[i].part3}';
            }
            setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _saveToArchive() async {
    if (_polygons.isEmpty) return;

    double totalArea = 0.0;
    final List<SampleItem> samples = [];

    for (int i = 0; i < _polygons.length; i++) {
      final p = _polygons[i];
      final px = PolygonMath.computeShoelaceArea(p.points);
      final cm2 = px / _pixelsPerCm2;
      totalArea += cm2;

      final str = _strengthDataMap[i];
      samples.add(SampleItem(
        name: p.id,
        areaPx: px,
        areaCm2: cm2,
        loadKn: str?.loadKn ?? 0.0,
        condition: str?.condition ?? 'n',
        tensileMpa: str?.tensileStrengthMpa ?? 0.0,
        compMpa: str?.compStrengthMpa ?? 0.0,
      ));
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
        const SnackBar(backgroundColor: Color(0xFF2563EB), content: Text('Серия испытаний сохранена в журнал!')),
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

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _confirmExit();
        if (shouldExit && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Разметка керна', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
            onPressed: () async {
              if (await _confirmExit() && context.mounted) Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo, color: Color(0xFF475569)),
              tooltip: 'Отменить действие',
              onPressed: _history.isNotEmpty ? _undo : null,
            ),
            if (_activePolygonIndex != -1)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                tooltip: 'Удалить активный образец',
                onPressed: () {
                  _saveToHistory();
                  setState(() {
                    _polygons.removeAt(_activePolygonIndex);
                    _strengthDataMap.remove(_activePolygonIndex);
                    _activePolygonIndex = _polygons.isNotEmpty ? _polygons.length - 1 : -1;
                    _activePointIndex = -1;
                  });
                },
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
            final bool isManipulating = _activePointIndex != -1 || _isDraggingWholeObject || _isLassoMode || _isEraserMode;

            return Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 1.0,
                        maxScale: 4.5,
                        panEnabled: !_isA4CalibMode && !isManipulating,
                        scaleEnabled: !_isA4CalibMode && !isManipulating,
                        child: Center(
                          child: SizedBox(
                            key: _canvasKey,
                            width: canvasSize.width,
                            height: canvasSize.height,
                            child: Stack(
                              fit: StackFit.expand,
                              clipBehavior: Clip.none,
                              children: [
                                Image.file(File(widget.imagePath), fit: BoxFit.fill),

                                if (_isA4CalibMode && _a4Corners.length == 4)
                                  CustomPaint(
                                    painter: _A4FrameOnlyPainter(
                                      corners: _a4Corners.map((p) => Offset(p.dx * canvasSize.width, p.dy * canvasSize.height)).toList(),
                                    ),
                                  ),

                                CustomPaint(
                                  painter: _CleanPolygonPainter(
                                    polygons: _polygons,
                                    activeIndex: _activePolygonIndex,
                                    activePointIndex: _activePointIndex,
                                    lassoPoints: _lassoPoints,
                                    eraserStroke: _eraserStroke,
                                    eraserRadius: _eraserRadius,
                                  ),
                                ),

                                if (_isA4CalibMode && _a4Corners.length == 4)
                                  for (int i = 0; i < _a4Corners.length; i++)
                                    Positioned(
                                      left: _a4Corners[i].dx * canvasSize.width - 32,
                                      top: _a4Corners[i].dy * canvasSize.height - 32,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanUpdate: (details) {
                                          setState(() {
                                            final currentX = _a4Corners[i].dx * canvasSize.width + details.delta.dx;
                                            final currentY = _a4Corners[i].dy * canvasSize.height + details.delta.dy;
                                            _a4Corners[i] = Offset(
                                              (currentX / canvasSize.width).clamp(0.0, 1.0),
                                              (currentY / canvasSize.height).clamp(0.0, 1.0),
                                            );
                                            _targetNodeLocal = Offset(currentX, currentY);
                                          });
                                          _recalculateScale(canvasSize);
                                        },
                                        onPanEnd: (_) => setState(() => _targetNodeLocal = null),
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          alignment: Alignment.center,
                                          color: Colors.transparent,
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2563EB),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white, width: 3),
                                              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      if (!_isA4CalibMode)
                        Positioned.fill(
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: _onPointerDown,
                            onPointerMove: _onPointerMove,
                            onPointerUp: _onPointerUp,
                            onPointerCancel: (_) {
                              _pointerCount = 0;
                              setState(() {
                                _activePointIndex = -1;
                                _isDraggingWholeObject = false;
                                _targetNodeLocal = null;
                                _eraserStroke.clear();
                              });
                            },
                          ),
                        ),

                      // Лупа (работает как при перетягивании точек, так и при рисовании Лассо)
                      if (_targetNodeLocal != null && _decodedImage != null)
                        Positioned(
                          top: 14,
                          right: 14,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFF97316), width: 3),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
                            ),
                            child: ClipOval(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  _AccurateHUDMagnifier(
                                    imageFile: File(widget.imagePath),
                                    normX: _targetNodeLocal!.dx / canvasSize.width,
                                    normY: _targetNodeLocal!.dy / canvasSize.height,
                                  ),
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFF97316), shape: BoxShape.circle)),
                                  Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFF97316), width: 1.5))),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Панель инструментов
                      Positioned(
                        bottom: 12,
                        left: 16,
                        right: 16,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    _isA4CalibMode = !_isA4CalibMode;
                                    _isLassoMode = false;
                                    _isEraserMode = false;
                                    _activePointIndex = -1;
                                  }),
                                  icon: Icon(Icons.crop_free, size: 16, color: _isA4CalibMode ? const Color(0xFF2563EB) : const Color(0xFF475569)),
                                  label: Text(_isA4CalibMode ? 'Готово' : 'Калибровка А4',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _isA4CalibMode ? const Color(0xFF2563EB) : const Color(0xFF475569))),
                                ),
                                Container(width: 1, height: 18, color: const Color(0xFFE2E8F0)),
                                IconButton(
                                  icon: Icon(Icons.gesture, size: 18, color: _isLassoMode ? const Color(0xFFF97316) : const Color(0xFF475569)),
                                  tooltip: 'Лассо',
                                  onPressed: () => setState(() {
                                    _isLassoMode = !_isLassoMode;
                                    _isA4CalibMode = false;
                                    _isEraserMode = false;
                                  }),
                                ),
                                Container(width: 1, height: 18, color: const Color(0xFFE2E8F0)),
                                // Ластик (короткий тап — режим срезки луча, долгий тап — выбор размера)
                                GestureDetector(
                                  onLongPress: _showEraserSettings,
                                  child: IconButton(
                                    icon: Icon(Icons.auto_fix_high, size: 18, color: _isEraserMode ? const Color(0xFFDC2626) : const Color(0xFF475569)),
                                    tooltip: 'Ластик (Зажмите для размера)',
                                    onPressed: () => setState(() {
                                      _isEraserMode = !_isEraserMode;
                                      _isLassoMode = false;
                                      _isA4CalibMode = false;
                                    }),
                                  ),
                                ),
                                Container(width: 1, height: 18, color: const Color(0xFFE2E8F0)),
                                TextButton.icon(
                                  onPressed: _polygons.isNotEmpty ? _openStrengthCalculator : null,
                                  icon: const Icon(Icons.calculate_outlined, size: 16, color: Color(0xFF2563EB)),
                                  label: const Text('Расчёт нагрузки', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      if (_isProcessing)
                        Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator(color: Color(0xFFF97316)))),
                    ],
                  ),
                ),

                // Нижний блок со списком
                Container(
                  height: 200,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -3))],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('ПЛОЩАДЬ СЕРИИ', style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                                        child: Text('${_pixelsPerCm2.toStringAsFixed(0)} px/см²', style: const TextStyle(fontSize: 9, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  Text('${totalAreaCm2.toStringAsFixed(2)} см²', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
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
                        child: _polygons.isEmpty
                            ? const Center(child: Text('Коснитесь объекта для авто-сегментации контура', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)))
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
                                      border: Border(left: BorderSide(color: isSelected ? const Color(0xFFF97316) : Colors.transparent, width: 4)),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 11,
                                        backgroundColor: isSelected ? const Color(0xFFF97316) : const Color(0xFFE2E8F0),
                                        child: Text('${idx + 1}', style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.bold)),
                                      ),
                                      title: Text(poly.id, style: TextStyle(color: const Color(0xFF0F172A), fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                                      subtitle: isSelected ? const Text('Тап по контуру — узел. Зажав центр — сдвинуть.', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))) : null,
                                      trailing: Text('${cm2Area.toStringAsFixed(2)} см²', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
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
      ),
    );
  }
}

class _A4FrameOnlyPainter extends CustomPainter {
  final List<Offset> corners;
  _A4FrameOnlyPainter({required this.corners});

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
  }

  @override
  bool shouldRepaint(covariant _A4FrameOnlyPainter oldDelegate) => true;
}

class _CleanPolygonPainter extends CustomPainter {
  final List<SamplePolygon> polygons;
  final int activeIndex;
  final int activePointIndex;
  final List<Offset> lassoPoints;
  final List<Offset> eraserStroke;
  final double eraserRadius;

  _CleanPolygonPainter({
    required this.polygons,
    required this.activeIndex,
    required this.activePointIndex,
    required this.lassoPoints,
    required this.eraserStroke,
    required this.eraserRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Отрисовка траектории ластика
    if (eraserStroke.length > 1) {
      final eraserPaint = Paint()
        ..color = const Color(0xFFDC2626).withOpacity(0.4)
        ..strokeWidth = eraserRadius * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final ePath = Path()..moveTo(eraserStroke.first.dx, eraserStroke.first.dy);
      for (int i = 1; i < eraserStroke.length; i++) {
        ePath.lineTo(eraserStroke[i].dx, eraserStroke[i].dy);
      }
      canvas.drawPath(ePath, eraserPaint);
    }

    if (lassoPoints.length > 1) {
      final lassoPaint = Paint()..color = const Color(0xFFF97316)..strokeWidth = 2.5..style = PaintingStyle.stroke;
      final lPath = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
      for (int i = 1; i < lassoPoints.length; i++) {
        lPath.lineTo(lassoPoints[i].dx, lassoPoints[i].dy);
      }
      canvas.drawPath(lPath, lassoPaint);
    }

    for (int p = 0; p < polygons.length; p++) {
      final poly = polygons[p];
      if (poly.points.length < 3) continue;
      final bool isSelected = (p == activeIndex);

      final fillPaint = Paint()..color = (isSelected ? const Color(0xFFF97316) : const Color(0xFF94A3B8)).withOpacity(0.32)..style = PaintingStyle.fill;
      final strokePaint = Paint()..color = isSelected ? const Color(0xFFF97316) : const Color(0xFF64748B)..strokeWidth = isSelected ? 2.5 : 1.5..style = PaintingStyle.stroke;

      final path = Path()..moveTo(poly.points.first.dx, poly.points.first.dy);
      for (int i = 1; i < poly.points.length; i++) {
        path.lineTo(poly.points[i].dx, poly.points[i].dy);
      }
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      if (isSelected && activePointIndex != -1 && activePointIndex < poly.points.length) {
        final nodePaint = Paint()..color = const Color(0xFFF97316);
        final borderPaint = Paint()..color = Colors.white..strokeWidth = 2.0..style = PaintingStyle.stroke;
        canvas.drawCircle(poly.points[activePointIndex], 7.5, nodePaint);
        canvas.drawCircle(poly.points[activePointIndex], 7.5, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CleanPolygonPainter oldDelegate) => true;
}

class _AccurateHUDMagnifier extends StatelessWidget {
  final File imageFile;
  final double normX;
  final double normY;

  const _AccurateHUDMagnifier({required this.imageFile, required this.normX, required this.normY});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double zoom = 3.5;
        final double mid = constraints.maxWidth / 2;
        return ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translate(mid, mid)
              ..scale(zoom)
              ..translate(-normX * constraints.maxWidth, -normY * constraints.maxHeight),
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Image.file(imageFile, fit: BoxFit.fill, filterQuality: FilterQuality.none),
            ),
          ),
        );
      },
    );
  }
}
