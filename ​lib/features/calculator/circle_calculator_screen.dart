import 'dart:math' as math;
import 'package:flutter/material.dart';

class CircleCalculatorScreen extends StatefulWidget {
  const CircleCalculatorScreen({super.key});

  @override
  State<CircleCalculatorScreen> createState() => _CircleCalculatorScreenState();
}

class _CircleCalculatorScreenState extends State<CircleCalculatorScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  
  // Режим ввода: 'diameter' или 'radius'
  String _mode = 'diameter';
  
  // Единица измерения ввода: 'mm', 'cm', 'm'
  String _inputUnit = 'mm';
  
  // Единица измерения площади: 'mm2', 'cm2', 'm2'
  String _areaUnit = 'cm2';

  double _value = 0.0;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  // Радиус в метрах (базовая величина для расчетов)
  double get _radiusInMeters {
    if (_value <= 0) return 0.0;
    double rawRadius = (_mode == 'diameter') ? _value / 2.0 : _value;
    switch (_inputUnit) {
      case 'mm':
        return rawRadius / 1000.0;
      case 'cm':
        return rawRadius / 100.0;
      case 'm':
        return rawRadius;
      default:
        return rawRadius / 1000.0;
    }
  }

  // Площадь сечения в выбранной размерности
  double get _calculatedArea {
    final rM = _radiusInMeters;
    if (rM <= 0) return 0.0;
    final areaM2 = math.pi * rM * rM;
    switch (_areaUnit) {
      case 'mm2':
        return areaM2 * 1000000.0;
      case 'cm2':
        return areaM2 * 10000.0;
      case 'm2':
        return areaM2;
      default:
        return areaM2 * 10000.0;
    }
  }

  // Длина окружности (периметр) в см
  double get _circumferenceCm {
    final rM = _radiusInMeters;
    if (rM <= 0) return 0.0;
    return (2 * math.pi * rM) * 100.0;
  }

  // Диаметр в мм (стандартный калибр керна)
  double get _diameterMm {
    final rM = _radiusInMeters;
    if (rM <= 0) return 0.0;
    return (2 * rM) * 1000.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Геометрия сечения керна'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Карточка результата
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ПЛОЩАДЬ СЕЧЕНИЯ (S)',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1.2),
                      ),
                      DropdownButton<String>(
                        value: _areaUnit,
                        isDense: true,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'mm2', child: Text('мм²', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                          DropdownMenuItem(value: 'cm2', child: Text('см²', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2563EB)))),
                          DropdownMenuItem(value: 'm2', child: Text('м²', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _areaUnit = val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _calculatedArea > 0 ? _calculatedArea.toStringAsFixed(_areaUnit == 'm2' ? 6 : 2) : '0.00',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  const Divider(height: 24, color: Color(0xFFF1F5F9)),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Калибр d', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                            Text('${_diameterMm.toStringAsFixed(1)} мм', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Длина окружности L', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                            Text('${_circumferenceCm.toStringAsFixed(2)} см', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Выбор режима: Диаметр или Радиус
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Диаметр (d)')),
                    selected: _mode == 'diameter',
                    selectedColor: const Color(0xFF2563EB),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _mode == 'diameter' ? Colors.white : const Color(0xFF475569),
                    ),
                    onSelected: (sel) {
                      if (sel) setState(() => _mode = 'diameter');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Радиус (r)')),
                    selected: _mode == 'radius',
                    selectedColor: const Color(0xFF2563EB),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _mode == 'radius' ? Colors.white : const Color(0xFF475569),
                    ),
                    onSelected: (sel) {
                      if (sel) setState(() => _mode = 'radius');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Поле ввода значения
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: _mode == 'diameter' ? 'Например, 42.5' : 'Например, 21.25',
                        border: InputBorder.none,
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _value = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                        });
                      },
                    ),
                  ),
                  DropdownButton<String>(
                    value: _inputUnit,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'mm', child: Text('мм', style: TextStyle(fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 'cm', child: Text('см', style: TextStyle(fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 'm', child: Text('м', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _inputUnit = val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Быстрые стандартные диаметры керна
            const Text(
              'СТАНДАРТНЫЕ КАЛИБРЫ КЕРНА (ГОСТ):',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1.0),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [42.0, 50.0, 54.7, 63.5, 76.0, 93.0, 100.0].map((d) {
                return ActionChip(
                  label: Text('$d мм', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  onPressed: () {
                    setState(() {
                      _mode = 'diameter';
                      _inputUnit = 'mm';
                      _value = d;
                      _inputCtrl.text = d.toString();
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
