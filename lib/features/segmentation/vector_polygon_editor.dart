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

  List<SamplePolygon> _polygons = [];
  final List<List<SamplePolygon>> _history = [];

  int _activePolygonIndex = -1;
  int _activePointIndex = -1;

  bool _isA4CalibMode = false;
  List<Offset> _a4Corners = [];

  bool _isDraggingWholeObject = false;
  Offset? _lastLocalTouch;
  Offset? _currentInspectedPoint;

  img.Image? _decodedImage;
  bool _isProcessing = false;

  double _pixelsPerCm2 = 520.0;
  static const double _edgeHitThreshold = 30.0;

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

  void _saveToHistory() {
    final snapshot = _polygons.map((poly) {
      return SamplePolygon(
        id: poly.id,
        points: List<Offset>.from(poly.points),
      );
    }).toList();
    _history.add(snapshot);
    if (_history.length > 20) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _polygons = _history.removeLast();
      _activePolygonIndex = _polygons.isNotEmpty ? _polygons.length - 1 : -1;
      _activePointIndex = -1;
      _isDraggingWholeObject = false;
    });
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

    final RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final Size canvasSize = box.size;

    _lastLocalTouch = localPos;

    // В режиме калибровки листа жесты отданы маркерам углов
    if (_isA4CalibMode) return;

    // 1. Проверяем касание существующего узла
    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];
      final nodeHit = PolygonMath.findNearestPoint(localPos, poly.points, 28.0);
      if (nodeHit != -1) {
        _saveToHistory();
        setState(() {
          _activePointIndex = nodeHit;
          _currentInspectedPoint = localPos;
          _isDraggingWholeObject = false;
        });
        return;
      }

      // 2. Добавление узла на ребро контура
      final edgeIdx = PolygonMath.findNearestEdgeIndex(localPos, poly.points, _edgeHitThreshold);
      if (edgeIdx != -1) {
        _saveToHistory();
        setState(() {
          poly.points.insert(edgeIdx + 1, localPos);
          _activePointIndex = edgeIdx + 1;
          _currentInspectedPoint = localPos;
          _isDraggingWholeObject = false;
        });
        return;
      }

      // 3. Захват для перемещения всей фигуры
      if (PolygonMath.isPointInside(localPos, poly.points)) {
        _saveToHistory();
        setState(() {
          _isDraggingWholeObject = true;
          _activePointIndex = -1;
        });
        return;
      }
    }

    // 4. Выбор существующего полигона
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

    if (_activePolygonIndex != -1 && _activePolygonIndex < _polygons.length) {
      final poly = _polygons[_activePolygonIndex];

      if (_activePointIndex != -1 && _activePointIndex < poly.points.length) {
        setState(() {
          poly.points[_activePointIndex] = localPos;
          _currentInspectedPoint = localPos;
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

    // Автозахват объекта срабатывает СТРОГО на чистом одиночном тапе (без смещения и без второго пальца)
    if (!_isPanningOrZooming && _pointerCount == 0 && _tapDownPosition != null && !_isA4CalibMode) {
      final double travel = (e.position - _tapDownPosition!).distance;
      if (travel < 10.0 && _activePointIndex == -1 && !_isDraggingWholeObject) {
        final localPos = _screenToCanvas(e.position);
        if (localPos != null && _decodedImage != null && !_isProcessing) {
          final RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
          // Проверяем, не ткнули ли внутрь уже существующего полигона
          bool clickedInsideExisting = false;
          for (final p in _polygons) {
            if (PolygonMath.isPointInside(localPos, p.points)) {
              clickedInsideExisting = true;
              break;
            }
          }
          if (!clickedInsideExisting) {
            _autoDetectObjectAt(localPos, box.size);
          }
        }
      }
    }

    if (_pointerCount == 0) {
      setState(() {
        _activePointIndex = -1;
        _isDraggingWholeObject = false;
        _currentInspectedPoint = null;
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
          IconButton(
            icon: const Icon(Icons.undo, color: Color(0xFF475569)),
            tooltip: 'Отменить действие',
            onPressed: _history.isNotEmpty ? _undo : null,
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _isA4CalibMode = !_isA4CalibMode;
              _activePointIndex = -1;
              _isDraggingWholeObject = false;
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
                ? () {
                    _saveToHistory();
                    setState(() {
                      _polygons.removeAt(_activePolygonIndex);
                      _activePolygonIndex = _polygons.isNotEmpty ? _polygons.length - 1 : -1;
                      _activePointIndex = -1;
                    });
                  }
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

          final bool isManipulatingNode = _activePointIndex != -1 || _isDraggingWholeObject;

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1.0,
                      maxScale: 4.5,
                      panEnabled: !_isA4CalibMode && !isManipulatingNode,
                      scaleEnabled: !_isA4CalibMode && !isManipulatingNode,
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

                              // Рамка А4
                              if (_isA4CalibMode && _a4Corners.length == 4)
                                CustomPaint(
                                  painter: _A4FrameOnlyPainter(
                                    corners: _a4Corners.map((p) => Offset(p.dx * canvasSize.width, p.dy * canvasSize.height)).toList(),
                                  ),
                                ),

                              // Полигоны
                              CustomPaint(
                                painter: _CleanPolygonPainter(
                                  polygons: _polygons,
                                  activeIndex: _activePolygonIndex,
                                  activePointIndex: _activePointIndex,
                                ),
                              ),

                              // Отдельные интерактивные маркеры углов листа А4
                              if (_isA4CalibMode && _a4Corners.length == 4)
                                for (int i = 0; i < _a4Corners.length; i++)
                                  Positioned(
                                    left: _a4Corners[i].dx * canvasSize.width - 24,
                                    top: _a4Corners[i].dy * canvasSize.height - 24,
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
                                          _currentInspectedPoint = Offset(currentX, currentY);
                                        });
                                        _recalculateScale(canvasSize);
                                      },
                                      onPanEnd: (_) => setState(() => _currentInspectedPoint = null),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        alignment: Alignment.center,
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 3),
                                            boxShadow: const [
                                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                            ],
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

                    // Сенсорный слой для добавления узлов и перемещения полигонов
                    if (!_isA4CalibMode)
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _onPointerDown,
                          onPointerMove: _onPointerMove,
                          onPointerUp: _onPointerUp,
                          onPointerCancel: (e) {
                            _pointerCount = 0;
                            setState(() {
                              _activePointIndex = -1;
                              _isDraggingWholeObject = false;
                              _currentInspectedPoint = null;
                            });
                          },
                        ),
                      ),

                    // Чёткая лупа-прицел (HUD) в верхнем правом углу экрана
                    if (_currentInspectedPoint != null && _decodedImage != null)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFF97316), width: 3),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
                            ],
                          ),
                          child: ClipOval(
                            child: Stack(
                              children: [
                                _DirectCropMagnifier(
                                  imageFile: File(widget.imagePath),
                                  normPoint: Offset(
                                    _currentInspectedPoint!.dx / canvasSize.width,
                                    _currentInspectedPoint!.dy / canvasSize.height,
                                  ),
                                ),
                                // Прицельное перекрестие
                                Center(
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFF97316), width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

              // Нижняя сводная панель
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
                                  const Text('Перетяните 4 синих маркера строго по углам листа бумаги на столе.',
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
                                            ? const Text('Тап по контуру — узел. Зажав центр — сдвинуть.',
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

/// Высокоточный рендерер кропа оригинального фото без замыливания
class _DirectCropMagnifier extends StatelessWidget {
  final File imageFile;
  final Offset normPoint;

  const _DirectCropMagnifier({required this.imageFile, required this.normPoint});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double zoom = 2.8;
        final double halfW = constraints.maxWidth / 2;
        final double halfH = constraints.maxHeight / 2;

        return ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translate(halfW, halfH)
              ..scale(zoom)
              ..translate(-normPoint.dx * constraints.maxWidth, -normPoint.dy * constraints.maxHeight),
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
