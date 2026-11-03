import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          surface: Color(0xFF131C2E),
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
      appBar: AppBar(
        title: const Text('RockArea v2 — Лаборатория', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF131C2E),
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
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  border: Border.all(color: const Color(0xFF10B981), width: 2),
                ),
                child: const Icon(Icons.analytics_outlined, size: 48, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Планиметрия сечения керна',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Сделайте снимок торца образца скальной породы для векторной сегментации контура',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 40),
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF10B981))
              else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Сделать снимок камеры', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      side: const BorderSide(color: Color(0xFF334155)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Выбрать образец из галереи'),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
