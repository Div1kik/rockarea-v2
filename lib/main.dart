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
      title: 'RockArea Core v2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFF97316),
          secondary: Color(0xFF2563EB),
          surface: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: const MainCaptureScreen(),
    );
  }
}

class MainCaptureScreen extends StatefulWidget {
  const MainCaptureScreen({super.key});

  @override
  State<MainCaptureScreen> createState() => _MainCaptureScreenState();
}

class _MainCaptureScreenState extends State<MainCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isLoading = true);
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );

      if (photo != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VectorPolygonEditor(imagePath: photo.path),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка захвата: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('RockArea Core v2', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined, color: Color(0xFF2563EB)),
            tooltip: 'Журнал испытаний',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArchiveScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF7ED),
                  border: Border.all(color: const Color(0xFFF97316), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.view_in_ar_outlined, size: 48, color: Color(0xFFF97316)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Планиметрия керна и сколов',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Разместите образцы на листе бумаги для точной авто-сегментации контуров и расчёта площади',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 40),
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFFF97316))
              else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF97316),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Сделать снимок камерой', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Выбрать фото из галереи', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ArchiveScreen()),
                    );
                  },
                  icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF64748B), size: 18),
                  label: const Text('Открыть архив сессий', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
