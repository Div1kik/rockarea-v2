import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'features/archive/archive_screen.dart';
import 'features/segmentation/rock_area_logo.dart';
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
              // Векторный логотип ROCKAREA
              const RockAreaLogo(size: 150),
              const SizedBox(height: 48),

              // Кнопка фотосъёмки с листа А4
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

              // Кнопка выбора из галереи
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

              // Переход в журнал испытаний
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
