import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'features/archive/archive_screen.dart';
import 'features/segmentation/vector_polygon_editor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RockAreaApp());
}

class RockAreaApp extends StatelessWidget {
  const RockAreaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RockArea',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          secondary: const Color(0xFFF97316),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0.5,
          iconTheme: IconThemeData(color: Color(0xFF0F172A)),
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 95,
      );

      if (file != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VectorPolygonEditor(imagePath: file.path),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text('Ошибка при выборе изображения: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('ROCKAREA'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined, color: Color(0xFF2563EB)),
            tooltip: 'Журнал испытаний (Архив)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ArchiveScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const RockAreaLogo(size: 150),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 22),
                  label: const Text(
                    'Сделать фото керна',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: const Text(
                    'Выбрать из галереи',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ArchiveScreen()),
                  );
                },
                icon: const Icon(Icons.history, size: 18, color: Color(0xFF64748B)),
                label: const Text(
                  'Открыть журнал испытаний',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RockAreaLogo extends StatelessWidget {
  final double size;
  const RockAreaLogo({super.key, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _RockAreaLogoPainter(),
        ),
        const SizedBox(height: 12),
        const Text(
          'ROCKAREA',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'GEOMECHANICS & PLANIMETRY',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.bold,
            fontSize: 8,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _RockAreaLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;

    final bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.22),
    );
    canvas.drawRRect(bgRRect, Paint()..color = const Color(0xFF0F172A));

    final gridPaint = Paint()
      ..color = const Color(0xFF334155).withOpacity(0.35)
      ..strokeWidth = 1.0;

    for (double i = 0.25; i <= 0.75; i += 0.25) {
      canvas.drawLine(Offset(s * 0.18, s * i), Offset(s * 0.82, s * i), gridPaint);
      canvas.drawLine(Offset(s * i, s * 0.18), Offset(s * i, s * 0.82), gridPaint);
    }

    final pTop = Offset(s * 0.50, s * 0.19);
    final pLeft = Offset(s * 0.28, s * 0.33);
    final pRight = Offset(s * 0.72, s * 0.33);
    final pMidL = Offset(s * 0.36, s * 0.51);
    final pMidR = Offset(s * 0.64, s * 0.51);
    final pCenter = Offset(s * 0.50, s * 0.43);
    final pBottom = Offset(s * 0.50, s * 0.67);

    void drawFacet(List<Offset> points, Color color) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    drawFacet([pTop, pLeft, pMidL, pCenter], const Color(0xFF2563EB));
    drawFacet([pTop, pRight, pMidR, pCenter], const Color(0xFF60A5FA));
    drawFacet([pLeft, pMidL, pBottom], const Color(0xFF1D4ED8));
    drawFacet([pMidL, pMidR, pBottom], const Color(0xFFF97316));
    drawFacet([pRight, pMidR, pBottom], const Color(0xFF3B82F6));

    void drawNode(Offset o, Color inner, Color border) {
      canvas.drawCircle(o, s * 0.022, Paint()..color = inner);
      canvas.drawCircle(o, s * 0.022, Paint()..color = border..strokeWidth = 1.5..style = PaintingStyle.stroke);
    }

    drawNode(pTop, Colors.white, const Color(0xFF2563EB));
    drawNode(pLeft, Colors.white, const Color(0xFF2563EB));
    drawNode(pRight, Colors.white, const Color(0xFF2563EB));
    drawNode(pMidL, const Color(0xFFF97316), Colors.white);
    drawNode(pMidR, const Color(0xFFF97316), Colors.white);
    drawNode(pBottom, Colors.white, const Color(0xFFF97316));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
