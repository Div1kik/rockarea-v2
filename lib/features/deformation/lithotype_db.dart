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
  });
}

class LithotypeDatabase {
  static const List<LithotypeProfile> profiles = [
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
    ),
  ];

  static LithotypeProfile getById(String id) {
    return profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => profiles.first,
    );
  }
}
