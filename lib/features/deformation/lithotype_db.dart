class LithotypeProfile {
  final String id;
  final String name;
  final String genesis;
  final double rhoSDefault;       // Плотность частиц по умолчанию, г/см3
  final double eSkeletonGpa;      // Модуль упругости бездефектного скелета, ГПа
  final double alphaLit;          // Корреляционный множитель E / Rc (если нет пористости)
  final double porosityDecayB;    // Коэффициент падения жесткости от пористости
  final double nu0;               // Базовый коэффициент Пуассона монолита
  final double kElasticBase;      // Базовое отношение E0 / E (коэффициент упругости)
  final double softeningFactor;   // Коэффициент размягчаемости при водонасыщении (w)
  final double kConversionBase;   // Базовый коэф. перехода Rc / sigma_p для монолита (ВНИМИ / ГОСТ Р 59958)

  const LithotypeProfile({
    required this.id,
    required this.name,
    required this.genesis,
    required this.rhoSDefault,
    required this.eSkeletonGpa,
    required this.alphaLit,
    required this.porosityDecayB,
    required this.nu0,
    required this.kElasticBase,
    required this.softeningFactor,
    required this.kConversionBase,
  });
}

class LithotypeDatabase {
  static const List<LithotypeProfile> profiles = [
    LithotypeProfile(
      id: 'unknown_rock',
      name: 'Неизвестная / Не определена (средние коэф.)',
      genesis: 'Не определен',
      rhoSDefault: 2.65,
      eSkeletonGpa: 55.0,
      alphaLit: 250.0,
      porosityDecayB: 0.052,
      nu0: 0.24,
      kElasticBase: 0.82,
      softeningFactor: 0.85,
      kConversionBase: 16.0,
    ),
    LithotypeProfile(
      id: 'gabbro_diabase',
      name: 'Габбро / Диабаз / Норит / Долерит',
      genesis: 'Интрузивная',
      rhoSDefault: 2.95,
      eSkeletonGpa: 84.0,
      alphaLit: 340.0,
      porosityDecayB: 0.050,
      nu0: 0.24,
      kElasticBase: 0.90,
      softeningFactor: 0.94,
      kConversionBase: 19.0,
    ),
    LithotypeProfile(
      id: 'granite',
      name: 'Гранит / Гранодиорит / Диорит',
      genesis: 'Интрузивная',
      rhoSDefault: 2.67,
      eSkeletonGpa: 68.0,
      alphaLit: 320.0,
      porosityDecayB: 0.055,
      nu0: 0.22,
      kElasticBase: 0.88,
      softeningFactor: 0.92,
      kConversionBase: 18.5,
    ),
    LithotypeProfile(
      id: 'basalt_andesite',
      name: 'Базальт / Андезит / Порфирит',
      genesis: 'Эффузивная',
      rhoSDefault: 2.85,
      eSkeletonGpa: 74.0,
      alphaLit: 300.0,
      porosityDecayB: 0.048,
      nu0: 0.23,
      kElasticBase: 0.86,
      softeningFactor: 0.90,
      kConversionBase: 17.5,
    ),
    LithotypeProfile(
      id: 'quartzite',
      name: 'Кварцит / Джеспилит / Роговик',
      genesis: 'Метаморфическая',
      rhoSDefault: 2.68,
      eSkeletonGpa: 78.0,
      alphaLit: 350.0,
      porosityDecayB: 0.060,
      nu0: 0.19,
      kElasticBase: 0.91,
      softeningFactor: 0.95,
      kConversionBase: 21.0,
    ),
    LithotypeProfile(
      id: 'gneiss_schist',
      name: 'Гнейс / Кристаллический сланец',
      genesis: 'Метаморфическая',
      rhoSDefault: 2.74,
      eSkeletonGpa: 58.0,
      alphaLit: 250.0,
      porosityDecayB: 0.055,
      nu0: 0.23,
      kElasticBase: 0.82,
      softeningFactor: 0.85,
      kConversionBase: 15.5,
    ),
    LithotypeProfile(
      id: 'skarn_serpentinite',
      name: 'Скарн / Пироксенит / Серпентинит',
      genesis: 'Метаморфическая',
      rhoSDefault: 2.90,
      eSkeletonGpa: 64.0,
      alphaLit: 270.0,
      porosityDecayB: 0.052,
      nu0: 0.25,
      kElasticBase: 0.84,
      softeningFactor: 0.87,
      kConversionBase: 16.5,
    ),
    LithotypeProfile(
      id: 'limestone_dolomite',
      name: 'Известняк / Доломит / Мрамор',
      genesis: 'Осадочная / Карбонатная',
      rhoSDefault: 2.72,
      eSkeletonGpa: 52.0,
      alphaLit: 220.0,
      porosityDecayB: 0.045,
      nu0: 0.27,
      kElasticBase: 0.80,
      softeningFactor: 0.82,
      kConversionBase: 14.0,
    ),
    LithotypeProfile(
      id: 'sandstone',
      name: 'Песчаник (крепкий цемент)',
      genesis: 'Осадочная',
      rhoSDefault: 2.66,
      eSkeletonGpa: 44.0,
      alphaLit: 190.0,
      porosityDecayB: 0.050,
      nu0: 0.25,
      kElasticBase: 0.76,
      softeningFactor: 0.78,
      kConversionBase: 13.5,
    ),
    LithotypeProfile(
      id: 'siltstone_argillite',
      name: 'Алевролит / Аргиллит / Мергель',
      genesis: 'Осадочная',
      rhoSDefault: 2.68,
      eSkeletonGpa: 28.0,
      alphaLit: 140.0,
      porosityDecayB: 0.065,
      nu0: 0.29,
      kElasticBase: 0.68,
      softeningFactor: 0.65,
      kConversionBase: 11.0,
    ),
  ];

  static LithotypeProfile getById(String id) {
    return profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => profiles.first,
    );
  }
}
