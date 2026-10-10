import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'asset_catalog.dart';
import 'audio.dart';
import 'world_data.dart';

// Gameplay, physics and rendering mirror the original JS game in `game js/`
// (physics.js, renderer.js, world.js). Flutter-only additions are persistence
// of in-area progress, the tutorial, audio files and the phone zoom.

const _playerWidth = 48.0;
const _playerHeight = 58.0;
const _cubeSize = 54.0;

class GameUiState {
  const GameUiState({
    this.loading = true,
    this.areaId = 'forest',
    this.health = 3,
    this.maxHealth = 3,
    this.rootCount = 0,
    this.selectedRecipe = 'earth',
    this.discovered = const {'forest'},
    this.unlockedRecipes = const {'earth'},
    this.upgrades = const {'metabolism': 0, 'rump': 0, 'senses': 0},
    this.termiteCount = 0,
    this.selectedSkin = 'bush',
    this.toast = '',
    this.areaName = '',
    this.prompt = 'Makan daun, lalu buat kubus di pelat kayu',
    this.bossName = '',
    this.pendingUpgrade = false,
    this.won = false,
    this.showTutorial = false,
    this.clueTitle = '',
    this.clueText = '',
    this.clueAvailable = false,
  });

  final bool loading;
  final String areaId;
  final int health;
  final int maxHealth;
  final int rootCount;
  final String selectedRecipe;
  final Set<String> discovered;
  final Set<String> unlockedRecipes;
  final Map<String, int> upgrades;
  final int termiteCount;
  final String selectedSkin;
  final String toast;

  /// Full area name shown briefly after entering an area (empty when hidden).
  final String areaName;
  final String prompt;
  final String bossName;
  final bool pendingUpgrade;
  final bool won;
  final bool showTutorial;

  /// Clue pop-up content (empty when the pop-up is closed).
  final String clueTitle;
  final String clueText;

  /// Whether a clue exists for the mission Momo is next to (lightbulb button).
  final bool clueAvailable;

  AreaSpec get area => areasById[areaId]!;
  RecipeSpec get recipe => recipeById(selectedRecipe);

  /// Value comparison so the HUD only rebuilds when something visible changed.
  bool sameAs(GameUiState other) =>
      loading == other.loading &&
      areaId == other.areaId &&
      health == other.health &&
      maxHealth == other.maxHealth &&
      rootCount == other.rootCount &&
      selectedRecipe == other.selectedRecipe &&
      termiteCount == other.termiteCount &&
      selectedSkin == other.selectedSkin &&
      toast == other.toast &&
      areaName == other.areaName &&
      prompt == other.prompt &&
      bossName == other.bossName &&
      pendingUpgrade == other.pendingUpgrade &&
      won == other.won &&
      showTutorial == other.showTutorial &&
      clueTitle == other.clueTitle &&
      clueText == other.clueText &&
      clueAvailable == other.clueAvailable &&
      setEquals(discovered, other.discovered) &&
      setEquals(unlockedRecipes, other.unlockedRecipes) &&
      mapEquals(upgrades, other.upgrades);
}

class _Player {
  double x = 180;
  double y = 580;
  double vx = 0;
  double vy = 0;
  int facing = 1;
  int shieldDir = 1;
  int health = 3;
  int maxHealth = 3;
  double invulnerable = 0;
  double actionLock = 0;
  double animationTime = 0;
  String animation = 'idle_breathe';
  bool onGround = true;
  bool burrowing = false;
  bool shielding = false;
}

class _Cube {
  _Cube(this.recipe, this.x, this.y, this.vx, this.vy, this.fuse);

  final String recipe;
  double x;
  double y;
  double vx;
  double vy;
  double fuse;
  double age = 0;
  double standTime = 0;
  bool dead = false;
  bool stuck = false;
}

class _Enemy {
  _Enemy({
    required this.type,
    required this.x,
    required this.y,
    required this.sheet,
    required this.animation,
    required this.homeX,
    required this.direction,
    this.flying = false,
    this.ranged = false,
    this.projectile = 'seed_pod',
    this.fireAnimation = '',
    this.fireTimer = 1,
    this.health = 1,
  });

  final String type;
  final String sheet;
  final String animation;
  final String fireAnimation;
  final String projectile;
  final bool flying;
  final bool ranged;
  final double homeX;
  double x;
  double y;
  double direction;
  double fireTimer;
  double firing = 0;
  double hit = 0;
  int health;
}

class _Projectile {
  _Projectile(this.x, this.y, this.vx, this.vy, this.type);

  double x;
  double y;
  double vx;
  double vy;
  double age = 0;
  final String type;
  String owner = 'enemy';
  bool dead = false;
}

class _Boss {
  _Boss(this.type, this.x, this.y, this.side);

  final String type;
  final String side;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  double health = 3;
  final double maxHealth = 3;
  double timer = 1.5;
  double hit = 0;
  String mode = 'hover';
  bool active = false;
}

class _Surface {
  const _Surface(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

/// A sprite-sheet effect (cube pop, explosion, parry spark, ...).
class _Effect {
  _Effect(this.sheet, this.animation, this.x, this.y, this.size);

  static const duration = 0.46;

  final String sheet;
  final String animation;
  final double x;
  final double y;
  final double size;
  double age = 0;
}

class _Obstacle {
  const _Obstacle(this.type, this.x, this.y, this.harmful);

  final String type;
  final double x;
  final double y;
  final bool harmful;
}

class CubewombatGame extends FlameGame {
  CubewombatGame();

  final ValueNotifier<GameUiState> uiState = ValueNotifier(const GameUiState());

  /// Asset loading progress (0..1) for the loading overlay.
  final ValueNotifier<double> loadProgress = ValueNotifier(0);

  final _player = _Player();
  final _input = <String, bool>{
    'left': false,
    'right': false,
    'down': false,
    'jump': false,
    'action': false,
    'skill': false,
  };
  final Set<String> _recipes = {'earth'};
  final Set<String> _roots = {};
  final Set<String> _termites = {};
  final Set<String> _discovered = {};
  final Set<String> _defeatedBosses = {};
  final Set<String> _completedGates = {};
  final Set<String> _completedChallenges = {};
  final Set<String> _completedPuzzles = {};
  final Set<String> _destroyedBreakables = {};
  final Set<String> _solvedGates = {};
  final Set<String> _solvedChallenges = {};
  final Map<String, double> _bossHealth = {};
  final Map<String, int> _enemyHealth = {};
  final Map<String, int> _upgrades = {'metabolism': 0, 'rump': 0, 'senses': 0};
  final List<_Cube> _cubes = [];
  final List<_Enemy> _enemies = [];
  final List<_Projectile> _projectiles = [];
  final List<_Effect> _effects = [];
  final List<_Surface> _surfaces = [];
  final List<_Surface> _playerSurfaces = [];
  final List<_Obstacle> _obstacles = [];
  final List<List<double>> _holes = [];
  final Set<String> _pressedThisFrame = {};
  final math.Random _random = math.Random();

  /// Most recently used skin ids (newest first), kept decoded in memory.
  final List<String> _recentSkins = [];
  bool _loadingSkin = false;
  static const _skinGroups = [
    'MOVE',
    'AIR',
    'CRAFT',
    'SHIELD',
    'BURROW',
    'DAMAGE',
  ];

  late GameAssetCatalog _assets;
  late SharedPreferences _preferences;
  AreaSpec _area = areasById['forest']!;
  _Boss? _boss;
  String _selectedRecipe = 'earth';
  String _skin = 'bush';
  String _costume = 'none';
  String _prompt = 'Makan daun, lalu buat kubus di pelat kayu';

  /// The centre hint is only shown for the first seconds after entering an area.
  static const _promptDuration = 5.0;
  double _promptTime = _promptDuration;
  String _toast = '';
  double _toastTime = 0;
  double _areaNameTime = 0;
  double _cubeCooldown = 0;
  double _elapsed = 0;
  int _reflections = 0;

  // Clues: seconds of "struggle" per mission; a pop-up opens past the
  // threshold, once per mission per session.
  static const _struggleThreshold = 12.0;
  final Map<String, double> _struggle = {};
  final Set<String> _cluesShown = {};
  (String, String)? _clue;

  // Camera / view. `_scale` maps world units to screen pixels.
  double _scale = 1;
  double _offsetY = 0;
  bool _viewReady = false;
  double _cameraX = 0;
  double _viewLeft = 0;
  double _viewRight = 560;
  double _shake = 0;

  double _checkpointX = 120;
  double _previousDirectionAt = 0;
  double _sprintUntil = 0;
  bool _puzzleSolved = false;
  bool _paused = false;
  bool _tutorialOpen = false;
  bool _loadingArea = false;
  bool _won = false;
  bool _breakableDestroyed = false;
  bool _showWinPanel = false;
  String? _pendingUpgrade;
  double _hudUpdateTimer = 0;
  double _saveTimer = 0;
  double _flushTimer = 0;
  bool _saveDirty = false;

  static const _basePlatforms = <List<double>>[
    [360, 475, 190, 34],
    [720, 430, 180, 34],
    [1110, 485, 180, 34],
    [1370, 390, 150, 34],
  ];
  static const _heightOffsets = [
    0.0,
    -28.0,
    18.0,
    -46.0,
    24.0,
    -12.0,
    -34.0,
    12.0,
    -54.0,
    26.0,
    -18.0,
    -38.0,
  ];
  static const _obstacleCount = 36;
  static const _tallObstacles = {'stalactite', 'wind_totem', 'lava_cannon'};
  static const _obstacleHazards = {
    'thorn_bush',
    'stalactite',
    'ice_spikes',
    'sand_vent',
    'guarded_saw',
    'lava_cannon',
  };
  static const _bossNames = {
    'eagle': 'MAHACAKAR',
    'adder': 'SISIK SUNYI',
    'taz': 'TAZ RIPSAW',
  };

  bool get isPaused =>
      _paused ||
      _tutorialOpen ||
      _loadingArea ||
      _pendingUpgrade != null ||
      _clue != null;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _preferences = await SharedPreferences.getInstance();
    final hasSavedProgress = _preferences.containsKey('cubewombat.save');
    _loadProgress();
    _assets = await GameAssetCatalog.load();
    await _loadAreaAssets(_area, _skin);
    _enterArea(
      _area.id,
      hasSavedProgress ? _player.x : 180,
      restorePosition: hasSavedProgress,
    );
    _loadingArea = false;
    unawaited(GameAudio.instance.startBgm('bgm.mp3'));
    _refreshUi(loading: false);
  }

  void _loadProgress() {
    final saved = _preferences.getString('cubewombat.save');
    if (saved == null) {
      _tutorialOpen =
          !(_preferences.getBool('cubewombat.tutorialSeen') ?? false);
      return;
    }
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final savedArea = data['area'] as String?;
      if (savedArea != null && areasById.containsKey(savedArea)) {
        _area = areasById[savedArea]!;
      }
      _recipes
        ..addAll(
          (data['recipes'] as List<dynamic>? ?? const ['earth']).cast<String>(),
        )
        ..add('earth');
      _roots.addAll(
        (data['roots'] as List<dynamic>? ?? const []).cast<String>(),
      );
      _termites.addAll(
        (data['termites'] as List<dynamic>? ?? const []).cast<String>(),
      );
      _discovered.addAll(
        (data['discovered'] as List<dynamic>? ?? [_area.id]).cast<String>(),
      );
      _defeatedBosses.addAll(
        (data['defeatedBosses'] as List<dynamic>? ?? const []).cast<String>(),
      );
      _completedGates.addAll(
        (data['completedGates'] as List<dynamic>? ?? const []).cast<String>(),
      );
      _completedChallenges.addAll(
        (data['completedChallenges'] as List<dynamic>? ?? const [])
            .cast<String>(),
      );
      _completedPuzzles.addAll(
        (data['completedPuzzles'] as List<dynamic>? ?? const []).cast<String>(),
      );
      _destroyedBreakables.addAll(
        (data['destroyedBreakables'] as List<dynamic>? ?? const [])
            .cast<String>(),
      );
      final bossHealth =
          data['bossHealth'] as Map<String, dynamic>? ?? const {};
      for (final entry in bossHealth.entries) {
        final health = (entry.value as num?)?.toDouble();
        if (health != null && health > 0 && health <= 3) {
          _bossHealth[entry.key] = health;
        }
      }
      final enemyHealth =
          data['enemyHealth'] as Map<String, dynamic>? ?? const {};
      for (final entry in enemyHealth.entries) {
        final health = (entry.value as num?)?.toInt();
        if (health != null && health >= 0 && health <= 2) {
          _enemyHealth[entry.key] = health;
        }
      }
      _selectedRecipe = _recipes.contains(data['selectedRecipe'])
          ? data['selectedRecipe'] as String
          : 'earth';
      _skin = skinById(data['skin'] as String? ?? 'bush').id;
      _costume = data['costume'] as String? ?? 'none';
      _won = data['won'] as bool? ?? false;
      _showWinPanel = false;
      _tutorialOpen =
          !(_preferences.getBool('cubewombat.tutorialSeen') ??
              data['tutorialSeen'] as bool? ??
              false);
      final upgrades = data['upgrades'] as Map<String, dynamic>? ?? const {};
      for (final key in _upgrades.keys) {
        _upgrades[key] = ((upgrades[key] as num?)?.toInt() ?? 0).clamp(0, 3);
      }
      final earnedChoices = _roots.length ~/ 4;
      final spentChoices = _upgrades.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      if (earnedChoices > spentChoices) _pendingUpgrade = 'choose';
      final position =
          data['playerPosition'] as Map<String, dynamic>? ?? const {};
      _player
        ..x = ((position['x'] as num?)?.toDouble() ?? 180)
            .clamp(0, worldWidth)
            .toDouble()
        ..y = ((position['y'] as num?)?.toDouble() ?? 520)
            .clamp(0, worldHeight + 70)
            .toDouble()
        ..health = ((data['health'] as num?)?.toInt() ?? _player.maxHealth)
            .clamp(1, _player.maxHealth)
        ..onGround = data['playerOnGround'] as bool? ?? true
        ..facing = ((data['playerFacing'] as num?)?.toInt() ?? 1) < 0 ? -1 : 1;
      _checkpointX = ((data['checkpointX'] as num?)?.toDouble() ?? 120)
          .clamp(0, worldWidth)
          .toDouble();
    } catch (_) {
      _area = areasById['forest']!;
      _tutorialOpen =
          !(_preferences.getBool('cubewombat.tutorialSeen') ?? false);
    }
  }

  /// Mark progress as changed. Writes are batched in [update] so frequent
  /// events (hits, pickups) do not hit the disk every frame.
  void _saveProgress() {
    _saveDirty = true;
  }

  Future<void> saveProgressNow() async {
    if (!isLoaded) return;
    _saveDirty = false;
    final data = <String, Object>{
      'version': 1,
      'area': _area.id,
      'recipes': _recipes.toList(),
      'selectedRecipe': _selectedRecipe,
      'roots': _roots.toList(),
      'termites': _termites.toList(),
      'discovered': _discovered.toList(),
      'defeatedBosses': _defeatedBosses.toList(),
      'completedGates': _completedGates.toList(),
      'completedChallenges': _completedChallenges.toList(),
      'completedPuzzles': _completedPuzzles.toList(),
      'destroyedBreakables': _destroyedBreakables.toList(),
      'bossHealth': _bossHealth,
      'enemyHealth': _enemyHealth,
      'upgrades': _upgrades,
      'health': _player.health,
      'playerPosition': {'x': _player.x, 'y': _player.y},
      'playerOnGround': _player.onGround,
      'playerFacing': _player.facing,
      'checkpointX': _checkpointX,
      'costume': _costume,
      'skin': _skin,
      'won': _won,
      'tutorialSeen': !_tutorialOpen,
    };
    try {
      await _preferences.setString('cubewombat.save', jsonEncode(data));
    } catch (_) {
      // A failed write must never crash the game; the autosave retries.
    }
  }

  // ---------------------------------------------------------------------------
  // Main loop (same order as updateGame() in physics.js)
  // ---------------------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) return;
    _updateCamera(math.min(dt, 0.05));
    if (isPaused) return;
    dt = dt.clamp(0, 0.033).toDouble();
    _elapsed += dt;
    _toastTime = math.max(0, _toastTime - dt);
    _areaNameTime = math.max(0, _areaNameTime - dt);
    _promptTime = math.max(0, _promptTime - dt);
    _cubeCooldown = math.max(0, _cubeCooldown - dt);
    _saveTimer += dt;
    _flushTimer += dt;

    _updatePuzzles();
    _updateChallenges();
    if (_pressedThisFrame.remove('action')) _handleAction();
    _updateCubes(dt);
    _updatePuzzles();
    _updateChallenges();
    _updatePlayer(dt);
    _trackStruggle(dt);
    _updateEnemies(dt);
    _updateRangedEnemies(dt);
    _updateProjectiles(dt);
    _updateBoss(dt);
    _collectPickups();
    _transitionIfNeeded();
    for (final effect in _effects) {
      effect.age += dt;
    }
    _effects.removeWhere((effect) => effect.age >= _Effect.duration);
    _checkFinale();

    _hudUpdateTimer += dt;
    if (_hudUpdateTimer >= 0.1) {
      _hudUpdateTimer = 0;
      _refreshUi(loading: false);
    }
    // Flush pending changes quickly; otherwise refresh the position every 5s.
    if ((_saveDirty && _flushTimer >= 0.5) || _saveTimer >= 5) {
      _saveTimer = 0;
      _flushTimer = 0;
      unawaited(saveProgressNow());
    }
  }

  void _refreshUi({required bool loading}) {
    final boss = _boss;
    final next = GameUiState(
      loading: loading,
      areaId: _area.id,
      health: _player.health,
      maxHealth: _player.maxHealth,
      rootCount: _roots.length,
      selectedRecipe: _selectedRecipe,
      discovered: Set.unmodifiable(_discovered),
      unlockedRecipes: Set.unmodifiable(_recipes),
      upgrades: Map.unmodifiable(_upgrades),
      termiteCount: _termites.length,
      selectedSkin: _skin,
      toast: _toastTime > 0 ? _toast : '',
      areaName: _areaNameTime > 0 ? _area.name : '',
      prompt: _promptTime > 0 ? _prompt : '',
      bossName: boss != null && boss.active && boss.health > 0
          ? (_bossNames[boss.type] ?? '')
          : '',
      pendingUpgrade: _pendingUpgrade != null,
      won: _showWinPanel,
      showTutorial: _tutorialOpen,
      clueTitle: _clue?.$1 ?? '',
      clueText: _clue?.$2 ?? '',
      clueAvailable: _clueKeyNearby() != null,
    );
    if (!next.sameAs(uiState.value)) uiState.value = next;
  }

  // ---------------------------------------------------------------------------
  // Public API used by the Flutter UI
  // ---------------------------------------------------------------------------

  void setInput(String name, bool active) {
    final old = _input[name] ?? false;
    if (active && !old && (name == 'action' || name == 'jump')) {
      _pressedThisFrame.add(name);
    }
    if (active && !old && (name == 'left' || name == 'right')) {
      // Double-tap a direction within 290ms to sprint for 800ms (input.js).
      final now = _elapsed;
      final direction = name == 'left' ? -1 : 1;
      if (_player.facing == direction && now - _previousDirectionAt < 0.29) {
        _sprintUntil = now + 0.8;
      }
      _player.facing = direction;
      _previousDirectionAt = now;
    }
    _input[name] = active;
  }

  void cycleRecipe() {
    final unlocked = recipes
        .where((recipe) => _recipes.contains(recipe.id))
        .toList();
    if (unlocked.isEmpty) return;
    GameAudio.instance.play('click.mp3');
    final current = unlocked.indexWhere(
      (recipe) => recipe.id == _selectedRecipe,
    );
    _selectedRecipe = unlocked[(current + 1) % unlocked.length].id;
    _showToast('Kubus ${recipeById(_selectedRecipe).label}', 1.2);
    _saveProgress();
  }

  void setPaused(bool value) {
    // The win panel keeps the game paused until "Lanjut menjelajah".
    _paused = value || _showWinPanel;
    _refreshUi(loading: uiState.value.loading);
  }

  Future<void> dismissTutorial() async {
    _tutorialOpen = false;
    await _preferences.setBool('cubewombat.tutorialSeen', true);
    await saveProgressNow();
    _refreshUi(loading: false);
  }

  void drawSkinPreview(ui.Canvas canvas, ui.Rect destination, String id) {
    if (!isLoaded) return;
    _assets.drawInCell(
      canvas,
      'SKIN_ICON_ATLAS',
      skinById(id).icon,
      destination,
    );
  }

  Future<void> travelTo(String areaId) async {
    if (!_discovered.contains(areaId) || !areasById.containsKey(areaId)) return;
    await _loadAndEnterArea(areaId, 170, unpause: true);
  }

  void chooseUpgrade(String branch) {
    if (_pendingUpgrade == null || !_upgrades.containsKey(branch)) return;
    if (_upgrades[branch]! < 3) _upgrades[branch] = _upgrades[branch]! + 1;
    GameAudio.instance.play('upgrade.mp3');
    _pendingUpgrade = null;
    _showToast(switch (branch) {
      'metabolism' => 'Pencernaan berevolusi',
      'rump' => 'Bokong makin tangguh',
      _ => 'Indra akar terbuka',
    }, 2.2);
    _saveProgress();
  }

  Future<void> chooseSkin(String id) async {
    final skin = skinById(id);
    if (_loadingSkin || skin.id == _skin) return;
    GameAudio.instance.play('click.mp3');
    _loadingSkin = true;
    _showToast('Menyiapkan ${skin.label}…', 2);
    try {
      await _loadAreaAssets(_area, skin.id);
      _skin = skin.id;
      _showToast('${skin.label} dipakai', 1.8);
      _saveProgress();
    } catch (_) {
      _showToast('Skin belum dapat dimuat', 1.8);
    } finally {
      _loadingSkin = false;
    }
  }

  /// Open the clue for the mission Momo is next to (lightbulb button).
  void showClue() {
    final key = _clueKeyNearby();
    if (key != null) _openClue(key);
  }

  void dismissClue() {
    _clue = null;
    _refreshUi(loading: false);
  }

  void continueAfterWin() {
    _paused = false;
    _showWinPanel = false;
    _won = true;
    _saveProgress();
    _refreshUi(loading: false);
  }

  // ---------------------------------------------------------------------------
  // Areas
  // ---------------------------------------------------------------------------

  void _enterArea(String id, double spawnX, {bool restorePosition = false}) {
    _area = areasById[id]!;
    _discovered.add(id);
    _player
      ..x = spawnX
      ..y = restorePosition ? _player.y : 520
      ..vx = 0
      ..vy = 0
      ..health = math.max(1, _player.health)
      ..burrowing = false;
    _cubes.clear();
    _projectiles.clear();
    _effects.clear();
    _solvedGates
      ..clear()
      ..addAll(_completedGates.where((gate) => gate.startsWith('$id-gate-')));
    _solvedChallenges
      ..clear()
      ..addAll(
        _completedChallenges.where(
          (challenge) => challenge.startsWith('$id-challenge-'),
        ),
      );
    _puzzleSolved = _completedPuzzles.contains(id);
    _breakableDestroyed = _destroyedBreakables.contains(id);
    if (!restorePosition) {
      _checkpointX = id == 'forest'
          ? 120
          : math.max(120, spawnX - 30).toDouble();
    }
    _areaNameTime = 2.4;
    _promptTime = _promptDuration;
    _prompt = id == 'forest' && _roots.isEmpty
        ? 'Makan daun, lalu buat kubus di pelat kayu'
        : _recipes.contains(_area.recipe)
        ? 'Kubus ${recipeById(_area.recipe).label}: ${recipeById(_area.recipe).hint}'
        : 'Cari makanan lokal untuk membuka Kubus ${recipeById(_area.recipe).label}';
    _enemies.clear();
    if (_area.enemyType != null) {
      for (var i = 0; i < 24; i++) {
        final x = 720 + i * 760.0;
        _enemies.add(
          _Enemy(
            type: _area.enemyType!,
            x: x,
            y: _area.enemyFlying ? 390 - (i.isOdd ? 70 : 0) : 580,
            homeX: x,
            direction: i.isOdd ? 1 : -1,
            sheet: _area.enemySheet!,
            animation: _area.enemyAnimation!,
            flying: _area.enemyFlying,
          ),
        );
      }
    }
    final ranged = _rangedProfile(_area.index);
    for (var i = 0; i < 12; i++) {
      final x = 1250 + i * 1500.0;
      _enemies.add(
        _Enemy(
          type: ranged.type,
          x: x,
          y: ranged.flying ? 390 - (i.isOdd ? 80 : 0) : 580,
          homeX: x,
          direction: -1,
          sheet: ranged.sheet,
          animation: ranged.idle,
          fireAnimation: ranged.fire,
          projectile: ranged.projectile,
          flying: ranged.flying,
          ranged: true,
          fireTimer: 0.8 + i * 0.45,
          health: 2,
        ),
      );
    }
    _boss = _area.boss != null && !_defeatedBosses.contains(_area.boss)
        ? _makeBoss(_area.boss!)
        : null;
    if (_boss != null && _bossHealth.containsKey(_boss!.type)) {
      _boss!.health = _bossHealth[_boss!.type]!;
    }
    for (final enemy in _enemies) {
      final health = _enemyHealth[_enemyProgressId(enemy)];
      if (health != null) enemy.health = health;
    }
    _buildWorld();
    _struggle.clear();
    _viewReady = false;
    _refreshUi(loading: false);
  }

  Set<String> _assetKeysForArea(AreaSpec area, String skinId) {
    final keys = <String>{
      area.background,
      'CUBE_ATLAS',
      'TERRAIN_ATLAS',
      'WORLD_ATLAS',
      'OBSTACLE_ATLAS',
      'AREA_PUZZLE_ATLAS',
      'PROJECTILE_ATLAS',
      'SKIN_ICON_ATLAS',
      'FX_CORE_SHEET',
      'FX_BURROW_SHEET',
      'FX_LATE_SHEET',
      area.challenge.fxSheet,
      _rangedProfile(area.index).sheet,
      for (final group in _skinGroups) 'SKIN_${skinById(skinId).prefix}_$group',
    };
    if (area.enemySheet != null) keys.add(area.enemySheet!);
    if (area.wind) keys.add('FX_NATURE_SHEET');
    switch (area.boss) {
      case 'eagle':
        keys.addAll(['BOSS_EAGLE_A', 'BOSS_EAGLE_B']);
      case 'adder':
        keys.addAll(['BOSS_ADDER_A', 'BOSS_ADDER_B']);
      case 'taz':
        keys.add('BOSS_TAZ_A');
    }
    return keys;
  }

  Future<void> _loadAreaAssets(AreaSpec area, String skinId) async {
    _recentSkins
      ..remove(skinId)
      ..insert(0, skinId);
    if (_recentSkins.length > 3) _recentSkins.removeLast();
    final keys = _assetKeysForArea(area, skinId);
    var finished = keys.where(_assets.isLoaded).length;
    loadProgress.value = finished / keys.length;
    await Future.wait(
      keys.map(
        (key) => _assets.loadKey(key).whenComplete(() {
          finished += 1;
          loadProgress.value = math.min(1.0, finished / keys.length);
        }),
      ),
    );
    // Keep recently used skins decoded so switching back is instant.
    _assets.retainOnly({
      ...keys,
      for (final id in _recentSkins)
        for (final group in _skinGroups) 'SKIN_${skinById(id).prefix}_$group',
    });
  }

  Future<void> _loadAndEnterArea(
    String areaId,
    double spawnX, {
    bool unpause = false,
  }) async {
    final nextArea = areasById[areaId];
    if (nextArea == null) return;
    _loadingArea = true;
    _refreshUi(loading: true);
    try {
      await _loadAreaAssets(nextArea, _skin);
      _enterArea(areaId, spawnX);
      // Leaving mid-fight must not carry the boss track into the next area.
      unawaited(GameAudio.instance.startBgm('bgm.mp3'));
      _saveProgress();
    } catch (_) {
      _showToast('Tema belum dapat dimuat', 2);
    } finally {
      _loadingArea = false;
      if (unpause) _paused = false;
      _refreshUi(loading: false);
    }
  }

  _Boss _makeBoss(String type) => switch (type) {
    'eagle' => _Boss(type, 720, 300, 'left'),
    'adder' =>
      _Boss(type, worldWidth - 430, 575, 'right')
        ..mode = 'listen'
        ..timer = 1.8,
    _ =>
      _Boss(type, worldWidth - 180, 575, 'right')
        ..mode = 'run'
        ..vx = -120
        ..timer = 1.2,
  };

  /// One ranged-enemy profile per area, as rangedProfile() in world.js.
  ({
    String type,
    String sheet,
    String idle,
    String fire,
    String projectile,
    bool flying,
  })
  _rangedProfile(int areaIndex) {
    if (areaIndex <= 1) {
      return (
        type: 'seed_cockatoo',
        sheet: 'RANGED_ENEMY_SHEET_1',
        idle: 'seed_cockatoo_idle',
        fire: 'seed_cockatoo_throw',
        projectile: areaIndex == 1 ? 'bog_bubble' : 'seed_pod',
        flying: true,
      );
    }
    if (areaIndex <= 3) {
      return (
        type: 'crystal_crab',
        sheet: 'RANGED_ENEMY_SHEET_1',
        idle: 'crystal_crab_idle',
        fire: 'crystal_crab_launch',
        projectile: 'crystal_shard',
        flying: false,
      );
    }
    if (areaIndex <= 5) {
      return (
        type: 'seed_cockatoo',
        sheet: 'RANGED_ENEMY_SHEET_1',
        idle: 'seed_cockatoo_idle',
        fire: 'seed_cockatoo_throw',
        projectile: areaIndex == 5 ? 'frost_orb' : 'pine_cone',
        flying: true,
      );
    }
    if (areaIndex <= 7) {
      return (
        type: 'sun_sentry',
        sheet: 'RANGED_ENEMY_SHEET_2',
        idle: 'sun_sentry_idle',
        fire: 'sun_sentry_fire',
        projectile: areaIndex == 7 ? 'sand_clod' : 'sun_disc',
        flying: true,
      );
    }
    return (
      type: 'scrap_cannon',
      sheet: 'RANGED_ENEMY_SHEET_2',
      idle: 'scrap_cannon_idle',
      fire: 'scrap_cannon_fire',
      projectile: areaIndex == 9 ? 'magma_orb' : 'gear_bolt',
      flying: false,
    );
  }

  void _buildWorld() {
    _surfaces.clear();
    _holes.clear();
    _obstacles.clear();
    for (var chunk = 0; chunk < chunkCount; chunk++) {
      for (var i = 0; i < _area.holes.length; i++) {
        final hole = _area.holes[i];
        final drift = ((chunk + i) % 3 - 1) * 55.0;
        _holes.add([
          hole[0] + chunk * chunkWidth + drift,
          hole[1] + chunk * chunkWidth + drift,
        ]);
      }
    }
    var cursor = 0.0;
    for (final hole in _holes) {
      if (hole[0] > cursor) {
        _surfaces.add(_Surface(cursor, 580, hole[0] - cursor, 100));
      }
      cursor = hole[1];
    }
    if (cursor < worldWidth) {
      _surfaces.add(_Surface(cursor, 580, worldWidth - cursor, 100));
    }
    for (var chunk = 0; chunk < chunkCount; chunk++) {
      for (var i = 0; i < _basePlatforms.length; i++) {
        final platform = _basePlatforms[i];
        final height = math.max(
          285.0,
          platform[1] + _heightOffsets[chunk] + (i.isOdd ? 12 : 0),
        );
        final x =
            platform[0] + chunk * chunkWidth + (i.isOdd ? chunk % 3 * 24 : 0);
        _surfaces.add(_Surface(x, height, platform[2], platform[3]));
      }
    }
    for (var chunk = 0; chunk < chunkCount; chunk++) {
      for (final platform in _area.extraPlatforms) {
        _surfaces.add(
          _Surface(
            platform[0] + chunk * chunkWidth,
            platform[1],
            platform[2],
            platform[3],
          ),
        );
      }
    }
    for (var index = 0; index < _obstacleCount; index++) {
      final type = _area.obstacles[index % _area.obstacles.length];
      _obstacles.add(
        _Obstacle(
          type,
          520 + index * 510.0,
          index % 3 == 1 ? 475 : 580,
          _obstacleHazards.contains(type),
        ),
      );
    }
  }

  ui.Offset _challengePosition(int index) =>
      ui.Offset(2400 + index * 3000, 580);

  // ---------------------------------------------------------------------------
  // Actions & cubes
  // ---------------------------------------------------------------------------

  void _handleAction() {
    // The leaf only reacts while it is visible (it hides once its recipe is
    // the selected one), so KUBUS still crafts next to an eaten leaf.
    final foodVisible =
        !_recipes.contains(_area.recipe) || _selectedRecipe != _area.recipe;
    if (foodVisible) {
      for (var i = 0; i < chunkCount; i++) {
        if (_near(_player.x, _player.y, i * chunkWidth + 270, 525, 95)) {
          _unlockRecipe(_area.recipe);
          return;
        }
      }
    }
    if (_area.npc != null &&
        _near(
          _player.x,
          _player.y,
          _area.npc == 'tinka' ? 1010 : 430,
          580,
          110,
        )) {
      if (_area.npc == 'tinka') {
        _showToast(
          _termites.isNotEmpty
              ? 'Tinka: Rayap emas membuat cakarmu makin kuat!'
              : 'Tinka: Bawa Rayap Emas dari ruang puzzle.',
          2.5,
        );
        if (_termites.length >= 2 && _upgrades['senses']! < 3) {
          _upgrades['senses'] = _upgrades['senses']! + 1;
        }
      } else {
        _costume = _costume == 'straw' ? 'goggles' : 'straw';
        _showToast(
          _costume == 'straw'
              ? 'Pip memberi Topi Jerami'
              : 'Pip memberi Kacamata Spora',
          2.5,
        );
      }
      _saveProgress();
      return;
    }
    _placeCube();
  }

  void _unlockRecipe(String id) {
    final isNew = _recipes.add(id);
    _selectedRecipe = id;
    _showToast(
      '${isNew ? 'Resep baru: ' : 'Dipilih: '}Kubus ${recipeById(id).label}',
      2.2,
    );
    _player
      ..actionLock = 0.45
      ..animation = 'eat'
      ..animationTime = 0;
    GameAudio.instance.play(isNew ? 'upgrade.mp3' : 'eat.mp3');
    _saveProgress();
  }

  void _placeCube() {
    if (_cubeCooldown > 0) return;
    final maxCubes = 1 + _upgrades['metabolism']!;
    while (_cubes.where((cube) => !cube.dead).length >= maxCubes) {
      _cubes.firstWhere((cube) => !cube.dead).dead = true;
    }
    final behind = _elapsed < _sprintUntil;
    final direction = behind ? -_player.facing : _player.facing;
    final recipe = _selectedRecipe;
    final cube = _Cube(
      recipe,
      _player.x + direction * 66,
      _player.y - 2,
      recipe == 'ice' ? direction * 320.0 : 0,
      -30,
      recipe == 'blast' ? 3 : double.infinity,
    );
    if (recipe == 'sticky' &&
        _area.stickyWall != null &&
        (cube.x - _area.stickyWall!).abs() < 120) {
      cube
        ..x = _area.stickyWall! - direction * 30
        ..y = math.max(220, _player.y - 35)
        ..vy = 0
        ..stuck = true;
    }
    _cubes.add(cube);
    _cubeCooldown = math.max(0.35, 0.9 * (1 - _upgrades['metabolism']! * 0.14));
    _player
      ..actionLock = 0.42
      ..animation = behind ? 'back_drop' : 'craft_cube'
      ..animationTime = 0;
    _addEffect('FX_CORE_SHEET', 'cube_pop', cube.x, cube.y - 22, 80);
    GameAudio.instance.play('craft.mp3');
  }

  void _updateCubes(double dt) {
    for (final cube in _cubes) {
      if (cube.dead) continue;
      cube
        ..age += dt
        ..fuse -= dt;
      if (cube.fuse <= 0) {
        _explode(cube);
        continue;
      }
      if (cube.stuck) continue;
      if (_area.wind && cube.recipe != 'iron') cube.vx += 75 * dt;
      if (_area.conveyor && cube.y > 550) cube.vx += 80 * dt;
      cube.vy += 1180 * dt;
      cube.x += cube.vx * dt;
      final previousY = cube.y;
      cube.y += cube.vy * dt;
      final lowerCubes = _cubes
          .where((other) => other != cube && !other.dead && other.y >= cube.y)
          .map(
            (other) => _Surface(
              other.x - _cubeSize / 2,
              other.y - _cubeSize,
              _cubeSize,
              _cubeSize,
            ),
          );
      final landed = _findLanding(cube.x, cube.y, previousY, _cubeSize - 8, [
        ..._surfaces,
        ...lowerCubes,
      ], cube.vy);
      if (landed != null) {
        cube
          ..y = landed.y
          ..vy = 0;
        if (cube.recipe != 'ice') cube.vx *= 0.45;
      }
      if (cube.recipe == 'obsidian' && _area.hazard == 'lava' && cube.y > 570) {
        cube
          ..y = 570
          ..vy = 0
          ..vx *= 0.92;
      }
      if (cube.x < 10 ||
          cube.x > worldWidth - 10 ||
          cube.y > worldHeight + 80) {
        cube.dead = true;
      }
    }
    _cubes.removeWhere((cube) => cube.dead && cube.age >= 0.3);
  }

  void _explode(_Cube cube) {
    cube.dead = true;
    _addEffect('FX_BURROW_SHEET', 'explosion', cube.x, cube.y - 25, 130);
    _addShake(8);
    GameAudio.instance.play('blast.mp3');
    if (_area.breakable != null &&
        !_breakableDestroyed &&
        _near(
          cube.x,
          cube.y,
          _area.breakable![0],
          _area.breakable![1] + 80,
          170,
        )) {
      _breakableDestroyed = true;
      _destroyedBreakables.add(_area.id);
      _saveProgress();
    }
    for (final enemy in _enemies) {
      if (enemy.health > 0 && _near(cube.x, cube.y, enemy.x, enemy.y, 150)) {
        _setEnemyHealth(enemy, 0);
        GameAudio.instance.play('enemy_die.mp3');
      }
    }
    if (_area.recipe == 'blast') {
      for (var gate = 0; gate < chunkCount - 1; gate++) {
        // JS measures to the gate top (y 360), which a cube on the ground can
        // never reach; measure near the ground so mine gates can open.
        if (_near(cube.x, cube.y, 1550 + gate * chunkWidth, 540, 170)) {
          _openGate(gate);
        }
      }
    }
    for (var i = 0; i < 6; i++) {
      final challenge = _challengePosition(i);
      if (_area.challenge.requirement == 'blast' &&
          _near(cube.x, cube.y, challenge.dx, challenge.dy, 175)) {
        _solveChallenge(i);
      }
    }
    final boss = _boss;
    if (boss != null &&
        _near(cube.x, cube.y, boss.x, boss.y, 165) &&
        (boss.type == 'taz' || boss.type == 'adder')) {
      _damageBoss(1);
    }
  }

  _Surface? _findLanding(
    double x,
    double y,
    double previousY,
    double width,
    Iterable<_Surface> surfaces,
    double vy,
  ) {
    if (vy < 0) return null;
    _Surface? landed;
    for (final surface in surfaces) {
      final left = x - width / 2;
      final right = x + width / 2;
      if (right <= surface.x + 4 || left >= surface.x + surface.width - 4) {
        continue;
      }
      if (previousY <= surface.y + 4 &&
          y >= surface.y &&
          (landed == null || surface.y < landed.y)) {
        landed = surface;
      }
    }
    return landed;
  }

  // ---------------------------------------------------------------------------
  // Puzzles & challenges
  // ---------------------------------------------------------------------------

  void _updatePuzzles() {
    var solved = _completedPuzzles.contains(_area.id);
    if (_area.plate case final plate?) {
      solved =
          solved ||
          _cubes.any((cube) => _near(cube.x, cube.y, plate[0], plate[1], 62));
    }
    if (_area.mirrorSocket case final socket?) {
      solved =
          solved ||
          _cubes.any(
            (cube) =>
                cube.recipe == 'mirror' &&
                _near(cube.x, cube.y, socket[0], socket[1], 95),
          );
    }
    if (_area.machineSocket case final socket?) {
      solved =
          solved ||
          _cubes.any(
            (cube) =>
                cube.recipe == 'battery' &&
                _near(cube.x, cube.y, socket[0], socket[1], 95),
          );
    }
    _puzzleSolved = solved;
    if (solved && _completedPuzzles.add(_area.id)) _saveProgress();
    if (_area.recipe == 'blast') return;
    for (var index = 0; index < chunkCount - 1; index++) {
      if (_solvedGates.contains('${_area.id}-gate-$index')) continue;
      final gateX = 1550 + index * chunkWidth;
      if (_cubes.any(
        (cube) =>
            !cube.dead &&
            cube.recipe == _area.recipe &&
            _near(cube.x, cube.y, gateX, 540, 105),
      )) {
        _openGate(index);
        _showToast('Gerbang ${recipeById(_area.recipe).label} terbuka', 1.7);
      }
    }
  }

  void _openGate(int index) {
    final gateId = '${_area.id}-gate-$index';
    if (!_solvedGates.add(gateId)) return;
    _completedGates.add(gateId);
    GameAudio.instance.play('gate.mp3');
    _saveProgress();
  }

  void _updateChallenges() {
    const cubeRequirements = {
      'sticky',
      'spore',
      'iron',
      'ice',
      'mirror',
      'battery',
      'obsidian',
    };
    final requirement = _area.challenge.requirement;
    for (var index = 0; index < 6; index++) {
      if (_solvedChallenges.contains('${_area.id}-challenge-$index')) continue;
      final challenge = _challengePosition(index);
      if (requirement == 'burrow' &&
          _player.burrowing &&
          _near(_player.x, _player.y, challenge.dx, challenge.dy, 90)) {
        _solveChallenge(index);
        continue;
      }
      if (cubeRequirements.contains(requirement)) {
        final cube = _cubes
            .where(
              (item) =>
                  !item.dead &&
                  item.recipe == requirement &&
                  _near(item.x, item.y, challenge.dx, challenge.dy, 105),
            )
            .firstOrNull;
        if (cube != null && (requirement != 'ice' || cube.vx.abs() > 80)) {
          _solveChallenge(index);
        }
      }
    }
  }

  void _solveChallenge(int index) {
    final id = '${_area.id}-challenge-$index';
    if (!_solvedChallenges.add(id)) return;
    _completedChallenges.add(id);
    final challenge = _challengePosition(index);
    _addEffect(
      _area.challenge.fxSheet,
      _area.challenge.fx,
      challenge.dx,
      challenge.dy - 55,
      135,
    );
    GameAudio.instance.play('challenge.mp3');
    unawaited(HapticFeedback.mediumImpact());
    _showToast('Teka-teki bioma terbuka', 1.8);
    _saveProgress();
  }

  // ---------------------------------------------------------------------------
  // Player
  // ---------------------------------------------------------------------------

  void _updatePlayer(double dt) {
    final player = _player;
    player
      ..invulnerable = math.max(0, player.invulnerable - dt)
      ..actionLock = math.max(0, player.actionLock - dt)
      ..animationTime += dt;
    final move =
        (_input['right'] == true ? 1 : 0) - (_input['left'] == true ? 1 : 0);
    if (move != 0) player.facing = move;
    final wasBurrowing = player.burrowing;
    player.burrowing =
        _input['down'] == true && _input['skill'] == true && player.onGround;
    if (!wasBurrowing && player.burrowing) {
      GameAudio.instance.play('burrow.mp3');
    }
    player.shielding =
        _input['skill'] == true && _input['down'] != true && !player.burrowing;
    if (player.shielding && move != 0) player.shieldDir = move;
    final sprinting = _elapsed < _sprintUntil && move != 0 && !player.burrowing;
    final speed =
        235 *
        (sprinting ? 1.55 : 1) *
        (player.shielding ? 0.78 : 1) *
        (_area.hazard == 'bog' && player.y > 560 ? 0.65 : 1);
    if (player.burrowing) {
      player.vx += (move * speed * 0.8 - player.vx) * math.min(1, dt * 9);
      player.vy = 0;
      _setAnimation('burrow_move');
    } else if (player.actionLock <= 0) {
      player.vx += (move * speed - player.vx) * math.min(1, dt * 12);
    } else {
      player.vx *= 0.9;
    }
    if (wasBurrowing && !player.burrowing) {
      player
        ..vy = -360
        ..animation = 'emerge_uppercut'
        ..animationTime = 0
        ..actionLock = 0.42;
      _addEffect('FX_BURROW_SHEET', 'uppercut_burst', player.x, player.y, 115);
      GameAudio.instance.play('burrow.mp3');
    }
    if (_pressedThisFrame.remove('jump') &&
        player.onGround &&
        !player.burrowing) {
      player
        ..vy = -520
        ..onGround = false
        ..animation = 'jump_takeoff'
        ..animationTime = 0;
      GameAudio.instance.play('jump.mp3');
    }
    if (_area.wind &&
        !_cubes.any(
          (cube) =>
              cube.recipe == 'iron' &&
              _near(cube.x, cube.y, player.x, player.y, 115),
        )) {
      player.vx += 120 * dt;
    }

    final previousY = player.y;
    player
      ..vy += 1180 * dt
      ..x += player.vx * dt
      ..y += player.vy * dt;
    final surfaces = _playerSurfaces
      ..clear()
      ..addAll(_surfaces);
    final cubeSurfaces = <_Surface, _Cube>{};
    for (final cube in _cubes) {
      if (cube.dead) continue;
      final surface = _Surface(
        cube.x - _cubeSize / 2,
        cube.y - _cubeSize,
        _cubeSize,
        _cubeSize,
      );
      cubeSurfaces[surface] = cube;
      surfaces.add(surface);
    }
    final wasAir = !player.onGround;
    final impact = player.vy;
    final landed = _findLanding(
      player.x,
      player.y,
      previousY,
      _playerWidth,
      surfaces,
      player.vy,
    );
    if (landed != null) {
      player
        ..y = landed.y
        ..vy = 0
        ..onGround = true;
      if (wasAir && impact > 220) GameAudio.instance.play('land.mp3');
      final standCube = cubeSurfaces[landed];
      if (standCube != null && standCube.recipe == 'sand') {
        standCube.standTime += dt;
        if (standCube.standTime > 2) {
          standCube.dead = true;
          _addEffect(
            'FX_LATE_SHEET',
            'sand_crumble',
            standCube.x,
            standCube.y,
            100,
          );
        }
      }
    } else {
      player.onGround = false;
    }

    final tutorial = _area.id == 'forest' && !_puzzleSolved;
    if (tutorial && player.x > 570 && player.x < 645) {
      player
        ..x = player.vx > 0 ? 569 : 646
        ..vx = 0;
      _prompt = 'Taruh Kubus Tanah di pelat kayu';
    } else if (_area.id == 'forest' && _puzzleSolved) {
      _prompt = 'Dua jalur terbuka — pilih rawa atau gua';
    }
    if (_area.breakable case final block? when !_breakableDestroyed) {
      if (player.x > block[0] - 30 && player.x < block[0] + 80) {
        player
          ..x = player.vx > 0 ? block[0] - 31 : block[0] + 81
          ..vx = 0;
        _prompt = 'Kubus Peledak dapat menghancurkan batu retak';
      }
    }
    for (var index = 0; index < chunkCount - 1; index++) {
      if (_solvedGates.contains('${_area.id}-gate-$index')) continue;
      final gateX = 1550 + index * chunkWidth;
      if (player.x > gateX - 32 && player.x < gateX + 66) {
        player
          ..x = player.vx > 0 ? gateX - 33 : gateX + 67
          ..vx = 0;
        _prompt =
            'Pasang Kubus ${recipeById(_area.recipe).label} di akar gerbang';
        break;
      }
    }
    for (var index = 0; index < 6; index++) {
      if (_solvedChallenges.contains('${_area.id}-challenge-$index')) continue;
      final gateX = _challengePosition(index).dx + 40;
      if (player.x > gateX - 32 && player.x < gateX + 65) {
        player
          ..x = player.vx > 0 ? gateX - 33 : gateX + 66
          ..vx = 0;
        _prompt = _area.challenge.hint;
        break;
      }
    }
    for (final obstacle in _obstacles) {
      if (!obstacle.harmful) continue;
      if (_overlaps(
        player.x - _playerWidth / 2,
        player.y - _playerHeight,
        _playerWidth,
        _playerHeight,
        obstacle.x - 36,
        obstacle.y - 55,
        72,
        55,
      )) {
        _damagePlayer(player.x < obstacle.x ? -1 : 1);
      }
    }
    for (var index = 0; index < chunkCount; index++) {
      final checkpointX = index * chunkWidth + 120;
      if (_near(player.x, player.y, checkpointX, 525, 66) &&
          checkpointX != _checkpointX) {
        _checkpointX = checkpointX;
        player.health = player.maxHealth;
        GameAudio.instance.play('checkpoint.mp3');
        _showToast('Sarang akar tersimpan', 1.4);
        _saveProgress();
      }
    }
    if (player.y > worldHeight + 70) {
      player.health -= 1;
      if (player.health <= 0) player.health = player.maxHealth;
      _respawn();
    }
    player.x = player.x.clamp(-10, worldWidth + 10).toDouble();
    if (player.actionLock <= 0) {
      if (player.shielding) {
        _setAnimation('shield_hold');
      } else if (player.burrowing) {
        _setAnimation('burrow_move');
      } else if (!player.onGround) {
        _setAnimation(player.vy < -80 ? 'jump_rise' : 'fall');
      } else if (player.vx.abs() > 235 * 1.15) {
        _setAnimation('sprint');
      } else if (player.vx.abs() > 20) {
        _setAnimation('walk');
      } else {
        _setAnimation('idle_breathe');
      }
    }
  }

  void _damagePlayer(int direction, {String? cause}) {
    if (_player.invulnerable > 0) return;
    if (cause == 'boss') _addStruggle('boss', 5);
    if (cause == 'projectile' && _reflections == 0) {
      _addStruggle('reflect', 3.4);
    }
    _player
      ..health -= 1
      ..invulnerable = 1.2
      ..vx = direction * 260
      ..vy = -250
      ..animation = 'hurt'
      ..animationTime = 0;
    GameAudio.instance.play('hurt.mp3');
    unawaited(HapticFeedback.mediumImpact());
    if (_player.health <= 0) _respawn();
    _saveProgress();
  }

  void _respawn() {
    _player
      ..health = _player.maxHealth
      ..x = _checkpointX + 45
      ..y = 500
      ..vx = 0
      ..vy = 0;
    // Respawn can happen while projectiles are being iterated. Mark transient
    // actors for removal and let their update loops prune them safely.
    for (final cube in _cubes) {
      cube.dead = true;
    }
    for (final projectile in _projectiles) {
      projectile.dead = true;
    }
    _showToast('Momo kembali ke sarang', 1.8);
    _saveProgress();
  }

  // ---------------------------------------------------------------------------
  // Enemies, projectiles, boss
  // ---------------------------------------------------------------------------

  void _updateEnemies(double dt) {
    final player = _player;
    for (final enemy in _enemies) {
      if (enemy.ranged || enemy.health <= 0) continue;
      enemy.hit = math.max(0, enemy.hit - dt);
      if (enemy.type == 'cave_spider' &&
          _cubes.any(
            (cube) =>
                cube.recipe == 'spore' &&
                _near(cube.x, cube.y, enemy.x, enemy.y, 190),
          )) {
        enemy.direction = enemy.x < player.x ? -1 : 1;
      }
      final speed = enemy.flying ? 65.0 : 50.0;
      enemy.x += enemy.direction * speed * dt;
      if ((enemy.x - enemy.homeX).abs() > 170) enemy.direction *= -1;
      if (enemy.flying) enemy.y += math.sin(_elapsed * 3 + enemy.homeX) * 0.6;
      if (!_overlaps(
        player.x - _playerWidth / 2,
        player.y - _playerHeight,
        _playerWidth,
        _playerHeight,
        enemy.x - 30,
        enemy.y - (enemy.flying ? 45 : 52),
        60,
        52,
      )) {
        continue;
      }
      final side = (enemy.x - player.x).sign.toInt();
      final enemySide = side == 0 ? 1 : side;
      if (player.shielding && enemySide == player.shieldDir) {
        enemy
          ..direction = enemySide.toDouble()
          ..x += enemySide * 52;
        if (_upgrades['rump']! >= 1) {
          _setEnemyHealth(enemy, 0);
          GameAudio.instance.play('enemy_die.mp3');
        }
        _addEffect('FX_CORE_SHEET', 'parry_spark', enemy.x, enemy.y - 25, 85);
        GameAudio.instance.play('shield.mp3');
      } else if (player.vy > 180 && player.y - 20 < enemy.y) {
        _setEnemyHealth(enemy, 0);
        GameAudio.instance.play('enemy_die.mp3');
        player.vy = -300;
      } else {
        _damagePlayer(player.x < enemy.x ? -1 : 1);
      }
    }
  }

  void _updateRangedEnemies(double dt) {
    final player = _player;
    for (final enemy in _enemies) {
      if (!enemy.ranged || enemy.health <= 0) continue;
      enemy
        ..hit = math.max(0, enemy.hit - dt)
        ..firing = math.max(0, enemy.firing - dt)
        ..direction = player.x < enemy.x ? -1 : 1;
      final distance = (player.x - enemy.x).abs();
      if (distance > 900) continue;
      if (distance < 620 && _reflections == 0) {
        _prompt =
            'Tahan SKILL sambil bergerak ke arah proyektil untuk memantulkannya';
      }
      enemy.fireTimer -= dt;
      if (enemy.fireTimer > 0) continue;
      enemy
        ..firing = 0.48
        ..fireTimer = 2.15 + (enemy.x % 3) * 0.18;
      final dx = player.x - enemy.x;
      final dy = player.y - 35 - (enemy.y - 45);
      final length = math.sqrt(dx * dx + dy * dy);
      final safeLength = length == 0 ? 1 : length;
      _projectiles.add(
        _Projectile(
          enemy.x + enemy.direction * 35,
          enemy.y - 48,
          dx / safeLength * 285,
          dy / safeLength * 285,
          enemy.projectile,
        ),
      );
    }
  }

  void _updateProjectiles(double dt) {
    final player = _player;
    for (final projectile in _projectiles) {
      if (projectile.dead) continue;
      projectile
        ..age += dt
        ..x += projectile.vx * dt
        ..y += projectile.vy * dt
        ..vy += 35 * dt;
      if (projectile.owner == 'enemy' &&
          _near(projectile.x, projectile.y, player.x, player.y - 30, 42)) {
        var attackSide = (projectile.x - player.x).sign.toInt();
        if (attackSide == 0) attackSide = -projectile.vx.sign.toInt();
        if (attackSide == 0) attackSide = 1;
        if (player.shielding && attackSide == player.shieldDir) {
          projectile
            ..owner = 'player'
            ..vx = attackSide * (360.0 + _upgrades['rump']! * 45)
            ..vy *= -0.15
            ..x = player.x + attackSide * 48;
          _reflections += 1;
          _addEffect(
            'FX_CORE_SHEET',
            'parry_spark',
            projectile.x,
            projectile.y,
            90,
          );
          GameAudio.instance.play('shield.mp3');
          unawaited(HapticFeedback.lightImpact());
        } else {
          projectile.dead = true;
          _damagePlayer(projectile.vx > 0 ? 1 : -1, cause: 'projectile');
        }
      }
      if (projectile.owner == 'player') _updateReflectedProjectile(projectile);
      if (projectile.age > 6 ||
          projectile.x < -100 ||
          projectile.x > worldWidth + 100 ||
          projectile.y > worldHeight + 100) {
        projectile.dead = true;
      }
    }
    _projectiles.removeWhere((projectile) => projectile.dead);
  }

  void _updateReflectedProjectile(_Projectile projectile) {
    if (_area.challenge.requirement == 'reflect') {
      for (var index = 0; index < 6; index++) {
        if (_solvedChallenges.contains('${_area.id}-challenge-$index')) {
          continue;
        }
        final challenge = _challengePosition(index);
        if (_near(projectile.x, projectile.y, challenge.dx, challenge.dy, 88)) {
          _solveChallenge(index);
          projectile.dead = true;
          return;
        }
      }
    }
    for (final enemy in _enemies) {
      if (!enemy.ranged || enemy.health <= 0) continue;
      if (_near(projectile.x, projectile.y, enemy.x, enemy.y - 35, 52)) {
        _setEnemyHealth(enemy, enemy.health - 1);
        enemy.hit = 0.5;
        projectile.dead = true;
        _addEffect('FX_CORE_SHEET', 'shield_impact', enemy.x, enemy.y - 35, 82);
        GameAudio.instance.play('shield.mp3');
        _prompt = 'Mantap! Pantulkan lagi sampai pelempar tumbang';
        return;
      }
    }
    for (final enemy in _enemies) {
      if (enemy.ranged || enemy.health <= 0) continue;
      if (_near(projectile.x, projectile.y, enemy.x, enemy.y, 48)) {
        _setEnemyHealth(enemy, 0);
        GameAudio.instance.play('enemy_die.mp3');
        projectile.dead = true;
        return;
      }
    }
    final boss = _boss;
    if (boss != null &&
        boss.health > 0 &&
        _near(projectile.x, projectile.y, boss.x, boss.y, 75)) {
      _damageBoss(1);
      projectile.dead = true;
    }
  }

  void _updateBoss(double dt) {
    final boss = _boss;
    if (boss == null || boss.health <= 0) return;
    final player = _player;
    final inArena = boss.side == 'left'
        ? player.x < 1450
        : player.x > worldWidth - 1450;
    if (!boss.active && !inArena) return;
    if (!boss.active) {
      boss.active = true;
      GameAudio.instance.startBgm('bgm_boss.mp3');
      _showToast(switch (boss.type) {
        'eagle' => 'Mahacakar turun dari angin!',
        'adder' => 'Tanah mendengar langkahmu…',
        _ => 'Taz Ripsaw mengejar!',
      }, 2.4);
    }
    boss
      ..timer -= dt
      ..hit = math.max(0, boss.hit - dt);
    if (boss.type == 'eagle') {
      if (boss.timer <= 0) {
        if (boss.mode == 'hover' || boss.mode == 'hurt') {
          boss
            ..mode = 'telegraph'
            ..timer = 0.75
            ..x = math.min(worldWidth - 120, player.x + 240)
            ..y = 260;
        } else if (boss.mode == 'telegraph') {
          boss
            ..mode = 'dive'
            ..timer = 0.8
            ..vx = (player.x - boss.x) / 0.75
            ..vy = (player.y - 35 - boss.y) / 0.75;
        } else {
          boss
            ..mode = 'hover'
            ..timer = 1.8
            ..y = 290
            ..vx = 0
            ..vy = 0;
        }
      }
      boss
        ..x += boss.vx * dt
        ..y += boss.vy * dt;
      if (boss.mode == 'dive' &&
          _near(boss.x, boss.y, player.x, player.y, 82)) {
        final side = (boss.x - player.x).sign.toInt();
        final bossSide = side == 0 ? 1 : side;
        if (player.shielding && bossSide == player.shieldDir) {
          _damageBoss(1);
          boss
            ..mode = 'hurt'
            ..timer = 1.1;
        } else {
          _damagePlayer(player.x < boss.x ? -1 : 1, cause: 'boss');
        }
      }
    } else if (boss.type == 'adder') {
      if (boss.timer <= 0) {
        boss.mode = boss.mode == 'listen'
            ? 'swim'
            : boss.mode == 'swim'
            ? 'emerge'
            : 'listen';
        boss.timer = boss.mode == 'emerge' ? 0.9 : 1.5;
        if (boss.mode == 'emerge') {
          boss.x = (player.x + player.facing * 70)
              .clamp(worldWidth - 1600, worldWidth - 120)
              .toDouble();
        }
      }
      if (boss.mode == 'swim') boss.x += (player.x - boss.x).sign * 100 * dt;
      boss.y = boss.mode == 'emerge' ? 555 : 610;
      if (boss.mode == 'emerge' &&
          _near(boss.x, boss.y, player.x, player.y, 80)) {
        _damagePlayer(player.x < boss.x ? -1 : 1, cause: 'boss');
      }
      if (player.animation == 'emerge_uppercut' &&
          _near(player.x, player.y, boss.x, boss.y, 105)) {
        _damageBoss(1);
      }
    } else {
      final target = player.x + 145;
      boss.vx += (target - boss.x).sign * 220 * dt;
      boss.vx = boss.vx.clamp(-240, 240).toDouble();
      boss
        ..x += boss.vx * dt
        ..y = 575
        ..mode = boss.hit > 0 ? 'spin' : 'run';
      for (final cube in _cubes) {
        if (!cube.dead && _near(cube.x, cube.y, boss.x, boss.y, 78)) {
          cube.dead = true;
          _damageBoss(1);
          boss.vx = 260;
        }
      }
      if (_near(boss.x, boss.y, player.x, player.y, 75)) {
        _damagePlayer(player.x < boss.x ? -1 : 1, cause: 'boss');
      }
    }
  }

  void _damageBoss(int amount) {
    final boss = _boss;
    if (boss == null || boss.hit > 0) return;
    boss
      ..health -= amount
      ..hit = 0.7
      ..mode = 'hurt';
    _addShake(10);
    unawaited(HapticFeedback.heavyImpact());
    GameAudio.instance.play('boss_hit.mp3');
    if (boss.health <= 0) {
      _defeatedBosses.add(boss.type);
      _bossHealth.remove(boss.type);
      GameAudio.instance.play('boss_die.mp3');
      GameAudio.instance.startBgm('bgm.mp3');
      _showToast(
        '${switch (boss.type) {
          'eagle' => 'Mahacakar',
          'adder' => 'Sisik Sunyi',
          _ => 'Taz Ripsaw',
        }} tumbang!',
        3,
      );
    } else {
      _bossHealth[boss.type] = boss.health;
    }
    _saveProgress();
  }

  String _enemyProgressId(_Enemy enemy) =>
      '${_area.id}:${enemy.ranged ? 'ranged' : 'melee'}:${enemy.homeX.round()}';

  void _setEnemyHealth(_Enemy enemy, int health) {
    enemy.health = math.max(0, health);
    _enemyHealth[_enemyProgressId(enemy)] = enemy.health;
    _saveProgress();
  }

  // ---------------------------------------------------------------------------
  // Pickups, transitions, finale
  // ---------------------------------------------------------------------------

  void _collectPickups() {
    for (final root in _area.roots) {
      if (_roots.contains(root.id) ||
          (root.requires != null && !_recipes.contains(root.requires))) {
        continue;
      }
      if (_near(_player.x, _player.y, root.x, root.y, 52)) {
        _roots.add(root.id);
        _addEffect('FX_BURROW_SHEET', 'root_pickup', root.x, root.y - 20, 110);
        GameAudio.instance.play('root.mp3');
        unawaited(HapticFeedback.lightImpact());
        _showToast('Akar Langka ${_roots.length}/24', 2);
        final earned = _roots.length ~/ 4;
        final spent = _upgrades.values.fold<int>(
          0,
          (sum, value) => sum + value,
        );
        if (earned > spent && _roots.length % 4 == 0) {
          _pendingUpgrade = 'choose';
        }
        _saveProgress();
      }
    }
    for (final termite in _area.termites) {
      if (!_termites.contains(termite.id) &&
          _near(_player.x, _player.y, termite.x, termite.y, 46)) {
        _termites.add(termite.id);
        GameAudio.instance.play('termite.mp3');
        _showToast('Rayap Emas ${_termites.length}', 1.7);
        _saveProgress();
      }
    }
  }

  void _checkFinale() {
    final finale = _area.finale;
    if (finale == null ||
        _won ||
        !_recipes.contains('obsidian') ||
        !_near(_player.x, _player.y, finale[0], finale[1], 85)) {
      return;
    }
    _won = true;
    _paused = true;
    _showWinPanel = true;
    GameAudio.instance.play('win.mp3');
    _saveProgress();
    _refreshUi(loading: false);
  }

  void _transitionIfNeeded() {
    final side = _player.x < 8
        ? 'left'
        : _player.x > worldWidth - 8
        ? 'right'
        : null;
    if (side == null) return;
    final link = _area.links[side];
    final canTravel =
        link != null &&
        link.requires.every(_recipes.contains) &&
        (link.requiresBoss == null ||
            _defeatedBosses.contains(link.requiresBoss));
    if (canTravel) {
      unawaited(_loadAndEnterArea(link.to, link.spawn));
      return;
    }
    _player
      ..x = side == 'left' ? 22 : worldWidth - 22
      ..vx = 0;
    _addStruggle('link-$side', 0.15);
    final missingBoss =
        link?.requiresBoss != null &&
        !_defeatedBosses.contains(link!.requiresBoss);
    final missingRecipe = link?.requires
        .where((recipe) => !_recipes.contains(recipe))
        .firstOrNull;
    _showToast(
      missingBoss
          ? 'Boss masih menjaga jalur'
          : missingRecipe != null
          ? 'Butuh Kubus ${recipeById(missingRecipe).label}'
          : 'Jalur belum terbuka',
      1.5,
    );
  }

  // ---------------------------------------------------------------------------
  // Clues
  // ---------------------------------------------------------------------------

  /// Unsolved obstacles that block progress, with their x position.
  Iterable<(String, double)> _barriers() sync* {
    if (_area.id == 'forest' && !_puzzleSolved) yield ('tutorial', 614);
    if (_area.breakable case final block? when !_breakableDestroyed) {
      yield ('breakable', block[0] + 27);
    }
    for (var i = 0; i < chunkCount - 1; i++) {
      if (!_solvedGates.contains('${_area.id}-gate-$i')) {
        yield ('gate-$i', 1550 + i * chunkWidth + 17);
      }
    }
    for (var i = 0; i < 6; i++) {
      if (!_solvedChallenges.contains('${_area.id}-challenge-$i')) {
        yield ('challenge-$i', _challengePosition(i).dx + 56);
      }
    }
  }

  String? _nearestBarrier(double range) {
    String? nearest;
    var best = range;
    for (final (key, x) in _barriers()) {
      final distance = (x - _player.x).abs();
      if (distance < best) {
        best = distance;
        nearest = key;
      }
    }
    return nearest;
  }

  String? _clueKeyNearby() {
    if (!isLoaded) return null;
    final barrier = _nearestBarrier(300);
    if (barrier != null) return barrier;
    final boss = _boss;
    if (boss != null && boss.active && boss.health > 0) return 'boss';
    return null;
  }

  /// Lingering next to an unsolved obstacle counts as struggling.
  void _trackStruggle(double dt) {
    final barrier = _nearestBarrier(240);
    if (barrier != null) _addStruggle(barrier, dt);
  }

  void _addStruggle(String key, double amount) {
    final total = (_struggle[key] ?? 0) + amount;
    _struggle[key] = total;
    if (total >= _struggleThreshold && _cluesShown.add('${_area.id}:$key')) {
      _openClue(key);
    }
  }

  void _openClue(String key) {
    _clue = _clueFor(key);
    GameAudio.instance.play('click.mp3');
    _refreshUi(loading: false);
  }

  String _recipeLabel(String id) => 'Kubus ${recipeById(id).label}';

  /// Where the leaf for [recipeId] grows, for "you don't have it yet" hints.
  String _recipeSource(String recipeId) {
    final area = areas.where((area) => area.recipe == recipeId).firstOrNull;
    if (area == null || area.id == _area.id) {
      return 'Makan daun di dekat sarang akar (ada di awal setiap bagian '
          'area): berdiri di dekat daun lalu tekan KUBUS.';
    }
    return 'Resepnya ada di ${area.shortName}: makan daun di sana dengan '
        'menekan KUBUS di dekat daun.';
  }

  /// Extra paragraph when the needed recipe is not unlocked yet.
  String _needRecipe(String recipeId) => _recipes.contains(recipeId)
      ? ''
      : '\n\nKamu belum punya ${_recipeLabel(recipeId)}. '
            '${_recipeSource(recipeId)}';

  (String, String) _clueFor(String key) {
    final recipe = _area.recipe;
    if (key == 'tutorial') {
      return (
        'Pelat kayu',
        'Gerbang ini terbuka kalau ada kubus di atas pelat kayu.\n\n'
            '1. Dekati daun (di dekat sarang) lalu tekan KUBUS untuk makan.\n'
            '2. Berdiri di samping pelat kayu, menghadap ke pelat.\n'
            '3. Tekan KUBUS lagi — Kubus Tanah akan jatuh di atas pelat.',
      );
    }
    if (key == 'breakable') {
      return (
        'Batu retak',
        'Batu retak hanya hancur oleh ledakan.\n\n'
            'Pilih Kubus Peledak lewat ikon kubus di atas, taruh di dekat batu '
            'dengan KUBUS, lalu mundur. Kubus meledak setelah 3 detik.'
            '${_needRecipe('blast')}',
      );
    }
    if (key.startsWith('gate-')) {
      final how = recipe == 'blast'
          ? 'Taruh Kubus Peledak tepat di depan gerbang, lalu mundur — '
                'ledakannya membuka gerbang.'
          : 'Pilih ${_recipeLabel(recipe)} lewat ikon kubus di atas, berdiri '
                'tepat di depan gerbang, lalu tekan KUBUS. Kubus harus '
                'mendarat di kaki gerbang (ikon kubus di gerbang menunjukkan '
                'jenisnya).';
      return ('Gerbang akar', '$how${_needRecipe(recipe)}');
    }
    if (key.startsWith('challenge-')) {
      final requirement = _area.challenge.requirement;
      final text = switch (requirement) {
        'reflect' =>
          'Lonceng akar berbunyi kalau terkena biji yang dipantulkan.\n\n'
              'Berdiri di dekat lonceng sampai burung pelempar datang. Saat '
              'biji meluncur, tahan SKILL sambil menghadap ke arah biji — biji '
              'akan terpantul. Pantulkan saat lonceng ada di antara kamu dan '
              'burung.',
        'burrow' =>
          'Penanda pasir hanya bereaksi kalau kamu menggali tepat di '
              'bawahnya.\n\nBerdiri di penanda, lalu tahan SKILL sambil menarik '
              'joystick ke bawah (atau Shift + S) untuk menggali.',
        'ice' =>
          'Kubus Es harus meluncur menabrak bumper, bukan diletakkan diam.'
              '\n\nMundur agak jauh dari bumper, menghadap ke arahnya, lalu '
              'tekan KUBUS. Kubus Es akan meluncur sendiri sampai menabrak.'
              '${_needRecipe('ice')}',
        'blast' =>
          'Pilar sekering harus diledakkan.\n\nTaruh Kubus Peledak di dekat '
              'pilar lalu mundur — meledak setelah 3 detik.'
              '${_needRecipe('blast')}',
        _ =>
          '${_area.challenge.hint}.\n\nPilih ${_recipeLabel(requirement)} '
              'lewat ikon kubus di atas, berdiri di depan alat teka-teki itu, '
              'lalu tekan KUBUS supaya kubus mendarat tepat di dekatnya.'
              '${_needRecipe(requirement)}',
      };
      return ('Teka-teki bioma', text);
    }
    if (key.startsWith('link-')) {
      final link = _area.links[key.substring(5)];
      if (link == null) {
        return (
          'Ujung dunia',
          'Tidak ada jalan ke arah ini. Coba jelajahi arah sebaliknya.',
        );
      }
      final bossId = link.requiresBoss;
      if (bossId != null && !_defeatedBosses.contains(bossId)) {
        final bossArea = areas.firstWhere((area) => area.boss == bossId);
        final side = bossId == 'eagle' ? 'kiri' : 'kanan';
        return (
          'Jalan dijaga boss',
          'Kalahkan boss dulu untuk membuka jalan ini. Boss menunggu di ujung '
              '$side ${bossArea.shortName}.',
        );
      }
      final lines = [
        for (final id in link.requires.where((id) => !_recipes.contains(id)))
          '• ${_recipeLabel(id)}: ${_recipeSource(id)}',
      ];
      return (
        'Jalan terkunci',
        'Jalan ini butuh resep yang belum kamu punya:\n\n${lines.join('\n')}',
      );
    }
    if (key == 'reflect') {
      return (
        'Musuh pelempar',
        'Tahan SKILL sambil menghadap ke arah proyektil yang datang untuk '
            'memantulkannya. Proyektil yang terpantul melukai pelempar — dua '
            'kali pantul dan ia tumbang.',
      );
    }
    return switch (_boss?.type) {
      'eagle' => (
        'Mahacakar',
        'Saat Mahacakar berhenti di udara lalu menukik, tahan SKILL menghadap '
            'ke arahnya. Tangkisan yang pas melukainya. Biji yang kamu '
            'pantulkan juga bisa mengenainya. Tiga kali kena, ia tumbang.',
      ),
      'adder' => (
        'Sisik Sunyi',
        'Sisik Sunyi bersembunyi di pasir lalu muncul di dekatmu. Gali (tahan '
            'SKILL + bawah) dan lepas tepat saat ia muncul untuk menyerang ke '
            'atas. Kubus Peledak di dekatnya juga melukainya.',
      ),
      _ => (
        'Taz Ripsaw',
        'Taz Ripsaw selalu mengejarmu. Taruh kubus di jalurnya — setiap kubus '
            'yang ia tabrak melukainya. Lompati dia saat terlalu dekat.',
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _addEffect(
    String sheet,
    String animation,
    double x,
    double y,
    double size,
  ) {
    _effects.add(_Effect(sheet, animation, x, y, size));
  }

  void _addShake(double amount) {
    _shake = math.max(_shake, amount);
  }

  void _setAnimation(String animation) {
    if (_player.animation != animation) {
      _player
        ..animation = animation
        ..animationTime = 0;
    }
  }

  void _showToast(String message, double duration) {
    _toast = message;
    _toastTime = duration;
    _refreshUi(loading: uiState.value.loading);
  }

  bool _near(double ax, double ay, double bx, double by, double radius) {
    final dx = ax - bx;
    final dy = ay - by;
    return dx * dx + dy * dy < radius * radius;
  }

  bool _overlaps(
    double ax,
    double ay,
    double aw,
    double ah,
    double bx,
    double by,
    double bw,
    double bh,
  ) => ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;

  // ---------------------------------------------------------------------------
  // Camera & rendering (renderer.js)
  // ---------------------------------------------------------------------------

  /// Screen heights below this count as a phone; the camera zooms in there.
  static const _phoneHeight = 600.0;

  void _updateCamera(double dt) {
    final width = size.x;
    final height = size.y;
    if (width <= 0 || height <= 0) return;
    final baseScale = math.min(
      width / 560,
      math.max(0.58, (height - 88) / worldHeight),
    );
    final phone = height < _phoneHeight;
    // On phones show ~430 world units of height instead of the whole 680, so
    // Momo and the world read larger; the camera then follows vertically.
    _scale = phone ? math.max(baseScale, height / 430) : baseScale;
    final viewWidth = width / _scale;
    final targetCamera = (_player.x - viewWidth * 0.42)
        .clamp(0, math.max(0, worldWidth - viewWidth))
        .toDouble();
    double targetOffset;
    if (phone) {
      // Ground sits just above the touch controls; rise when Momo (or an
      // active eagle) goes higher than the HUD allows.
      var top = _player.y - _playerHeight - 40;
      final boss = _boss;
      if (boss != null && boss.active && boss.health > 0) {
        top = math.min(top, boss.y - 160);
      }
      targetOffset = math.max(height - 70 - 580 * _scale, 86 - top * _scale);
    } else {
      targetOffset = height - 88 - worldHeight * _scale;
    }
    if (_viewReady) {
      final follow = math.min(1.0, dt * 5);
      _cameraX += (targetCamera - _cameraX) * follow;
      _offsetY += (targetOffset - _offsetY) * follow;
    } else {
      _cameraX = targetCamera;
      _offsetY = targetOffset;
      _viewReady = true;
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final width = size.x;
    final height = size.y;
    if (width <= 0 || height <= 0) return;
    if (!_viewReady) _updateCamera(0);
    final scale = _scale;
    _viewLeft = _cameraX - 120;
    _viewRight = _cameraX + width / scale + 120;

    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, width, height));
    _shake *= 0.84;
    if (_shake > 0.2) {
      canvas.translate(
        (_random.nextDouble() - 0.5) * _shake,
        (_random.nextDouble() - 0.5) * _shake,
      );
    }
    canvas.drawColor(const ui.Color(0xff163a3a), ui.BlendMode.src);
    if (isLoaded) {
      _drawBackground(canvas, width, height);
      canvas.save();
      canvas.translate(0, _offsetY);
      canvas.scale(scale, scale);
      canvas.translate(-_cameraX, 0);
      _drawWorld(canvas, width, height);
      for (final cube in _cubes) {
        if (!cube.dead) _drawCube(canvas, cube);
      }
      _drawEnemies(canvas);
      _drawProjectiles(canvas);
      _drawBoss(canvas);
      _drawPlayer(canvas);
      _drawEffects(canvas);
      if (_area.dark) _drawCaveDarkness(canvas, width, height);
      canvas.restore();
    }
    canvas.restore();
    super.render(canvas);
  }

  /// World y of the bottom screen edge.
  double _worldBottom(double height) => (height - _offsetY) / _scale;

  void _drawBackground(ui.Canvas canvas, double width, double height) {
    final image = _assets[_area.background]?.image;
    if (image == null) return;
    final imageRatio = image.width / image.height;
    final canvasRatio = width / height;
    var source = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    if (imageRatio > canvasRatio) {
      // Slow parallax: the background pans with the camera.
      final sourceWidth = image.height * canvasRatio;
      final range = math.max(1.0, image.width - sourceWidth);
      final sourceX =
          ((_cameraX / worldWidth) * (image.width - sourceWidth) * 0.6) % range;
      source = ui.Rect.fromLTWH(
        sourceX,
        0,
        sourceWidth,
        image.height.toDouble(),
      );
    } else {
      final sourceHeight = image.width / canvasRatio;
      source = ui.Rect.fromLTWH(
        0,
        math.max(0, image.height - sourceHeight),
        image.width.toDouble(),
        sourceHeight,
      );
    }
    final screen = ui.Rect.fromLTWH(0, 0, width, height);
    canvas.drawImageRect(
      image,
      source,
      screen,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    canvas.drawRect(
      screen,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset.zero,
          ui.Offset(0, height),
          const [
            ui.Color(0x1a081019),
            ui.Color(0x08080c12),
            ui.Color(0x5905070a),
          ],
          const [0, 0.65, 1],
        ),
    );
  }

  void _drawWorld(ui.Canvas canvas, double width, double height) {
    final scale = _scale;
    final bottom = _worldBottom(height);
    _drawHazards(canvas, bottom);
    final tileFrame = _assets['TERRAIN_ATLAS']?.frames[_area.terrain];
    for (final platform in _surfaces) {
      if (platform.x + platform.width < _viewLeft || platform.x > _viewRight) {
        continue;
      }
      _drawPlatform(canvas, platform, tileFrame != null);
    }

    final pulse = math.sin(_elapsed * 3) * 3;
    for (var i = 0; i < chunkCount; i++) {
      _drawWorldItem(
        canvas,
        'checkpoint_nest',
        i * chunkWidth + 120,
        580,
        86,
        86,
      );
    }
    if (!_recipes.contains(_area.recipe) || _selectedRecipe != _area.recipe) {
      for (var i = 0; i < chunkCount; i++) {
        _drawWorldItem(
          canvas,
          'leaf_food',
          i * chunkWidth + 270,
          525,
          58,
          58,
          bob: pulse * 0.35,
        );
      }
    }
    for (final root in _area.roots) {
      if (_roots.contains(root.id) ||
          (root.requires != null && !_recipes.contains(root.requires))) {
        continue;
      }
      _drawWorldItem(canvas, 'rare_root', root.x, root.y, 68, 76, bob: pulse);
    }
    for (final termite in _area.termites) {
      if (_termites.contains(termite.id)) continue;
      _drawWorldItem(
        canvas,
        'golden_termite',
        termite.x,
        termite.y,
        40,
        40,
        bob: pulse * 0.6,
      );
    }
    if (_area.plate case final plate?) {
      _drawWorldItem(canvas, 'pressure_plate', plate[0], plate[1] + 17, 82, 36);
    }
    if (_area.npc case final npc?) {
      _drawWorldItem(
        canvas,
        npc == 'tinka' ? 'tinka_echidna' : 'pip_quokka',
        npc == 'tinka' ? 1010 : 430,
        580,
        86,
        96,
      );
    }
    if (_area.id == 'forest' && !_puzzleSolved) {
      canvas.drawRect(
        const ui.Rect.fromLTWH(600, 380, 28, 200),
        ui.Paint()..color = const ui.Color(0xe0281e12),
      );
      _drawWorldItem(canvas, 'sealed_gate', 614, 490, 54, 54);
    }
    if (_area.breakable case final block? when !_breakableDestroyed) {
      canvas.drawRect(
        ui.Rect.fromLTWH(block[0], block[1], block[2], block[3]),
        ui.Paint()..color = const ui.Color(0xeb4e3e4e),
      );
      final crack = ui.Paint()
        ..color = const ui.Color(0xffc591d6)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 3 / scale;
      canvas.drawPath(
        ui.Path()
          ..moveTo(block[0] + 12, block[1] + 25)
          ..lineTo(block[0] + 38, block[1] + 105)
          ..lineTo(block[0] + 15, block[1] + 180),
        crack,
      );
    }
    if (_area.mirrorSocket case final socket?) {
      final path = ui.Path()
        ..moveTo(980, 300)
        ..lineTo(socket[0], socket[1] - 30);
      if (_puzzleSolved) path.lineTo(1310, 500);
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = const ui.Color(0xd958ffee)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = math.max(3 / scale, 4),
      );
    }
    if (_area.machineSocket case final socket?) {
      canvas.drawRect(
        ui.Rect.fromLTWH(socket[0] - 30, socket[1] - 45, 60, 45),
        ui.Paint()
          ..color = _puzzleSolved
              ? const ui.Color(0xff76ffe3)
              : const ui.Color(0xff5b4635),
      );
    }
    if (_area.finale case final finale?) {
      _drawWorldItem(
        canvas,
        'rare_root',
        finale[0],
        finale[1] + 190,
        190,
        240,
        bob: pulse * 0.25,
      );
    }
    for (final obstacle in _obstacles) {
      if (obstacle.x < _viewLeft - 60 || obstacle.x > _viewRight + 60) {
        continue;
      }
      final tall = _tallObstacles.contains(obstacle.type);
      final w = tall ? 72.0 : 92.0;
      final h = tall ? 108.0 : 76.0;
      _assets.drawInCell(
        canvas,
        'OBSTACLE_ATLAS',
        obstacle.type,
        ui.Rect.fromLTWH(obstacle.x - w / 2, obstacle.y - h, w, h),
      );
    }
    for (var index = 0; index < chunkCount - 1; index++) {
      if (_solvedGates.contains('${_area.id}-gate-$index')) continue;
      final x = 1550 + index * chunkWidth;
      if (x < _viewLeft - 100 || x > _viewRight + 100) continue;
      _assets.drawInCell(
        canvas,
        'OBSTACLE_ATLAS',
        'root_gate',
        ui.Rect.fromLTWH(x - 34, 360, 90, 220),
      );
      _assets.drawInCell(
        canvas,
        'CUBE_ATLAS',
        recipeById(_area.recipe).cube,
        ui.Rect.fromLTWH(x - 18, 500, 40, 40),
      );
    }
    for (var index = 0; index < 6; index++) {
      final challenge = _challengePosition(index);
      if (challenge.dx < _viewLeft - 120 || challenge.dx > _viewRight + 120) {
        continue;
      }
      final solved = _solvedChallenges.contains('${_area.id}-challenge-$index');
      _assets.drawInCell(
        canvas,
        'AREA_PUZZLE_ATLAS',
        _area.challenge.props[index % 2],
        ui.Rect.fromLTWH(challenge.dx - 48, challenge.dy - 100, 96, 100),
        alpha: solved ? 0.42 : 1,
      );
      if (!solved) {
        _assets.drawInCell(
          canvas,
          'OBSTACLE_ATLAS',
          'root_gate',
          ui.Rect.fromLTWH(challenge.dx + 40 - 34, 360, 90, 220),
        );
      }
    }
    if (_area.wind) {
      // Gusts drift in screen space (fixed pixel size), like renderer.js.
      for (var i = 0; i < 3; i++) {
        final screenX = ((_elapsed * 160 + i * 260) % (width + 220)) - 180;
        _assets.drawInCell(
          canvas,
          'FX_NATURE_SHEET',
          'wind_gust',
          ui.Rect.fromLTWH(
            _cameraX + screenX / scale,
            230 + i * 115,
            170 / scale,
            95 / scale,
          ),
          frameIndex: (_elapsed * 7).floor(),
        );
      }
    }
  }

  void _drawHazards(ui.Canvas canvas, double bottom) {
    final colors = switch (_area.hazard) {
      'lava' => const [
        ui.Color(0xffffb12b),
        ui.Color(0xffef4d22),
        ui.Color(0xff301323),
      ],
      'sandpit' => const [ui.Color(0xffe8b960), ui.Color(0xff7a3f35)],
      'bog' => const [ui.Color(0xff88a93b), ui.Color(0xff152a2b)],
      _ => const [ui.Color(0xff82d8e7), ui.Color(0xff174c71)],
    };
    final stops = colors.length == 3
        ? const [0.0, 0.25, 1.0]
        : const [0.0, 1.0];
    final wave = ui.Paint()
      ..color = _area.hazard == 'lava'
          ? const ui.Color(0xffffd36a)
          : const ui.Color(0xa6dcfff5)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3 / _scale;
    for (final hole in _holes) {
      final start = hole[0];
      final end = hole[1];
      if (end < _viewLeft || start > _viewRight) continue;
      final rect = ui.Rect.fromLTRB(start, 570, end, math.max(600, bottom));
      canvas.drawRect(
        rect,
        ui.Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            colors,
            stops,
          ),
      );
      final path = ui.Path();
      final step = 18 / _scale;
      for (var x = start; x <= end; x += step) {
        final y = 570 + math.sin((x * _scale + _elapsed * 80) * 0.035) * 3;
        if (x == start) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wave);
    }
  }

  /// Terrain tiles fill the whole platform (clipped), then a light top edge.
  void _drawPlatform(ui.Canvas canvas, _Surface platform, bool hasTiles) {
    final rect = ui.Rect.fromLTWH(
      platform.x,
      platform.y,
      platform.width,
      platform.height,
    );
    if (!hasTiles) {
      canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xff58462f));
      return;
    }
    final tile = math.max(42 / _scale, 64.0);
    final left = math.max(platform.x, _viewLeft - tile);
    final right = math.min(platform.x + platform.width, _viewRight + tile);
    canvas.save();
    canvas.clipRect(rect);
    // Keep tiles aligned to the platform origin while skipping offscreen ones.
    final firstX = platform.x + ((left - platform.x) / tile).floor() * tile;
    for (var x = firstX; x < right; x += tile) {
      for (var y = platform.y; y < platform.y + platform.height; y += tile) {
        _assets.drawInCell(
          canvas,
          'TERRAIN_ATLAS',
          _area.terrain,
          ui.Rect.fromLTWH(x, y, tile, tile),
        );
      }
    }
    canvas.restore();
    canvas.drawRect(
      ui.Rect.fromLTWH(
        platform.x,
        platform.y,
        platform.width,
        math.max(2 / _scale, 3),
      ),
      ui.Paint()..color = const ui.Color(0x2effffff),
    );
  }

  void _drawWorldItem(
    ui.Canvas canvas,
    String name,
    double x,
    double y,
    double width,
    double height, {
    double bob = 0,
  }) {
    if (x + width / 2 < _viewLeft || x - width / 2 > _viewRight) return;
    _assets.drawInCell(
      canvas,
      'WORLD_ATLAS',
      name,
      ui.Rect.fromLTWH(x - width / 2, y - height + bob, width, height),
    );
  }

  void _drawCube(ui.Canvas canvas, _Cube cube) {
    if (cube.recipe == 'spore') {
      final center = ui.Offset(cube.x, cube.y - 26);
      canvas.drawCircle(
        center,
        90,
        ui.Paint()
          ..shader = ui.Gradient.radial(center, 90, const [
            ui.Color(0x4753ffec),
            ui.Color(0x0053ffec),
          ]),
      );
    }
    final alpha =
        cube.recipe == 'blast' && cube.fuse < 1 && math.sin(_elapsed * 24) > 0
        ? 0.45
        : 1.0;
    _assets.drawInCell(
      canvas,
      'CUBE_ATLAS',
      recipeById(cube.recipe).cube,
      ui.Rect.fromLTWH(cube.x - 29, cube.y - 58, 58, 58),
      alpha: alpha,
    );
  }

  void _drawEnemies(ui.Canvas canvas) {
    for (final enemy in _enemies) {
      if (enemy.health <= 0 ||
          enemy.x < _viewLeft - 100 ||
          enemy.x > _viewRight + 100) {
        continue;
      }
      final animation = enemy.ranged && enemy.firing > 0
          ? enemy.fireAnimation
          : enemy.animation;
      final height = enemy.ranged
          ? (enemy.flying ? 78.0 : 72.0)
          : (enemy.flying ? 76.0 : 66.0);
      final hitAlpha = enemy.ranged ? 0.45 : 0.55;
      _assets.drawAnchored(
        canvas,
        enemy.sheet,
        animation,
        enemy.x,
        enemy.y,
        height,
        frameIndex:
            (_elapsed * 8 + (enemy.ranged ? enemy.x : enemy.homeX) * 0.01)
                .floor(),
        flipX: enemy.direction > 0,
        alpha: enemy.hit > 0 ? hitAlpha : 1,
        metricHeight: _assets[enemy.sheet]?.animationHeights[animation],
      );
      if (enemy.ranged && enemy.firing > 0.28) {
        canvas.drawCircle(
          ui.Offset(enemy.x + enemy.direction * 34, enemy.y - 48),
          14 * (0.5 + enemy.firing),
          ui.Paint()
            ..color = const ui.Color(0xccffde7d)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 2 / _scale,
        );
      }
    }
  }

  void _drawProjectiles(ui.Canvas canvas) {
    for (final projectile in _projectiles) {
      if (projectile.x < _viewLeft - 60 || projectile.x > _viewRight + 60) {
        continue;
      }
      final size = projectile.owner == 'player' ? 34.0 : 28.0;
      canvas.save();
      canvas.translate(projectile.x, projectile.y);
      canvas.rotate(projectile.age * (projectile.owner == 'player' ? 10 : 6));
      _assets.drawInCell(
        canvas,
        'PROJECTILE_ATLAS',
        projectile.type,
        ui.Rect.fromLTWH(-size / 2, -size / 2, size, size),
      );
      canvas.restore();
    }
  }

  /// Boss mode → (sheet, animation), as BOSS_VISUALS in renderer.js.
  (String, String) _bossVisual(_Boss boss) {
    final defeated = boss.health <= 0;
    switch (boss.type) {
      case 'eagle':
        if (defeated) return ('BOSS_EAGLE_B', 'eagle_defeat');
        return switch (boss.mode) {
          'telegraph' => ('BOSS_EAGLE_A', 'eagle_telegraph'),
          'dive' => ('BOSS_EAGLE_A', 'eagle_dive'),
          'hurt' => ('BOSS_EAGLE_B', 'eagle_recoil'),
          _ => ('BOSS_EAGLE_A', 'eagle_hover'),
        };
      case 'adder':
        if (defeated) return ('BOSS_ADDER_B', 'adder_defeat');
        return switch (boss.mode) {
          'swim' => ('BOSS_ADDER_A', 'adder_sand_swim'),
          'emerge' => ('BOSS_ADDER_A', 'adder_emerge'),
          'hurt' => ('BOSS_ADDER_B', 'adder_hurt'),
          _ => ('BOSS_ADDER_A', 'adder_listen'),
        };
      default:
        return (
          'BOSS_TAZ_A',
          defeated || boss.mode != 'run' ? 'taz_spin' : 'taz_run',
        );
    }
  }

  void _drawBoss(ui.Canvas canvas) {
    final boss = _boss;
    if (boss == null || boss.x < _viewLeft - 180 || boss.x > _viewRight + 180) {
      return;
    }
    final (key, animation) = _bossVisual(boss);
    final targetHeight = switch (boss.type) {
      'eagle' => 150.0,
      'adder' => 118.0,
      _ => 110.0,
    };
    _assets.drawAnchored(
      canvas,
      key,
      animation,
      boss.x,
      boss.y,
      targetHeight,
      frameIndex: (_elapsed * (boss.hit > 0 ? 10 : 7)).floor(),
      alpha: boss.hit > 0 && math.sin(_elapsed * 30) > 0 ? 0.45 : 1,
      metricHeight: _assets[key]?.animationHeights[animation],
    );
    if (boss.health <= 0) return;
    final barX = boss.x - 90;
    final barY = boss.y - (boss.type == 'eagle' ? 175 : 135);
    canvas.drawRect(
      ui.Rect.fromLTWH(barX, barY, 180, 10),
      ui.Paint()..color = const ui.Color(0xb8140d11),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(
        barX + 2 / _scale,
        barY + 2 / _scale,
        (180 - 4 / _scale) * boss.health / boss.maxHealth,
        math.max(3 / _scale, 6),
      ),
      ui.Paint()..color = const ui.Color(0xfff2a94f),
    );
  }

  void _drawPlayer(ui.Canvas canvas) {
    final animation = _player.animation;
    final group = switch (animation) {
      'jump_takeoff' || 'jump_rise' || 'fall' || 'land' => 'AIR',
      'eat' || 'craft_cube' || 'back_drop' || 'push' => 'CRAFT',
      'climb_ledge' ||
      'shield_start' ||
      'shield_hold' ||
      'shield_parry' => 'SHIELD',
      'dig_start' ||
      'burrow_move' ||
      'emerge_uppercut' ||
      'shockwave_slam' => 'BURROW',
      'hurt' || 'knockout' => 'DAMAGE',
      _ => 'MOVE',
    };
    final skin = skinById(_skin);
    final sheet = 'SKIN_${skin.prefix}_$group';
    final speed = animation == 'sprint'
        ? 12
        : animation == 'walk'
        ? 9
        : 7;
    final alpha = _player.invulnerable > 0 && math.sin(_elapsed * 28) > 0
        ? 0.4
        : _player.burrowing
        ? 0.72
        : 1.0;
    final facing = _player.shielding ? -_player.shieldDir : _player.facing;
    _assets.drawAnchored(
      canvas,
      sheet,
      animation,
      _player.x,
      _player.y,
      82,
      frameIndex: (_player.animationTime * speed).floor(),
      flipX: facing < 0,
      alpha: alpha,
      metricHeight: _assets[sheet]?.animationHeights[animation],
    );
    if (_player.shielding) {
      final center = ui.Offset(
        _player.x + _player.shieldDir * 31,
        _player.y - 35,
      );
      canvas.drawArc(
        ui.Rect.fromCircle(center: center, radius: 30),
        _player.shieldDir > 0 ? -1.1 : 2.05,
        2.2,
        false,
        ui.Paint()
          ..color = ui.Color(skin.shieldColor)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = math.max(2 / _scale, 3),
      );
    }
  }

  void _drawEffects(ui.Canvas canvas) {
    for (final effect in _effects) {
      if (effect.x < _viewLeft - 80 || effect.x > _viewRight + 80) continue;
      final frame = math.min(4, (effect.age / _Effect.duration * 5).floor());
      _assets.drawInCell(
        canvas,
        effect.sheet,
        effect.animation,
        ui.Rect.fromCenter(
          center: ui.Offset(effect.x, effect.y),
          width: effect.size,
          height: effect.size,
        ),
        frameIndex: frame,
      );
    }
  }

  void _drawCaveDarkness(ui.Canvas canvas, double width, double height) {
    final bounds = ui.Rect.fromLTWH(
      _cameraX,
      -_offsetY / _scale,
      width / _scale,
      height / _scale,
    );
    canvas.saveLayer(bounds, ui.Paint());
    canvas.drawRect(bounds, ui.Paint()..color = const ui.Color(0xb8050512));
    final lights = <(double, double, double)>[
      (_player.x, _player.y - 35, 140),
      for (final cube in _cubes)
        if (cube.recipe == 'spore' && !cube.dead) (cube.x, cube.y - 30, 190),
    ];
    for (final (x, y, radius) in lights) {
      final center = ui.Offset(x, y);
      canvas.drawCircle(
        center,
        radius,
        ui.Paint()
          ..blendMode = ui.BlendMode.dstOut
          ..shader = ui.Gradient.radial(
            center,
            radius,
            const [
              ui.Color(0xff000000),
              ui.Color(0xb8000000),
              ui.Color(0x00000000),
            ],
            const [0, 0.7, 1],
          ),
      );
    }
    canvas.restore();
  }

  @override
  void onRemove() {
    if (isLoaded) {
      unawaited(saveProgressNow());
      _assets.dispose();
    }
    // GameAudio is a singleton; stop it instead of disposing so a new game
    // instance can still play sound.
    unawaited(GameAudio.instance.stopBgm());
    uiState.dispose();
    loadProgress.dispose();
    super.onRemove();
  }
}
