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
          seedColor: const Color(0xFFF97316),
          primary: const Color(0xFFF97316),
          secondary: const Color(0xFF2563EB),
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
            icon: const Icon(Icons.folder_outlined, color: Color(0xFFF97316)),
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
              // Прежняя оранжевая эмблема с кристаллическими гранями
              const OrangeCrystalLogo(size: 140),
              const SizedBox(height: 44),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
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

class OrangeCrystalLogo extends StatelessWidget {
  final double size;
  const OrangeCrystalLogo({super.key, this.size = 130});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _OrangeCrystalPainter(),
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
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.bold,
            fontSize: 8,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _OrangeCrystalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;

    // Скругленный оранжевый контейнер
    final bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.24),
    );
    canvas.drawRRect(bgRRect, Paint()..color = const Color(0xFFFFF7ED));
    canvas.drawRRect(
      bgRRect,
      Paint()
        ..color = const Color(0xFFFDBA74).withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Геометрия кристалла керна
    final pTop = Offset(s * 0.50, s * 0.20);
    final pLeft = Offset(s * 0.28, s * 0.36);
    final pRight = Offset(s * 0.72, s * 0.36);
    final pCenter = Offset(s * 0.50, s * 0.46);
    final pMidL = Offset(s * 0.36, s * 0.58);
    final pMidR = Offset(s * 0.64, s * 0.58);
    final pBottom = Offset(s * 0.50, s * 0.74);

    void drawFacet(List<Offset> points, Color color) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    // Теплые оранжевые грани
    drawFacet([pTop, pLeft, pCenter], const Color(0xFFFB923C));
    drawFacet([pTop, pRight, pCenter], const Color(0xFFFDBA74));
    drawFacet([pLeft, pMidL, pBottom], const Color(0xFFEA580C));
    drawFacet([pMidL, pMidR, pBottom], const Color(0xFFF97316));
    drawFacet([pRight, pMidR, pBottom], const Color(0xFFC2410C));

    // Узлы
    void drawNode(Offset o, Color inner) {
      canvas.drawCircle(o, s * 0.024, Paint()..color = inner);
      canvas.drawCircle(o, s * 0.024, Paint()..color = Colors.white..strokeWidth = 1.8..style = PaintingStyle.stroke);
    }

    drawNode(pTop, const Color(0xFFEA580C));
    drawNode(pLeft, const Color(0xFFEA580C));
    drawNode(pRight, const Color(0xFFEA580C));
    drawNode(pMidL, const Color(0xFFF97316));
    drawNode(pMidR, const Color(0xFFF97316));
    drawNode(pBottom, Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
