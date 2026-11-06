  void _editSampleInline(int index) {
    final poly = _polygons[index];
    final area = PolygonMath.computeShoelaceArea(poly.points) / _pixelsPerCm2;
    final existing = _strengthDataMap[index] ?? SampleStrengthData(areaCm2: area);

    final initialCipher = [existing.part1, existing.part2, existing.part3].where((e) => e.isNotEmpty).join(' ');
    final cipherCtrl = TextEditingController(text: initialCipher);
    final loadCtrl = TextEditingController(text: existing.loadKn > 0 ? existing.loadKn.toString() : '');
    String condition = existing.condition;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Образец #${index + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Шифр пробы (через пробел):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: cipherCtrl,
                  decoration: const InputDecoration(
                    hintText: 'БАМ 1 1',
                    hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Площадь скола S: ${area.toStringAsFixed(2)} см²',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                const SizedBox(height: 12),
                const Text('Разрушающая нагрузка P (кН):', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: loadCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Состояние:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                DropdownButton<String>(
                  value: condition,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'n', child: Text('n — естественная влажность')),
                    DropdownMenuItem(value: 'w', child: Text('w — водонасыщенное')),
                    DropdownMenuItem(value: 'h', child: Text('h — воздушно-сухое')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => condition = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              onPressed: () {
                final raw = cipherCtrl.text.trim().split(RegExp(r'\s+'));
                setState(() {
                  existing.part1 = raw.isNotEmpty ? raw[0] : '';
                  existing.part2 = raw.length > 1 ? raw[1] : '';
                  existing.part3 = raw.length > 2 ? raw[2] : '';
                  existing.loadKn = double.tryParse(loadCtrl.text.replaceAll(',', '.')) ?? 0.0;
                  existing.condition = condition;
                  _strengthDataMap[index] = existing;

                  final cipher = [existing.part1, existing.part2, existing.part3].where((e) => e.isNotEmpty).join(' ');
                  poly.id = cipher.isNotEmpty ? cipher : 'Образец ${index + 1}';
                });
                Navigator.pop(ctx);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }
