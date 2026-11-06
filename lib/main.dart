import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'features/archive/archive_screen.dart';
import 'features/calculator/circle_calculator_screen.dart';
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
      home: const MainMenuScreen(),
    );
  }
}

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  void _showImageSourceDialog(BuildContext context) {
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Съемка керна на листе А4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF2563EB)),
              title: const Text('Сделать фото камерой', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? file = await picker.pickImage(source: ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
                if (file != null && context.mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => VectorPolygonEditor(imagePath: file.path)));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFFF97316)),
              title: const Text('Выбрать фото из галереи', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
                if (file != null && context.mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => VectorPolygonEditor(imagePath: file.path)));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('ROCKAREA LAB'),
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Шапка с теплым логотипом
          const Center(child: OrangeCrystalLogo(size: 90)),
          const SizedBox(height: 24),
          const Text(
            'ИНСТРУМЕНТЫ ЛАБОРАТОРИИ',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),

          // Карточка 1: Планиметрия и расчет нагрузок ГОСТ 24941-81
          Card(
            color: Colors.white,
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showImageSourceDialog(context),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(0xFFEFF6FF),
                      child: Icon(Icons.camera_alt, color: Color(0xFF2563EB), size: 22),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Планиметрия и нагрузка (ГОСТ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                          SizedBox(height: 3),
                          Text('Съемка на А4, оконтуривание керна, расчет площадей и σр / Rc', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Карточка 2: Калькулятор круга / калибра керна
          Card(
            color: Colors.white,
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CircleCalculatorScreen()),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(0xFFFFF7ED),
                      child: Icon(Icons.circle_outlined, color: Color(0xFFF97316), size: 22),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Геометрия сечения керна', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                          SizedBox(height: 3),
                          Text('Площадь и длина окружности по диаметру d или радиусу r (мм/см/м)', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Карточка 3: Задел на будущее
          Card(
            color: const Color(0xFFF1F5F9),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0xFFE2E8F0),
                    child: Icon(Icons.science_outlined, color: Color(0xFF94A3B8), size: 22),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Точечная нагрузка (Франклин / Is)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF64748B))),
                        SizedBox(height: 3),
                        Text('Модуль в разработке для следующих обновлений', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrangeCrystalLogo extends StatelessWidget {
  final double size;
  const OrangeCrystalLogo({super.key, this.size = 110});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _OrangeCrystalPainter(),
        ),
        const SizedBox(height: 8),
        const Text(
          'ROCKAREA',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 5,
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

    drawFacet([pTop, pLeft, pCenter], const Color(0xFFFB923C));
    drawFacet([pTop, pRight, pCenter], const Color(0xFFFDBA74));
    drawFacet([pLeft, pMidL, pBottom], const Color(0xFFEA580C));
    drawFacet([pMidL, pMidR, pBottom], const Color(0xFFF97316));
    drawFacet([pRight, pMidR, pBottom], const Color(0xFFC2410C));

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
