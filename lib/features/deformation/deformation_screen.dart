import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/archive_service.dart';
import '../segmentation/vector_polygon_editor.dart';
import 'deformation_chart_and_export.dart';
import 'deformation_models.dart';
import 'lithotype_db.dart';

class DeformationModuleScreen extends StatefulWidget {
  const DeformationModuleScreen({super.key});

  @override
  State<DeformationModuleScreen> createState() => _DeformationModuleScreenState();
}

class _DeformationModuleScreenState extends State<DeformationModuleScreen> {
  List<DeformationRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DeformationStorageService.getRecords();
    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  Future<void> _openWizard([DeformationRecord? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeformationWizardScreen(existingRecord: existing),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Деформационные характеристики'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined, color: Color(0xFF059669)),
              tooltip: 'Выгрузить сводную ведомость CSV',
              onPressed: () => DeformationExportService.exportDeformationCsv(
                context: context,
                records: _records,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        onPressed: () => _openWizard(),
        icon: const Icon(Icons.add),
        label: const Text('Новый расчет', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.analytics_outlined, size: 42, color: Color(0xFF2563EB)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Нет расчетов деформаций',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Пошаговый расчет E, E₀, ν и μ для крупного щебня и обломков: на сферических инденторах (с фото на А4 или импортом из архива) либо по Протодьяконову.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _openWizard(),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Начать расчет', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: _records.length,
                  itemBuilder: (context, idx) {
                    final r = _records[idx];
                    final isIndenter = r.method == DeformationCalcMethod.indenters;
                    return Card(
                      color: Colors.white,
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openWizard(r),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.cipher.isNotEmpty ? r.cipher : r.id,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isIndenter ? const Color(0xFFEFF6FF) : const Color(0xFFFFF7ED),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isIndenter ? 'Инденторы' : 'Протодьяконов',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isIndenter ? const Color(0xFF2563EB) : const Color(0xFFEA580C),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                                    onPressed: () async {
                                      await DeformationStorageService.deleteRecord(r.id);
                                      _load();
                                    },
                                  ),
                                ],
                              ),
                              Text(
                                '${r.lithotype.name} • ${r.date}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _miniMetric('E (Юнга)', '${r.modulusYoungEGpa.toStringAsFixed(1)} ГПа'),
                                  _miniMetric('E₀ (деф.)', '${r.modulusDeformationE0Gpa.toStringAsFixed(1)} ГПа'),
                                  _miniMetric('ν', r.poissonNu.toStringAsFixed(2)),
                                  _miniMetric('μ', r.transverseStrainMu.toStringAsFixed(2)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _miniMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
      ],
    );
  }
}

class DeformationWizardScreen extends StatefulWidget {
  final DeformationRecord? existingRecord;
  const DeformationWizardScreen({super.key, this.existingRecord});

  @override
  State<DeformationWizardScreen> createState() => _DeformationWizardScreenState();
}

class _DeformationWizardScreenState extends State<DeformationWizardScreen> {
  late DeformationRecord _record;
  int _currentStep = 0;

  // Контроллеры Шага 1 (Паспорт и физика)
  late TextEditingController _cipherCtrl;
  late TextEditingController _boreholeCtrl;
  late TextEditingController _intervalCtrl;
  late TextEditingController _rhoDCtrl;
  late TextEditingController _rhoSCtrl;
  late TextEditingController _radiusCtrl;
  late TextEditingController _complianceCtrl;

  // Контроллеры ручного ввода прочности / Протодьяконова
  late TextEditingController _manualLoadCtrl;
  late TextEditingController _manualAreaCtrl;
  late TextEditingController _manualRcCtrl;
  late TextEditingController _protoDropsCtrl;
  late TextEditingController _protoDustCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    _record = widget.existingRecord ??
        DeformationRecord(
          id: 'Деф #${now.millisecondsSinceEpoch.toString().substring(8)}',
          date: dateStr,
          defSamples: [
            IndenterDeformationSample(),
            IndenterDeformationSample(),
            IndenterDeformationSample(),
          ],
        );

    if (_record.defSamples.isEmpty) {
      _record.defSamples = [
        IndenterDeformationSample(),
        IndenterDeformationSample(),
        IndenterDeformationSample(),
      ];
    }

    _cipherCtrl = TextEditingController(text: _record.cipher);
    _boreholeCtrl = TextEditingController(text: _record.borehole);
    _intervalCtrl = TextEditingController(text: _record.interval);
    _rhoDCtrl = TextEditingController(text: _record.rhoDGcm3?.toString() ?? '');
    _rhoSCtrl = TextEditingController(text: _record.rhoSGcm3?.toString() ?? '');
    _radiusCtrl = TextEditingController(text: _record.indenterRadiusMm.toString());
    _complianceCtrl = TextEditingController(text: _record.frameComplianceMmPerKn.toString());

    _manualLoadCtrl = TextEditingController(text: _record.manualAvgLoadKn?.toString() ?? '');
    _manualAreaCtrl = TextEditingController(text: _record.manualAvgAreaCm2?.toString() ?? '');
    _manualRcCtrl = TextEditingController(text: _record.manualRcMpa?.toString() ?? '');
    _protoDropsCtrl = TextEditingController(text: _record.protoDropsN.toString());
    _protoDustCtrl = TextEditingController(
      text: _record.protoDustHeightMm > 0 ? _record.protoDustHeightMm.toString() : '',
    );
  }

  @override
  void dispose() {
    _cipherCtrl.dispose();
    _boreholeCtrl.dispose();
    _intervalCtrl.dispose();
    _rhoDCtrl.dispose();
    _rhoSCtrl.dispose();
    _radiusCtrl.dispose();
    _complianceCtrl.dispose();
    _manualLoadCtrl.dispose();
    _manualAreaCtrl.dispose();
    _manualRcCtrl.dispose();
    _protoDropsCtrl.dispose();
    _protoDustCtrl.dispose();
    super.dispose();
  }

  void _syncControllersToRecord() {
    _record.cipher = _cipherCtrl.text.trim();
    _record.borehole = _boreholeCtrl.text.trim();
    _record.interval = _intervalCtrl.text.trim();
    _record.rhoDGcm3 = double.tryParse(_rhoDCtrl.text.replaceAll(',', '.'));
    _record.rhoSGcm3 = double.tryParse(_rhoSCtrl.text.replaceAll(',', '.'));
    _record.indenterRadiusMm = double.tryParse(_radiusCtrl.text.replaceAll(',', '.')) ?? 15.0;
    _record.frameComplianceMmPerKn = double.tryParse(_complianceCtrl.text.replaceAll(',', '.')) ?? 0.0015;

    _record.manualAvgLoadKn = double.tryParse(_manualLoadCtrl.text.replaceAll(',', '.'));
    _record.manualAvgAreaCm2 = double.tryParse(_manualAreaCtrl.text.replaceAll(',', '.'));
    _record.manualRcMpa = double.tryParse(_manualRcCtrl.text.replaceAll(',', '.'));
    _record.protoDropsN = int.tryParse(_protoDropsCtrl.text.trim()) ?? 5;
    _record.protoDustHeightMm = double.tryParse(_protoDustCtrl.text.replaceAll(',', '.')) ?? 0.0;
  }

  Future<void> _saveRecord() async {
    _syncControllersToRecord();
    await DeformationStorageService.saveRecord(_record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFF059669), content: Text('Расчет сохранен в журнал модуля')),
      );
    }
  }

  /// Выгрузка готовых данных прочности из Архива RockArea
  Future<void> _importFromStrengthArchive() async {
    final records = await ArchiveService.getRecords();
    if (!mounted) return;

    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Архив прочности пока пуст')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите серию из Архива прочности',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: records.length,
                itemBuilder: (c, i) {
                  final rec = records[i];
                  final validSamples = rec.samples.where((s) => s.loadKn > 0 && s.areaCm2 > 0).toList();
                  final avgLoad = validSamples.isNotEmpty
                      ? validSamples.map((s) => s.loadKn).reduce((a, b) => a + b) / validSamples.length
                      : 0.0;
                  final firstCipher = rec.samples.isNotEmpty ? rec.samples.first.name : rec.id;

                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEFF6FF),
                      child: Icon(Icons.layers_outlined, color: Color(0xFF2563EB)),
                    ),
                    title: Text('$firstCipher (${rec.id})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${rec.date} • Образцов с нагрузкой: ${validSamples.length} • Pср = ${avgLoad.toStringAsFixed(2)} кН',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _record.method = DeformationCalcMethod.indenters;
                        if (_cipherCtrl.text.trim().isEmpty && firstCipher != 'Образец 1') {
                          _cipherCtrl.text = firstCipher;
                          _record.cipher = firstCipher;
                        }
                        if (validSamples.isNotEmpty) {
                          _record.condition = validSamples.first.condition;
                          _record.breakSamples = validSamples
                              .map((s) => IndenterBreakSample(areaCm2: s.areaCm2, loadKn: s.loadKn))
                              .toList();
                        } else if (rec.samples.isNotEmpty) {
                          _record.manualAvgAreaCm2 = rec.totalAreaCm2 / rec.samples.length;
                          _manualAreaCtrl.text = _record.manualAvgAreaCm2!.toStringAsFixed(2);
                        }
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF2563EB),
                          content: Text('Загружено ${validSamples.length} обр. из архива! Ступени P1/P2 рассчитаны.'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Запуск фото-разметки на листе А4 для определения площади скола S и P_разр
  Future<void> _capturePhotoForBreakSample() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Съемка скола на листе А4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF2563EB)),
              title: const Text('Сделать фото камерой'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFFF97316)),
              title: const Text('Выбрать фото из галереи'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;
    final XFile? file = await picker.pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
    if (file == null || !mounted) return;

    final List<SampleItem>? returnedSamples = await Navigator.push<List<SampleItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => VectorPolygonEditor(
          imagePath: file.path,
          returnSamplesMode: true,
        ),
      ),
    );

    if (returnedSamples != null && returnedSamples.isNotEmpty && mounted) {
      setState(() {
        for (final item in returnedSamples) {
          _record.breakSamples.add(
            IndenterBreakSample(areaCm2: item.areaCm2, loadKn: item.loadKn),
          );
        }
      });
      // Если для каких-то фото-образцов еще не введена разрушающая нагрузка P — сразу попросим ввести
      for (int i = 0; i < _record.breakSamples.length; i++) {
        if (_record.breakSamples[i].loadKn <= 0) {
          await _promptLoadForBreakSample(i);
        }
      }
    }
  }

  Future<void> _promptLoadForBreakSample(int index) async {
    final s = _record.breakSamples[index];
    final loadCtrl = TextEditingController(text: s.loadKn > 0 ? s.loadKn.toString() : '');
    final areaCtrl = TextEditingController(text: s.areaCm2 > 0 ? s.areaCm2.toStringAsFixed(2) : '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Кусок #${index + 1} (Разрушение)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: areaCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Площадь скола S (см²)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: loadCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Разрушающая нагрузка Pразр (кН)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
            onPressed: () {
              setState(() {
                s.areaCm2 = double.tryParse(areaCtrl.text.replaceAll(',', '.')) ?? s.areaCm2;
                s.loadKn = double.tryParse(loadCtrl.text.replaceAll(',', '.')) ?? 0.0;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncControllersToRecord();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_record.cipher.isNotEmpty ? _record.cipher : 'Расчет деформаций'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Color(0xFF2563EB)),
            tooltip: 'Сохранить расчет',
            onPressed: _saveRecord,
          ),
        ],
      ),
      body: Column(
        children: [
          // Верхняя шкала шагов
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _stepTab(0, '1. Паспорт и БД'),
                _stepArrow(),
                _stepTab(1, '2. Прочность'),
                _stepArrow(),
                _stepTab(2, '3. Нагружение'),
                _stepArrow(),
                _stepTab(3, '4. Итог / График'),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildStep1Passport(),
                _buildStep2StrengthSource(),
                _buildStep3LoadingStage(),
                _buildStep4ResultAndChart(),
              ],
            ),
          ),

          // Нижняя панель навигации между шагами
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (_currentStep > 0)
                  OutlinedButton(
                    onPressed: () => setState(() => _currentStep--),
                    child: const Text('Назад'),
                  )
                else
                  const SizedBox.shrink(),
                const Spacer(),
                if (_currentStep < 3)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      _syncControllersToRecord();
                      // Если выбран Протодьяконов, шаг 3 (инденторы) не нужен — сразу на Итог
                      if (_currentStep == 1 && _record.method == DeformationCalcMethod.protodyakonov) {
                        setState(() => _currentStep = 3);
                      } else {
                        setState(() => _currentStep++);
                      }
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(
                      _currentStep == 1 && _record.method == DeformationCalcMethod.protodyakonov
                          ? 'К расчету E, E₀, ν, μ'
                          : 'Далее',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await _saveRecord();
                      if (context.mounted) {
                        DeformationExportService.exportDeformationCsv(
                          context: context,
                          records: [_record],
                        );
                      }
                    },
                    icon: const Icon(Icons.table_view, size: 18),
                    label: const Text('Сохранить и в Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTab(int idx, String label) {
    final active = _currentStep == idx;
    return Expanded(
      child: InkWell(
        onTap: () {
          _syncControllersToRecord();
          setState(() => _currentStep = idx);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: active ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepArrow() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2),
        child: Icon(Icons.chevron_right, size: 14, color: Color(0xFF94A3B8)),
      );

  /// ШАГ 1: Паспорт пробы, БД литотипов и опциональная физика
  Widget _buildStep1Passport() {
    final lit = _record.lithotype;
    final por = _record.porosityPercent;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Идентификация пробы'),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(
                  controller: _cipherCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Шифр пробы (например, БАМ 1 1)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _boreholeCtrl,
                        decoration: const InputDecoration(labelText: 'Скважина', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _intervalCtrl,
                        decoration: const InputDecoration(labelText: 'Интервал, м', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _record.condition,
                  decoration: const InputDecoration(labelText: 'Состояние пробы', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'n', child: Text('n — естественная влажность')),
                    DropdownMenuItem(value: 'w', child: Text('w — водонасыщенное')),
                    DropdownMenuItem(value: 'h', child: Text('h — воздушно-сухое')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _record.condition = val);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        _sectionTitle('БД литотипов (автоподстановка коэффициентов)'),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _record.lithotypeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Литологический тип породы',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: LithotypeDatabase.profiles
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _record.lithotypeId = val);
                  },
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'Автопараметры БД (${lit.genesis}): Eскелета = ${lit.eSkeletonGpa} ГПа • αлит = ${lit.alphaLit.toStringAsFixed(0)} • ν₀ = ${lit.nu0} • ρs(умолч.) = ${lit.rhoSDefault} г/см³',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        _sectionTitle('Пористость и оснастка пресса (опционально)'),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Если делали плотность куска — введите ρd, модуль скорректируется по пористости:',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rhoDCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Плотность ρd (г/см³)', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _rhoSCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'ρs (${lit.rhoSDefault})',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                if (por != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Расчетная пористость пробы: n = ${por.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _radiusCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Радиус инд. R (мм)', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _complianceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Податл. станины (мм/кН)', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ШАГ 2: Развилка — есть ли прочность (Импорт / Фото с нуля / Ручной ввод / Протодьяконов)
  Widget _buildStep2StrengthSource() {
    final p1 = _record.recommendedP1Kn;
    final p2 = _record.recommendedP2Kn;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Выберите метод и наличие данных по прочности'),
        SegmentedButton<DeformationCalcMethod>(
          segments: const [
            ButtonSegment(
              value: DeformationCalcMethod.indenters,
              icon: Icon(Icons.compress, size: 16),
              label: Text('Инденторы (ГОСТ 24941)', style: TextStyle(fontSize: 11)),
            ),
            ButtonSegment(
              value: DeformationCalcMethod.protodyakonov,
              icon: Icon(Icons.hardware, size: 16),
              label: Text('Протодьяконов (копер)', style: TextStyle(fontSize: 11)),
            ),
          ],
          selected: {_record.method},
          onSelectionChanged: (set) {
            setState(() => _record.method = set.first);
          },
        ),
        const SizedBox(height: 14),

        if (_record.method == DeformationCalcMethod.protodyakonov) ...[
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Испытание по ГОСТ 21153.1-75 (толчение в копре)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Используется для мелкого щебня, когда куски нельзя зажать между сферическими инденторами.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _protoDropsCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Число ударов n (обычно 5)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _protoDustCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Высота пыли l (мм)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_record.protodyakonovF > 0)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        'Коэффициент крепости f = ${_record.protodyakonovF.toStringAsFixed(2)} • Оценка Rc = ${_record.equivalentRcMpa.toStringAsFixed(1)} МПа',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF059669)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ] else ...[
          // Ветка инденторов: 3 способа задать опорную разрушающую нагрузку
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Откуда берем разрушающую нагрузку Pразр?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Она нужна, чтобы программа рассчитала безопасные ступени P₁ и P₂ и не расколола образцы при замере деформаций.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),

                  // Вариант 1: Импорт из архива
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        side: const BorderSide(color: Color(0xFF2563EB)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: _importFromStrengthArchive,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Выгрузить из Архива прочности RockArea', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Вариант 2: С нуля с фото на А4
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF97316),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: _capturePhotoForBreakSample,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('С нуля: сфотографировать раскол на листе А4', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Список кусков Серии 1 (если добавлены через фото или вручную)
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Куски Серии 1 (разрушение)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _record.breakSamples.add(IndenterBreakSample(areaCm2: 6.0, loadKn: 0.0));
                          });
                          _promptLoadForBreakSample(_record.breakSamples.length - 1);
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Вручную', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  if (_record.breakSamples.isEmpty) ...[
                    const Text(
                      'Если серия кусков не набиралась, можно просто вписать среднюю Pразр с бумажного журнала:',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualLoadCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Средняя Pразр (кН)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _manualAreaCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Средняя S (см²)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    for (int i = 0; i < _record.breakSamples.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Кусок #${i + 1}: S = ${_record.breakSamples[i].areaCm2.toStringAsFixed(2)} см² • Pразр = ${_record.breakSamples[i].loadKn.toStringAsFixed(2)} кН',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'σp = ${_record.breakSamples[i].tensileMpa.toStringAsFixed(2)} МПа • Rc = ${_record.breakSamples[i].compMpa.toStringAsFixed(1)} МПа',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF059669)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 16, color: Color(0xFF2563EB)),
                              onPressed: () => _promptLoadForBreakSample(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Color(0xFFDC2626)),
                              onPressed: () => setState(() => _record.breakSamples.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Предпросмотр рассчитанных ступеней для Шага 3
          if (p2 > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Готово задание для пресса на следующий шаг:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E40AF)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Ступень 1 (обжатие): P₁ = ${p1.toStringAsFixed(2)} кН\n'
                    '• Ступень 2 (рабочая): P₂ = ${p2.toStringAsFixed(2)} кН\n'
                    '• Мин. площадь сечения куска: Smin ≥ ${_record.minRecommendedAreaCm2.toStringAsFixed(1)} см²',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// ШАГ 3: Интерактивное нагружение Серии 2 (пошаговый ввод отсчетов индикаторов)
  Widget _buildStep3LoadingStage() {
    final p1 = _record.recommendedP1Kn;
    final p2 = _record.recommendedP2Kn;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Крупная карточка-задание для оператора пресса
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.engineering, color: Color(0xFFFB923C), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'ЗАДАНИЕ НА ИСПЫТАНИЕ (СЕРИЯ 2)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (p2 <= 0)
                const Text(
                  'Внимание: не задана разрушающая нагрузка Pразр на Шаге 2. Вернитесь на Шаг 2, чтобы программа рассчитала ступени P₁ и P₂.',
                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
                )
              else ...[
                Text(
                  '1. Подберите куски с площадью сечения ≥ ${_record.minRecommendedAreaCm2.toStringAsFixed(1)} см² и высотой ≥ 10 мм.\n'
                  '2. Нагрузите до P₁ = ${p1.toStringAsFixed(2)} кН → запишите h₁.\n'
                  '3. Поднимите до P₂ = ${p2.toStringAsFixed(2)} кН → запишите h₂.\n'
                  '4. Сбросьте до P₁ = ${p1.toStringAsFixed(2)} кН → запишите h₁(разгр).',
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, height: 1.45),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            const Expanded(
              child: Text(
                'Отсчеты индикаторов (мм)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _record.defSamples.add(IndenterDeformationSample()));
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Добавить кусок'),
            ),
          ],
        ),

        for (int i = 0; i < _record.defSamples.length; i++) _buildIndenterSampleCard(i),
      ],
    );
  }

  Widget _buildIndenterSampleCard(int index) {
    final s = _record.defSamples[index];
    final singleRes = _record.calcSingleIndenterModuli(s);
    final bool hasPhysicsWarning = s.h2Mm > s.h1Mm && s.h1UnloadMm > 0 && s.h1UnloadMm < s.h1Mm;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasPhysicsWarning ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFFEFF6FF),
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Образец #${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                // Страховка: если кусок лопнул при попытке дойти до P2
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEA580C),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _handlePrematureBreak(index),
                  child: const Text('Кусок лопнул!', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                if (_record.defSamples.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                    onPressed: () => setState(() => _record.defSamples.removeAt(index)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: s.h1Mm > 0 ? s.h1Mm.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'h₁ (при P₁)', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) {
                      setState(() => s.h1Mm = double.tryParse(v.replaceAll(',', '.')) ?? 0.0);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: s.h2Mm > 0 ? s.h2Mm.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'h₂ (при P₂)', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) {
                      setState(() => s.h2Mm = double.tryParse(v.replaceAll(',', '.')) ?? 0.0);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: s.h1UnloadMm > 0 ? s.h1UnloadMm.toString() : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'h₁ разгр.', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) {
                      setState(() => s.h1UnloadMm = double.tryParse(v.replaceAll(',', '.')) ?? 0.0);
                    },
                  ),
                ),
              ],
            ),
            if (hasPhysicsWarning)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Проверьте отсчет: после разгрузки h₁(разгр) не может быть меньше начального h₁.',
                  style: TextStyle(fontSize: 10, color: Color(0xFFDC2626), fontWeight: FontWeight.bold),
                ),
              )
            else if (singleRes != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'По куску: E = ${singleRes[0].toStringAsFixed(2)} ГПа • E₀ = ${singleRes[1].toStringAsFixed(2)} ГПа',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Обработка ситуации, когда образец 2-й серии лопнул до достижения P2
  Future<void> _handlePrematureBreak(int index) async {
    final pCtrl = TextEditingController();
    final sCtrl = TextEditingController(text: _record.avgAreaCm2.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Образец разрушился до P₂', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Перенесем его в Серию 1 (прочность), чтобы программа уточнила среднюю прочность и снизила ступень P₂ для следующих кусков.',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Нагрузка при расколе (кН)', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: sCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Площадь скола S (см²)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF97316), foregroundColor: Colors.white),
            onPressed: () {
              final pVal = double.tryParse(pCtrl.text.replaceAll(',', '.')) ?? 0.0;
              final sVal = double.tryParse(sCtrl.text.replaceAll(',', '.')) ?? _record.avgAreaCm2;
              if (pVal > 0) {
                setState(() {
                  _record.breakSamples.add(IndenterBreakSample(areaCm2: sVal, loadKn: pVal));
                  _record.defSamples[index] = IndenterDeformationSample();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Пересчитать ступени'),
          ),
        ],
      ),
    );
  }

  /// ШАГ 4: Итоговые 4 характеристики, график деформирования и примечание для протокола
  Widget _buildStep4ResultAndChart() {
    final e = _record.modulusYoungEGpa;
    final e0 = _record.modulusDeformationE0Gpa;
    final nu = _record.poissonNu;
    final mu = _record.transverseStrainMu;
    final rc = _record.equivalentRcMpa;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Деформационные характеристики пробы'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.75,
          children: [
            _resultTile(
              'Модуль упругости (Юнга) E',
              e > 0 ? '${e.toStringAsFixed(2)} ГПа' : '—',
              const Color(0xFFEA580C),
              const Color(0xFFFFF7ED),
            ),
            _resultTile(
              'Модуль деформации E₀',
              e0 > 0 ? '${e0.toStringAsFixed(2)} ГПа' : '—',
              const Color(0xFF2563EB),
              const Color(0xFFEFF6FF),
            ),
            _resultTile(
              'Коэффициент Пуассона ν',
              e > 0 ? nu.toStringAsFixed(3) : '—',
              const Color(0xFF059669),
              const Color(0xFFECFDF5),
            ),
            _resultTile(
              'Коэф. попереч. деф. μ',
              e > 0 ? mu.toStringAsFixed(3) : '—',
              const Color(0xFF7C3AED),
              const Color(0xFFF5F3FF),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (_record.hasValidResult) ...[
          DeformationChartCard(record: _record),
          const SizedBox(height: 14),
        ],

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Справка для лабораторной ведомости:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 4),
              Text(
                '• Методика: ${_record.method == DeformationCalcMethod.indenters ? "Нагружение сферическими инденторами (ГОСТ 24941-81 / ГОСТ Р 59958-2021)" : "Расчетный метод по копру Протодьяконова (ГОСТ 21153.1-75) и пористости"}.\n'
                '• Опорный предел прочности на сжатие: Rc = ${rc.toStringAsFixed(1)} МПа.\n'
                '• Примечание: характеристики получены для монолитного куска породы (обломков щебня).',
                style: const TextStyle(fontSize: 11, color: Color(0xFF475569), height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultTile(String title, String value, Color accent, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.8),
      ),
    );
  }
}
