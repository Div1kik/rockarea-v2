import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'lithotype_db.dart';

enum DeformationCalcMethod {
  indenters,      // Сферические инденторы (ГОСТ 24941-81 / ГОСТ Р 59958-2021)
  protodyakonov,  // Копёр Протодьяконова (ГОСТ 21153.1-75) + Пористость
}

/// Образец 1-й серии (раскалывание для определения P_разр и sigma_p)
class IndenterBreakSample {
  double areaCm2;
  double loadKn;

  IndenterBreakSample({
    required this.areaCm2,
    required this.loadKn,
  });

  /// Коэффициент K по ГОСТ 24941-81 (как в ExportService)
  double get kFactor => areaCm2 > 0 ? 0.5076 * math.pow(areaCm2, 0.2506) : 0.0;

  /// Предел прочности на растяжение sigma_p, МПа
  double get tensileMpa => areaCm2 > 0 ? (7.5 * loadKn * kFactor) / areaCm2 : 0.0;

  /// Коэффициент пересчета в сжатие по ГОСТ 24941-81
  double get conversionFactor {
    final sp = tensileMpa;
    if (sp <= 0) return 12.0;
    if (sp < 1.0) return 12.0;
    if (sp < 5.0) return 16.0;
    return 20.0;
  }

  /// Предел прочности на одноосное сжатие Rc, МПа
  double get compMpa => tensileMpa * conversionFactor;

  Map<String, dynamic> toJson() => {
        'areaCm2': areaCm2,
        'loadKn': loadKn,
      };

  factory IndenterBreakSample.fromJson(Map<String, dynamic> json) => IndenterBreakSample(
        areaCm2: (json['areaCm2'] as num?)?.toDouble() ?? 0.0,
        loadKn: (json['loadKn'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Образец 2-й серии (ступенчатое упругое нагружение на инденторах)
class IndenterDeformationSample {
  double h1Mm;         // Отсчет индикатора при P1 (обжатие), мм
  double h2Mm;         // Отсчет индикатора при P2 (рабочая ступень), мм
  double h1UnloadMm;   // Отсчет индикатора после разгрузки до P1, мм

  IndenterDeformationSample({
    this.h1Mm = 0.0,
    this.h2Mm = 0.0,
    this.h1UnloadMm = 0.0,
  });

  bool get isFilled => h2Mm > h1Mm && h1UnloadMm > 0;

  Map<String, dynamic> toJson() => {
        'h1Mm': h1Mm,
        'h2Mm': h2Mm,
        'h1UnloadMm': h1UnloadMm,
      };

  factory IndenterDeformationSample.fromJson(Map<String, dynamic> json) => IndenterDeformationSample(
        h1Mm: (json['h1Mm'] as num?)?.toDouble() ?? 0.0,
        h2Mm: (json['h2Mm'] as num?)?.toDouble() ?? 0.0,
        h1UnloadMm: (json['h1UnloadMm'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Итоговый расчетный проект деформационных характеристик
class DeformationRecord {
  final String id;
  final String date;
  String cipher;           // Шифр пробы (например, "БАМ 1 1")
  String borehole;         // № Скважины
  String interval;         // Интервал, м
  String lithotypeId;      // ID породы из LithotypeDatabase
  String condition;        // 'n' (естеств.), 'w' (водонасыщ.), 'h' (возд.-сух.)
  DeformationCalcMethod method;

  // Параметры пресса и инденторов
  double indenterRadiusMm;      // Радиус индентора R (по умолчанию 15.0 мм)
  double frameComplianceMmPerKn; // Тарировочная податливость станины пресса (мм/кН)

  // Физика (опционально для поправки по пористости)
  double? rhoDGcm3;        // Плотность сухого грунта/куска, г/см3
  double? rhoSGcm3;        // Плотность частиц, г/см3

  // Данные Серии 1 (прочность)
  List<IndenterBreakSample> breakSamples;
  double? manualAvgLoadKn; // Если ввели среднюю P_разр вручную без списка кусков
  double? manualAvgAreaCm2;
  double? manualRcMpa;     // Если ввели Rc сразу с журнала

  // Данные Серии 2 (инденторы - упругое нагружение)
  List<IndenterDeformationSample> defSamples;

  // Альтернатива: Протодьяконов (ГОСТ 21153.1-75)
  int protoDropsN;         // Число сбрасываний груза n
  double protoDustHeightMm; // Высота столбика пыли l, мм

  DeformationRecord({
    required this.id,
    required this.date,
    this.cipher = '',
    this.borehole = '',
    this.interval = '',
    this.lithotypeId = 'gabbro_diabase',
    this.condition = 'n',
    this.method = DeformationCalcMethod.indenters,
    this.indenterRadiusMm = 15.0,
    this.frameComplianceMmPerKn = 0.0015, // Типовая податливость рамы ~0.0015 мм/кН
    this.rhoDGcm3,
    this.rhoSGcm3,
    List<IndenterBreakSample>? breakSamples,
    this.manualAvgLoadKn,
    this.manualAvgAreaCm2,
    this.manualRcMpa,
    List<IndenterDeformationSample>? defSamples,
    this.protoDropsN = 5,
    this.protoDustHeightMm = 0.0,
  })  : breakSamples = breakSamples ?? [],
        defSamples = defSamples ?? [];

  LithotypeProfile get lithotype => LithotypeDatabase.getById(lithotypeId);

  /// Расчетная пористость n_пор, % (если задана плотность куска rho_d)
  double? get porosityPercent {
    if (rhoDGcm3 == null || rhoDGcm3! <= 0) return null;
    final rs = (rhoSGcm3 != null && rhoSGcm3! > rhoDGcm3!)
        ? rhoSGcm3!
        : lithotype.rhoSDefault;
    if (rs <= rhoDGcm3!) return 0.5;
    return ((1.0 - (rhoDGcm3! / rs)) * 100.0).clamp(0.0, 60.0);
  }

  /// Средняя разрушающая нагрузка P_разр (кН) по Серии 1 или ручному вводу
  double get avgBreakLoadKn {
    if (breakSamples.isNotEmpty) {
      final valid = breakSamples.where((s) => s.loadKn > 0).toList();
      if (valid.isNotEmpty) {
        return valid.map((s) => s.loadKn).reduce((a, b) => a + b) / valid.length;
      }
    }
    return manualAvgLoadKn ?? 0.0;
  }

  /// Средняя площадь скола S (см2)
  double get avgAreaCm2 {
    if (breakSamples.isNotEmpty) {
      final valid = breakSamples.where((s) => s.areaCm2 > 0).toList();
      if (valid.isNotEmpty) {
        return valid.map((s) => s.areaCm2).reduce((a, b) => a + b) / valid.length;
      }
    }
    return manualAvgAreaCm2 ?? 6.0;
  }

  /// Средний предел прочности на растяжение sigma_p (МПа)
  double get avgTensileMpa {
    if (breakSamples.isNotEmpty) {
      final valid = breakSamples.where((s) => s.tensileMpa > 0).toList();
      if (valid.isNotEmpty) {
        return valid.map((s) => s.tensileMpa).reduce((a, b) => a + b) / valid.length;
      }
    }
    if (avgBreakLoadKn > 0 && avgAreaCm2 > 0) {
      final k = 0.5076 * math.pow(avgAreaCm2, 0.2506);
      return (7.5 * avgBreakLoadKn * k) / avgAreaCm2;
    }
    if (manualRcMpa != null && manualRcMpa! > 0) {
      return manualRcMpa! / 16.0;
    }
    return 0.0;
  }

  /// Коэффициент крепости f по Протодьяконову (ГОСТ 21153.1-75)
  double get protodyakonovF {
    if (protoDropsN <= 0 || protoDustHeightMm <= 0) return 0.0;
    return (20.0 * protoDropsN) / protoDustHeightMm;
  }

  /// Эквивалентный предел прочности на одноосное сжатие Rc (МПа)
  double get equivalentRcMpa {
    if (method == DeformationCalcMethod.protodyakonov) {
      return protodyakonovF * 10.0;
    }
    if (breakSamples.isNotEmpty) {
      final valid = breakSamples.where((s) => s.compMpa > 0).toList();
      if (valid.isNotEmpty) {
        return valid.map((s) => s.compMpa).reduce((a, b) => a + b) / valid.length;
      }
    }
    if (manualRcMpa != null && manualRcMpa! > 0) {
      return manualRcMpa!;
    }
    final sp = avgTensileMpa;
    if (sp <= 0) return 0.0;
    final conv = sp < 1.0 ? 12.0 : (sp < 5.0 ? 16.0 : 20.0);
    return sp * conv;
  }

  /// Рекомендуемая ступень 1 (обжатие) P1 = 0.1 * P_разр, кН
  double get recommendedP1Kn => avgBreakLoadKn > 0 ? avgBreakLoadKn * 0.10 : 0.0;

  /// Рекомендуемая ступень 2 (рабочая упругая) P2 = 0.5 * P_разр, кН
  double get recommendedP2Kn => avgBreakLoadKn > 0 ? avgBreakLoadKn * 0.50 : 0.0;

  /// Минимально допустимая площадь сечения куска для 2-й серии (чтобы не раскололся до P2), см2
  double get minRecommendedAreaCm2 {
    if (recommendedP2Kn <= 0 || avgTensileMpa <= 0) return 3.0;
    // По ГОСТ 24941-81: S > P2 / sigma_p (в единицах: P в кН * 10 / sigma_p в МПа -> см2)
    final sMin = (recommendedP2Kn * 10.0) / avgTensileMpa;
    return math.max(3.0, sMin * 1.15); // С запасом 15%
  }

  /// Расчет E и E0 для одного образца на инденторах (возвращает [E_ГПа, E0_ГПа] или null)
  List<double>? calcSingleIndenterModuli(IndenterDeformationSample s) {
    final p1 = recommendedP1Kn;
    final p2 = recommendedP2Kn;
    final dP_Kn = p2 - p1;
    if (dP_Kn <= 0 || !s.isFilled) return null;

    // Собственная деформация станины пресса на интервале (P2 - P1), мм
    final sysDefMm = frameComplianceMmPerKn * dP_Kn;

    // Полное сближение инденторов за вычетом станины, мм
    final dhTotalMm = (s.h2Mm - s.h1Mm) - sysDefMm;
    // Упругое восстановление при разгрузке до P1, мм
    final dhElasticMm = (s.h2Mm - s.h1UnloadMm) - sysDefMm;

    if (dhTotalMm <= 0.0005 || dhElasticMm <= 0.0005) return null;
    // Защита от некорректного отсчета (упругая не может превышать полную)
    final safeDhElastic = math.min(dhElasticMm, dhTotalMm);

    // Формула Герца для двух встречных сферических инденторов радиуса R (мм), P в Ньютонах:
    // E_к (МПа) = 3 * dP_N / (4 * sqrt(R * dh^3))
    final dP_N = dP_Kn * 1000.0;
    final rMm = indenterRadiusMm > 0 ? indenterRadiusMm : 15.0;

    final ekElasticMpa = (3.0 * dP_N) / (4.0 * math.sqrt(rMm * math.pow(safeDhElastic, 3)));
    final ekTotalMpa = (3.0 * dP_N) / (4.0 * math.sqrt(rMm * math.pow(dhTotalMm, 3)));

    // Переход от контактного модуля к модулю сжатия (коэф. 1.2 по ГОСТ Р 59958-2021) и в ГПа (/1000)
    double eGpa = (1.2 * ekElasticMpa) / 1000.0;
    double e0Gpa = (1.2 * ekTotalMpa) / 1000.0;

    // Если состояние водонасыщенное ('w'), а сухие испытания пересчитываются
    if (condition == 'w') {
      // Фактический замер уже выполнен на водонасыщенном образце, поправка не нужна
    }

    return [eGpa, e0Gpa];
  }

  /// ИТОГ 1: Модуль упругости (Юнга) E, ГПа
  double get modulusYoungEGpa {
    if (method == DeformationCalcMethod.indenters) {
      final validModuli = <double>[];
      for (final s in defSamples) {
        final res = calcSingleIndenterModuli(s);
        if (res != null) validModuli.add(res[0]);
      }
      if (validModuli.isNotEmpty) {
        return validModuli.reduce((a, b) => a + b) / validModuli.length;
      }
      return 0.0;
    } else {
      // Ветка Б: Протодьяконов + Пористость + Литотип
      final rc = equivalentRcMpa;
      if (rc <= 0) return 0.0;

      final por = porosityPercent;
      double eGpa;
      if (por != null) {
        // Уточненная модель через модуль скелета и экспоненту пористости
        final eByPorosity = lithotype.eSkeletonGpa * math.exp(-lithotype.porosityDecayB * por);
        final eByStrength = (lithotype.alphaLit * rc) / 1000.0;
        eGpa = (eByPorosity * 0.6 + eByStrength * 0.4);
      } else {
        eGpa = (lithotype.alphaLit * rc) / 1000.0;
      }

      if (condition == 'w') {
        eGpa *= lithotype.softeningFactor;
      }
      return eGpa;
    }
  }

  /// ИТОГ 2: Модуль деформации E0, ГПа
  double get modulusDeformationE0Gpa {
    if (method == DeformationCalcMethod.indenters) {
      final validModuli = <double>[];
      for (final s in defSamples) {
        final res = calcSingleIndenterModuli(s);
        if (res != null) validModuli.add(res[1]);
      }
      if (validModuli.isNotEmpty) {
        return validModuli.reduce((a, b) => a + b) / validModuli.length;
      }
      return 0.0;
    } else {
      final e = modulusYoungEGpa;
      if (e <= 0) return 0.0;
      final por = porosityPercent ?? 2.0;
      final kElastic = (lithotype.kElasticBase - 0.012 * por).clamp(0.45, 0.95);
      return e * kElastic;
    }
  }

  /// ИТОГ 3: Коэффициент Пуассона nu (упругий)
  double get poissonNu {
    final por = porosityPercent ?? 1.5;
    final nu = lithotype.nu0 * (1.0 - 0.008 * por);
    return nu.clamp(0.12, 0.42);
  }

  /// ИТОГ 4: Коэффициент поперечной деформации mu (полный, с учетом остаточных деформаций)
  double get transverseStrainMu {
    final e = modulusYoungEGpa;
    final e0 = modulusDeformationE0Gpa;
    final nu = poissonNu;
    if (e <= 0 || e0 <= 0) return nu + 0.02;

    final plasticShare = (1.0 - (e0 / e)).clamp(0.0, 0.6);
    final mu = nu + 0.16 * plasticShare;
    return mu.clamp(nu, 0.48);
  }

  bool get hasValidResult => modulusYoungEGpa > 0 && modulusDeformationE0Gpa > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'cipher': cipher,
        'borehole': borehole,
        'interval': interval,
        'lithotypeId': lithotypeId,
        'condition': condition,
        'method': method.name,
        'indenterRadiusMm': indenterRadiusMm,
        'frameComplianceMmPerKn': frameComplianceMmPerKn,
        'rhoDGcm3': rhoDGcm3,
        'rhoSGcm3': rhoSGcm3,
        'breakSamples': breakSamples.map((e) => e.toJson()).toList(),
        'manualAvgLoadKn': manualAvgLoadKn,
        'manualAvgAreaCm2': manualAvgAreaCm2,
        'manualRcMpa': manualRcMpa,
        'defSamples': defSamples.map((e) => e.toJson()).toList(),
        'protoDropsN': protoDropsN,
        'protoDustHeightMm': protoDustHeightMm,
      };

  factory DeformationRecord.fromJson(Map<String, dynamic> json) => DeformationRecord(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        cipher: json['cipher'] as String? ?? '',
        borehole: json['borehole'] as String? ?? '',
        interval: json['interval'] as String? ?? '',
        lithotypeId: json['lithotypeId'] as String? ?? 'gabbro_diabase',
        condition: json['condition'] as String? ?? 'n',
        method: json['method'] == 'protodyakonov'
            ? DeformationCalcMethod.protodyakonov
            : DeformationCalcMethod.indenters,
        indenterRadiusMm: (json['indenterRadiusMm'] as num?)?.toDouble() ?? 15.0,
        frameComplianceMmPerKn: (json['frameComplianceMmPerKn'] as num?)?.toDouble() ?? 0.0015,
        rhoDGcm3: (json['rhoDGcm3'] as num?)?.toDouble(),
        rhoSGcm3: (json['rhoSGcm3'] as num?)?.toDouble(),
        breakSamples: (json['breakSamples'] as List<dynamic>?)
                ?.map((e) => IndenterBreakSample.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        manualAvgLoadKn: (json['manualAvgLoadKn'] as num?)?.toDouble(),
        manualAvgAreaCm2: (json['manualAvgAreaCm2'] as num?)?.toDouble(),
        manualRcMpa: (json['manualRcMpa'] as num?)?.toDouble(),
        defSamples: (json['defSamples'] as List<dynamic>?)
                ?.map((e) => IndenterDeformationSample.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        protoDropsN: (json['protoDropsN'] as num?)?.toInt() ?? 5,
        protoDustHeightMm: (json['protoDustHeightMm'] as num?)?.toDouble() ?? 0.0,
      );
}

class DeformationStorageService {
  static const String _key = 'rockarea_deformation_records';

  static Future<List<DeformationRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => DeformationRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecord(DeformationRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getRecords();
    final idx = list.indexWhere((r) => r.id == record.id);
    if (idx != -1) {
      list[idx] = record;
    } else {
      list.insert(0, record);
    }
    await prefs.setString(_key, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  static Future<void> deleteRecord(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getRecords();
    list.removeWhere((r) => r.id == id);
    await prefs.setString(_key, jsonEncode(list.map((r) => r.toJson()).toList()));
  }
}
