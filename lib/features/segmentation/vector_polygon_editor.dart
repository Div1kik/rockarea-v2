  void _openStrengthCalculator() {
    final List<SampleStrengthData> items = [];
    for (int i = 0; i < _polygons.length; i++) {
      final p = _polygons[i];
      final area = PolygonMath.computeShoelaceArea(p.points) / _pixelsPerCm2;
      final existing = _strengthDataMap[i];

      items.add(SampleStrengthData(
        part1: existing?.part1 ?? '',
        part2: existing?.part2 ?? '',
        part3: existing?.part3 ?? '',
        areaCm2: area,
        loadKn: existing?.loadKn ?? 0.0,
        condition: existing?.condition ?? 'n',
      ));
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StrengthCalculatorSheet(
          title: 'Результаты испытаний',
          initialSamples: items,
          onSaved: (updated) {
            for (int i = 0; i < updated.length; i++) {
              _strengthDataMap[i] = updated[i];
              final parts = [updated[i].part1, updated[i].part2, updated[i].part3].where((e) => e.isNotEmpty).join(' ');
              _polygons[i].id = parts.isNotEmpty ? parts : 'Образец ${i + 1}';
            }
            setState(() {});
          },
        ),
      ),
    );
  }
