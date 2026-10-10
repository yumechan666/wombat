class RecipeSpec {
  const RecipeSpec(this.id, this.label, this.cube, this.hint);

  final String id;
  final String label;
  final String cube;
  final String hint;
}

const recipes = <RecipeSpec>[
  RecipeSpec('earth', 'Tanah', 'earth_cube', 'Tumpuk dan tekan pelat'),
  RecipeSpec('sticky', 'Lengket', 'sticky_cube', 'Menempel pada dinding'),
  RecipeSpec('spore', 'Spora', 'spore_cube', 'Menerangi kegelapan'),
  RecipeSpec('blast', 'Peledak', 'blast_cube', 'Meledak setelah 3 detik'),
  RecipeSpec('iron', 'Besi', 'iron_cube', 'Tak tergoyahkan angin'),
  RecipeSpec('ice', 'Es', 'ice_cube', 'Meluncur sampai menabrak'),
  RecipeSpec('mirror', 'Cermin', 'mirror_cube', 'Memantulkan sinar'),
  RecipeSpec('sand', 'Pasir', 'sand_cube', 'Pijakan cepat yang rapuh'),
  RecipeSpec('battery', 'Baterai', 'battery_cube', 'Menghidupkan mesin'),
  RecipeSpec('obsidian', 'Obsidian', 'obsidian_cube', 'Mengapung di lava'),
];

RecipeSpec recipeById(String id) => recipes.firstWhere(
  (recipe) => recipe.id == id,
  orElse: () => recipes.first,
);

class PickupSpec {
  const PickupSpec(this.id, this.x, this.y, {this.requires});

  final String id;
  final double x;
  final double y;
  final String? requires;
}

class LinkSpec {
  const LinkSpec(
    this.to,
    this.spawn, {
    this.requires = const [],
    this.requiresBoss,
  });

  final String to;
  final double spawn;
  final List<String> requires;
  final String? requiresBoss;
}

class ChallengeSpec {
  const ChallengeSpec(
    this.props,
    this.requirement,
    this.hint,
    this.fxSheet,
    this.fx,
  );

  final List<String> props;
  final String requirement;
  final String hint;
  final String fxSheet;
  final String fx;
}

class AreaSpec {
  const AreaSpec({
    required this.id,
    required this.index,
    required this.name,
    required this.shortName,
    required this.background,
    required this.terrain,
    required this.recipe,
    required this.holes,
    required this.roots,
    required this.links,
    required this.obstacles,
    required this.challenge,
    this.termites = const [],
    this.extraPlatforms = const [],
    this.hazard,
    this.dark = false,
    this.wind = false,
    this.conveyor = false,
    this.stickyWall,
    this.breakable,
    this.plate,
    this.mirrorSocket,
    this.machineSocket,
    this.npc,
    this.enemyType,
    this.enemySheet,
    this.enemyAnimation,
    this.enemyFlying = false,
    this.boss,
    this.finale,
  });

  final String id;
  final int index;
  final String name;
  final String shortName;
  final String background;
  final String terrain;
  final String recipe;
  final List<List<double>> holes;
  final List<PickupSpec> roots;
  final List<PickupSpec> termites;
  final List<List<double>> extraPlatforms;
  final String? hazard;
  final bool dark;
  final bool wind;
  final bool conveyor;
  final double? stickyWall;
  final List<double>? breakable;
  final List<double>? plate;
  final List<double>? mirrorSocket;
  final List<double>? machineSocket;
  final String? npc;
  final String? enemyType;
  final String? enemySheet;
  final String? enemyAnimation;
  final bool enemyFlying;
  final String? boss;
  final List<double>? finale;
  final Map<String, LinkSpec?> links;
  final List<String> obstacles;
  final ChallengeSpec challenge;
}

const _forestChallenge = ChallengeSpec(
  ['forest_root_bridge', 'forest_seed_bell'],
  'reflect',
  'Pantulkan biji ke lonceng akar',
  'AREA_FX_A',
  'forest_seed_rain',
);
const _bogChallenge = ChallengeSpec(
  ['bog_resin_valve', 'bog_lily_anchor'],
  'sticky',
  'Tempel Kubus Lengket pada katup',
  'AREA_FX_A',
  'bog_resin_splash',
);
const _caveChallenge = ChallengeSpec(
  ['cave_spore_lantern', 'cave_shadow_nest'],
  'spore',
  'Dekatkan Kubus Spora untuk menyalakan lorong',
  'AREA_FX_A',
  'cave_light_pulse',
);
const _mineChallenge = ChallengeSpec(
  ['mine_fuse_pillar', 'mine_rail_switch'],
  'blast',
  'Ledakkan Kubus Peledak di pilar sekering',
  'AREA_FX_A',
  'mine_fuse_burst',
);
const _peaksChallenge = ChallengeSpec(
  ['peaks_wind_gate', 'peaks_iron_anchor'],
  'iron',
  'Kunci angin dengan Kubus Besi',
  'AREA_FX_B',
  'peak_gust_burst',
);
const _iceChallenge = ChallengeSpec(
  ['ice_slide_bumper', 'ice_crack_switch'],
  'ice',
  'Luncurkan Kubus Es ke bumper',
  'AREA_FX_B',
  'ice_shatter',
);
const _templeChallenge = ChallengeSpec(
  ['temple_prism_socket', 'temple_sun_target'],
  'mirror',
  'Pasang Kubus Cermin pada prisma',
  'AREA_FX_B',
  'temple_beam_turn',
);
const _desertChallenge = ChallengeSpec(
  ['desert_sink_marker', 'desert_crumble_totem'],
  'burrow',
  'Gali tepat di bawah penanda pasir',
  'AREA_FX_B',
  'desert_sink',
);
const _factoryChallenge = ChallengeSpec(
  ['factory_power_node', 'factory_belt_switch'],
  'battery',
  'Hubungkan Kubus Baterai ke node',
  'AREA_FX_C',
  'factory_power_chain',
);
const _volcanoChallenge = ChallengeSpec(
  ['volcano_raft_lock', 'volcano_lava_valve'],
  'obsidian',
  'Kunci Kubus Obsidian menjadi rakit',
  'AREA_FX_C',
  'volcano_raft_lock',
);

const areas = <AreaSpec>[
  AreaSpec(
    id: 'forest',
    index: 0,
    name: 'Hutan Eucalyptus Induk',
    shortName: 'Eucalyptus',
    background: 'BG_FOREST',
    terrain: 'forest_soil',
    recipe: 'earth',
    holes: [
      [620, 730],
    ],
    roots: [
      PickupSpec('f1', 2500, 375),
      PickupSpec('f2', 9600, 335),
      PickupSpec('f3', 16600, 540, requires: 'sticky'),
    ],
    termites: [PickupSpec('ft', 9400, 440)],
    plate: [505, 560],
    npc: 'tinka',
    enemyType: 'leaf_beetle',
    enemySheet: 'ENEMY_SHEET_1',
    enemyAnimation: 'leaf_beetle_move',
    links: {
      'left': LinkSpec('cave', _rightEdgeSpawn),
      'right': LinkSpec('bog', 90),
    },
    obstacles: ['fallen_log', 'thorn_bush'],
    challenge: _forestChallenge,
  ),
  AreaSpec(
    id: 'bog',
    index: 1,
    name: 'Rawa Lumut Lengket',
    shortName: 'Rawa Lumut',
    background: 'BG_BOG',
    terrain: 'bog_moss',
    recipe: 'sticky',
    holes: [
      [440, 570],
      [980, 1120],
    ],
    hazard: 'bog',
    stickyWall: 890,
    extraPlatforms: [
      [875, 300, 55, 280],
      [1010, 350, 160, 30],
    ],
    roots: [PickupSpec('b1', 4300, 535), PickupSpec('b2', 14900, 295)],
    termites: [PickupSpec('bt', 9400, 385)],
    enemyType: 'bog_leech',
    enemySheet: 'ENEMY_SHEET_1',
    enemyAnimation: 'bog_leech_move',
    links: {
      'left': LinkSpec('forest', _rightEdgeSpawn),
      'right': LinkSpec('temple', 90, requires: ['sticky', 'ice']),
    },
    obstacles: ['sinking_lily', 'thorn_bush'],
    challenge: _bogChallenge,
  ),
  AreaSpec(
    id: 'cave',
    index: 2,
    name: 'Gua Jamur Bercahaya',
    shortName: 'Gua Spora',
    background: 'BG_CAVE',
    terrain: 'cave_stone',
    recipe: 'spore',
    holes: [
      [760, 870],
    ],
    dark: true,
    roots: [
      PickupSpec('c1', 2500, 535),
      PickupSpec('c2', 9600, 335),
      PickupSpec('c3', 16600, 420, requires: 'spore'),
    ],
    enemyType: 'cave_spider',
    enemySheet: 'ENEMY_SHEET_2',
    enemyAnimation: 'cave_spider_move',
    links: {
      'left': LinkSpec('mine', _rightEdgeSpawn, requires: ['spore']),
      'right': LinkSpec('forest', 90),
    },
    obstacles: ['stalactite', 'fallen_log'],
    challenge: _caveChallenge,
  ),
  AreaSpec(
    id: 'mine',
    index: 3,
    name: 'Tambang Kristal Terbengkalai',
    shortName: 'Tambang Kristal',
    background: 'BG_MINE',
    terrain: 'mine_rock',
    recipe: 'blast',
    holes: [
      [500, 620],
    ],
    breakable: [930, 365, 55, 215],
    roots: [PickupSpec('m1', 4300, 535), PickupSpec('m2', 14900, 520)],
    termites: [PickupSpec('mt', 9400, 375)],
    enemyType: 'miner_bot',
    enemySheet: 'ENEMY_SHEET_2',
    enemyAnimation: 'miner_bot_move',
    links: {
      'left': LinkSpec('peaks', _rightEdgeSpawn, requires: ['blast']),
      'right': LinkSpec('cave', 90),
    },
    obstacles: ['mine_cart', 'stalactite'],
    challenge: _mineChallenge,
  ),
  AreaSpec(
    id: 'peaks',
    index: 4,
    name: 'Puncak Tebing Angin Puyuh',
    shortName: 'Puncak Angin',
    background: 'BG_PEAKS',
    terrain: 'peak_cliff',
    recipe: 'iron',
    holes: [
      [570, 700],
      [1260, 1370],
    ],
    wind: true,
    roots: [PickupSpec('p1', 4300, 535), PickupSpec('p2', 14900, 335)],
    enemyType: 'cliff_glider',
    enemySheet: 'ENEMY_SHEET_3',
    enemyAnimation: 'cliff_glider_move',
    enemyFlying: true,
    boss: 'eagle',
    links: {
      'left': LinkSpec('ice', _rightEdgeSpawn, requiresBoss: 'eagle'),
      'right': LinkSpec('mine', 90),
    },
    obstacles: ['wind_totem', 'thorn_bush'],
    challenge: _peaksChallenge,
  ),
  AreaSpec(
    id: 'ice',
    index: 5,
    name: 'Hutan Pinus & Danau Beku',
    shortName: 'Danau Beku',
    background: 'BG_ICE',
    terrain: 'snow_ice',
    recipe: 'ice',
    holes: [
      [450, 720],
      [1090, 1260],
    ],
    hazard: 'icewater',
    roots: [
      PickupSpec('i1', 2500, 520),
      PickupSpec('i2', 9600, 520),
      PickupSpec('i3', 16600, 335),
    ],
    enemyType: 'frost_dingo',
    enemySheet: 'ENEMY_SHEET_3',
    enemyAnimation: 'frost_dingo_move',
    links: {
      'left': LinkSpec('temple', _rightEdgeSpawn, requires: ['sticky', 'ice']),
      'right': LinkSpec('peaks', 90),
    },
    obstacles: ['ice_spikes', 'fallen_log'],
    challenge: _iceChallenge,
  ),
  AreaSpec(
    id: 'temple',
    index: 6,
    name: 'Reruntuhan Kuil Pemantul',
    shortName: 'Kuil Cermin',
    background: 'BG_TEMPLE',
    terrain: 'temple_sandstone',
    recipe: 'mirror',
    holes: [
      [830, 940],
    ],
    mirrorSocket: [1130, 540],
    roots: [PickupSpec('t1', 2500, 535), PickupSpec('t2', 14900, 335)],
    npc: 'pip',
    enemyType: 'mirror_scarab',
    enemySheet: 'ENEMY_SHEET_4',
    enemyAnimation: 'mirror_scarab_move',
    links: {
      'left': LinkSpec('bog', _rightEdgeSpawn),
      'right': LinkSpec('desert', 90, requires: ['mirror']),
    },
    obstacles: ['laser_emitter', 'thorn_bush'],
    challenge: _templeChallenge,
  ),
  AreaSpec(
    id: 'desert',
    index: 7,
    name: 'Padang Pasir Isap',
    shortName: 'Pasir Isap',
    background: 'BG_DESERT',
    terrain: 'desert_sand',
    recipe: 'sand',
    holes: [
      [590, 760],
      [1130, 1260],
    ],
    hazard: 'sandpit',
    roots: [
      PickupSpec('d1', 2500, 520),
      PickupSpec('d2', 9600, 520),
      PickupSpec('d3', 16600, 335),
    ],
    enemyType: 'sand_lizard',
    enemySheet: 'ENEMY_SHEET_4',
    enemyAnimation: 'sand_lizard_move',
    boss: 'adder',
    links: {
      'left': LinkSpec('temple', _rightEdgeSpawn),
      'right': LinkSpec('factory', 90, requiresBoss: 'adder'),
    },
    obstacles: ['sand_vent', 'thorn_bush'],
    challenge: _desertChallenge,
  ),
  AreaSpec(
    id: 'factory',
    index: 8,
    name: 'Pabrik Penebangan Mesin',
    shortName: 'Pabrik Kayu',
    background: 'BG_FACTORY',
    terrain: 'factory_metal',
    recipe: 'battery',
    holes: [
      [510, 630],
      [970, 1090],
    ],
    machineSocket: [880, 540],
    conveyor: true,
    roots: [PickupSpec('x1', 4300, 535), PickupSpec('x2', 14900, 535)],
    termites: [PickupSpec('xt', 9400, 335)],
    enemyType: 'saw_drone',
    enemySheet: 'ENEMY_SHEET_5',
    enemyAnimation: 'saw_drone_move',
    enemyFlying: true,
    boss: 'taz',
    links: {
      'left': LinkSpec('desert', _rightEdgeSpawn),
      'right': LinkSpec('volcano', 90, requiresBoss: 'taz'),
    },
    obstacles: ['guarded_saw', 'mine_cart'],
    challenge: _factoryChallenge,
  ),
  AreaSpec(
    id: 'volcano',
    index: 9,
    name: 'Kawah Gunung Api Aktif',
    shortName: 'Kawah Inti',
    background: 'BG_VOLCANO',
    terrain: 'volcanic_basalt',
    recipe: 'obsidian',
    holes: [
      [420, 720],
      [920, 1260],
    ],
    hazard: 'lava',
    roots: [PickupSpec('v1', 4300, 500), PickupSpec('v2', 14900, 500)],
    finale: [19110, 330],
    enemyType: 'magma_gecko',
    enemySheet: 'ENEMY_SHEET_5',
    enemyAnimation: 'magma_gecko_move',
    links: {'left': LinkSpec('factory', _rightEdgeSpawn), 'right': null},
    obstacles: ['lava_cannon', 'ice_spikes'],
    challenge: _volcanoChallenge,
  ),
];

final areasById = <String, AreaSpec>{for (final area in areas) area.id: area};

const worldWidth = 19200.0;
const worldHeight = 680.0;
const chunkWidth = 1600.0;
const chunkCount = 12;

/// Spawn point when entering an area through its right edge.
const _rightEdgeSpawn = worldWidth - 100;

class SkinSpec {
  const SkinSpec(this.id, this.prefix, this.label, this.icon, this.shieldColor);

  final String id;
  final String prefix;
  final String label;
  final String icon;
  final int shieldColor;
}

const skins = <SkinSpec>[
  SkinSpec('bush', 'BUSH', 'Bush Ranger', 'bush_ranger', 0xff8bd36a),
  SkinSpec('spore', 'SPORE', 'Spore Scout', 'spore_scout', 0xff61f2df),
  SkinSpec('iron', 'IRON', 'Ironback Miner', 'ironback_miner', 0xffffc267),
  SkinSpec('frost', 'FROST', 'Frost Fuzz', 'frost_fuzz', 0xffb9f2ff),
  SkinSpec('sun', 'SUN', 'Sun Mirror', 'sun_mirror', 0xffffe18a),
  SkinSpec('dune', 'DUNE', 'Dune Drifter', 'dune_drifter', 0xffe5b264),
  SkinSpec('gear', 'GEAR', 'Gearbound', 'gearbound', 0xff62e5d0),
  SkinSpec('magma', 'MAGMA', 'Magma Pepper', 'magma_pepper', 0xffff7545),
  SkinSpec('quokka', 'QUOKKA', 'Quokka Fan', 'quokka_fan', 0xfff7df63),
  SkinSpec('root', 'ROOT', 'Root Guardian', 'root_guardian', 0xffa4e16d),
];

SkinSpec skinById(String id) =>
    skins.firstWhere((skin) => skin.id == id, orElse: () => skins.first);
