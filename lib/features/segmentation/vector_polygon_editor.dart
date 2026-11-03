import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/polygon_math.dart';

class VectorPolygonEditor extends StatefulWidget {
  final String imagePath;
  const VectorPolygonEditor({super.key, required this.imagePath});

  @override
  State<VectorPolygonEditor> createState() => _VectorPolygonEditorState();
}

class _VectorPolygonEditorState extends State<VectorPolygonEditor> {
  final List<Offset> _points = [];
  int _activePointIndex = -1;
  Offset? _currentTouch;

  static const double _hitRadius = 24.0;
  static const double _nodeRadius = 7.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaultPolygon());
  }

  void _initDefaultPolygon() {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height * 0.45;
    const r = 90.0;

    setState(() {
      _points.clear();
      _points.addAll([
        Offset(cx - r, cy - r),
        Offset(cx + r, cy - r),
        Offset(cx + r, cy + r),
        Offset(cx - r, cy + r),
      ]);
    });
  }

  void _onPanStart(DragStartDetails details) {
    final touch = details.localPosition;
    final hitIndex = PolygonMath.findNearestPoint(touch, _points, _hitRadius);
    if (hitIndex != -1) {
      setState(() {
        _activePointIndex = hitIndex;
        _currentTouch = touch;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activePointIndex != -1) {
      setState(() {
        _points[_activePointIndex] = details.localPosition;
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

  void _onTapUp(TapUpDetails details) {
    final touch = details.localPosition;
    final hitIndex = PolygonMath.findNearestPoint(touch, _points, _hitRadius);
    if (hitIndex == -1) {
      final edgeIndex = PolygonMath.findNearestEdgeIndex(touch, _points, 20.0);
      if (edgeIndex != -1) {
        setState(() {
          _points.insert(edgeIndex + 1, touch);
        });
      }
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final hitIndex = PolygonMath.findNearestPoint(details.localPosition, _points, _hitRadius);
    if (hitIndex != -1 && _points.length > 3) {
      setState(() {
        _points.removeAt(hitIndex);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double pixelArea = PolygonMath.computeShoelaceArea(_points);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: const Text('Разметка контура', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF131C2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Сбросить контур',
            onPressed: _initDefaultPolygon,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.file(
              File(widget.imagePath),
              fit: BoxFit.cover,
            ),
          ),
          GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onTapUp: _onTapUp,
            onLongPressStart: _onLongPressStart,
            child: CustomPaint(
              painter: _PolygonPainter(
                points: _points,
                activeIndex: _activePointIndex,
                nodeRadius: _nodeRadius,
              ),
              size: Size.infinite,
            ),
          ),
          if (_currentTouch != null && _activePointIndex != -1)
            Positioned(
              left: (_currentTouch!.dx - 45).clamp(10, MediaQuery.of(context).size.width - 100),
              top: (_currentTouch!.dy - 120).clamp(10, MediaQuery.of(context).size.height - 100),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF10B981), width: 2.5),
                  color: Colors.black.withOpacity(0.65),
                ),
                child:
