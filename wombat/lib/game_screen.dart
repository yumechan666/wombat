import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'game/cubewombat_game.dart';
import 'game/world_data.dart';

// Layout and colours follow the JS game's ui.js / styles.css.
const _cream = Color(0xfffff5d5);
const _paperColor = Color(0xffe7d39e);
const _ink = Color(0xff332517);
const _inkSoft = Color(0xff79552e);
const _badgeColor = Color(0xc7191c19);
const _badgeBorder = Color(0x59fce5a9);

/// Recipe gem colours from styles.css (`.recipe-button[data-type]`).
const _gemColors = {
  'earth': Color(0xffb9773e),
  'sticky': Color(0xff83a84b),
  'spore': Color(0xff42dcd0),
  'blast': Color(0xffa65ac7),
  'iron': Color(0xff6b7280),
  'ice': Color(0xff8edcf4),
  'mirror': Color(0xfff4dca8),
  'sand': Color(0xffd9a65e),
  'battery': Color(0xff4fc5ae),
  'obsidian': Color(0xff342b3c),
};

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final _game = CubewombatGame();
  final _stickKey = GlobalKey();
  final _nub = ValueNotifier(Offset.zero);
  final Set<LogicalKeyboardKey> _keysDown = {};
  int? _stickPointer;
  bool _mapOpen = false;
  bool _helpOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(GameAudio.instance.resumeBgm());
    } else {
      unawaited(_game.saveProgressNow());
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        unawaited(GameAudio.instance.pauseBgm());
      }
    }
  }

  /// Desktop window close: finish writing the save before the app exits.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _game.saveProgressNow();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _keysDown.clear();
    _nub.dispose();
    unawaited(_game.saveProgressNow());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff102a2c),
      body: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GameWidget<CubewombatGame>(
              game: _game,
              loadingBuilder: (context) => _LoadingOverlay(progress: null),
            ),
            ValueListenableBuilder<GameUiState>(
              valueListenable: _game.uiState,
              builder: (context, state, _) => Stack(
                fit: StackFit.expand,
                children: [
                  _buildGameOverlay(context, state),
                  if (state.loading)
                    ValueListenableBuilder<double>(
                      valueListenable: _game.loadProgress,
                      builder: (context, progress, _) =>
                          _LoadingOverlay(progress: progress),
                    ),
                  if (_mapOpen) _buildMapPanel(context, state),
                  if (state.pendingUpgrade) _buildUpgradePanel(state),
                  if (state.won) _buildWinPanel(state),
                  if (state.clueText.isNotEmpty) _buildCluePanel(state),
                  if (!state.loading && (state.showTutorial || _helpOpen))
                    GameTutorialPanel(onDismiss: _closeTutorial),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  bool _onHardwareKey(KeyEvent event) {
    GameAudio.instance.unlock();
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (isDown) {
      _keysDown.add(key);
    } else {
      _keysDown.remove(key);
    }
    final name = _inputForKey(key);
    if (name == null) return false;
    if (name == 'recipe') {
      if (event is KeyDownEvent) _game.cycleRecipe();
    } else if (name == 'map') {
      if (event is KeyDownEvent) _toggleMap();
    } else {
      final held = _keysDown.any((pressed) => _inputForKey(pressed) == name);
      _game.setInput(name, held);
    }
    return true;
  }

  String? _inputForKey(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.keyA => 'left',
    LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.keyD => 'right',
    LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyS => 'down',
    LogicalKeyboardKey.space => 'jump',
    LogicalKeyboardKey.keyE => 'action',
    LogicalKeyboardKey.shiftLeft || LogicalKeyboardKey.shiftRight => 'skill',
    LogicalKeyboardKey.keyQ => 'recipe',
    LogicalKeyboardKey.keyM => 'map',
    _ => null,
  };

  void _updateStick(Offset global) {
    final render = _stickKey.currentContext?.findRenderObject();
    if (render is! RenderBox) return;
    final delta =
        render.globalToLocal(global) - render.size.center(Offset.zero);
    final radius = render.size.width * 0.28;
    final length = delta.distance == 0 ? 1.0 : delta.distance;
    _nub.value = delta / length * math.min(radius, length);
    _game
      ..setInput('left', delta.dx < -render.size.width * 0.12)
      ..setInput('right', delta.dx > render.size.width * 0.12)
      ..setInput('down', delta.dy > render.size.height * 0.15);
  }

  void _releaseStick() {
    _stickPointer = null;
    _nub.value = Offset.zero;
    _game
      ..setInput('left', false)
      ..setInput('right', false)
      ..setInput('down', false);
  }

  // ---------------------------------------------------------------------------
  // HUD & touch controls
  // ---------------------------------------------------------------------------

  Widget _buildGameOverlay(BuildContext context, GameUiState state) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xbd070f12), Color(0x00070f12)],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                math.max(10, padding.left),
                math.max(8, padding.top),
                math.max(10, padding.right),
                26,
              ),
              child: _buildHudRow(state),
            ),
          ),
        ),
        if (state.toast.isNotEmpty)
          _centeredPill(
            top: padding.top + 62,
            child: _pill(
              state.toast,
              color: const Color(0xff352615),
              background: const Color(0xfff2d792),
              border: const Color(0xfffff3cc),
            ),
          ),
        _centeredPill(
          top: padding.top + 98,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            child: state.areaName.isEmpty
                ? const SizedBox.shrink()
                : _pill(
                    state.areaName,
                    key: ValueKey(state.areaName),
                    fontSize: 22,
                    color: const Color(0xfffff6d9),
                    background: const Color(0xa3231f23),
                  ),
          ),
        ),
        if (state.bossName.isNotEmpty)
          _centeredPill(
            top: padding.top + 140,
            child: _pill(
              state.bossName,
              color: const Color(0xffffd184),
              border: const Color(0xa6ff844f),
              letterSpacing: 1.4,
            ),
          ),
        if (state.prompt.isNotEmpty)
          // JS puts the hint just above the controls; on short landscape
          // phones that covers Momo, so it sits between the joystick and the
          // buttons instead.
          MediaQuery.sizeOf(context).height < 600
              ? Positioned(
                  left: padding.left + 140,
                  right: padding.right + 250,
                  bottom: padding.bottom + 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: 0.94,
                        child: _pill(state.prompt, fontSize: 13),
                      ),
                    ),
                  ),
                )
              : _centeredPill(
                  bottom: padding.bottom + 104,
                  child: Opacity(opacity: 0.94, child: _pill(state.prompt)),
                ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildTouchControls(padding),
        ),
      ],
    );
  }

  Widget _buildHudRow(GameUiState state) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _badge(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < state.maxHealth; index++)
              _LeafPip(full: index < state.health),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _badge(
          Text(
            state.area.shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xffdff7d4)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      _tapBadge(
        onTap: _game.cycleRecipe,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RecipeGem(recipeId: state.selectedRecipe),
            const SizedBox(width: 6),
            Text(state.recipe.label),
          ],
        ),
      ),
      const SizedBox(width: 8),
      _tapBadge(
        onTap: _toggleMap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⌁'),
            const SizedBox(width: 6),
            Text('${state.rootCount}/24'),
          ],
        ),
      ),
      const SizedBox(width: 8),
      if (state.clueAvailable) ...[
        _PulsingGlow(
          child: _roundButton(
            tooltip: 'Lihat clue',
            icon: Icons.lightbulb_rounded,
            onPressed: _game.showClue,
            highlight: true,
          ),
        ),
        const SizedBox(width: 6),
      ],
      _roundButton(
        tooltip: 'Cara bermain',
        icon: Icons.help_outline_rounded,
        onPressed: _openHelp,
      ),
      const SizedBox(width: 6),
      ValueListenableBuilder<bool>(
        valueListenable: GameAudio.instance.muted,
        builder: (context, muted, _) => _roundButton(
          tooltip: muted ? 'Nyalakan suara' : 'Matikan suara',
          icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          onPressed: GameAudio.instance.toggleMuted,
        ),
      ),
      const SizedBox(width: 6),
      _roundButton(
        tooltip: 'Menu utama',
        icon: Icons.home_rounded,
        onPressed: _backToMenu,
      ),
    ],
  );

  Widget _buildTouchControls(EdgeInsets padding) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xb8060a0b), Color(0x00060a0b)],
      ),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        math.max(20, padding.left + 8),
        12,
        math.max(20, padding.right + 8),
        math.max(12, padding.bottom + 4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildJoystick(),
          const Spacer(),
          _holdButton('skill', '◆', 'SKILL', const Color(0xe6376d70)),
          const SizedBox(width: 12),
          _holdButton('action', '■', 'KUBUS', const Color(0xeba66934)),
          const SizedBox(width: 12),
          Transform.translate(
            offset: const Offset(0, -8),
            child: _holdButton('jump', '↑', 'LOMPAT', const Color(0xe6487146)),
          ),
        ],
      ),
    ),
  );

  Widget _buildJoystick() => Listener(
    key: _stickKey,
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (_stickPointer != null) return;
      GameAudio.instance.unlock();
      _stickPointer = event.pointer;
      _updateStick(event.position);
    },
    onPointerMove: (event) {
      if (event.pointer == _stickPointer) _updateStick(event.position);
    },
    onPointerUp: (event) {
      if (event.pointer == _stickPointer) _releaseStick();
    },
    onPointerCancel: (event) {
      if (event.pointer == _stickPointer) _releaseStick();
    },
    child: SizedBox(
      width: 94,
      height: 94,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x73141714),
                border: Border.all(color: const Color(0x61fff2cc), width: 2),
              ),
            ),
          ),
          ValueListenableBuilder<Offset>(
            valueListenable: _nub,
            builder: (context, offset, child) => Positioned.fill(
              child: Transform.translate(offset: offset, child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.all(94 * 0.27),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xffe7d39d),
                  border: Border.all(color: const Color(0xff564a32), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0xff2c261c), offset: Offset(0, 3)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // Raw pointer events: react instantly and stay held even if the finger
  // drifts, like the JS pointerdown/pointerup handlers.
  Widget _holdButton(String input, String glyph, String label, Color color) =>
      Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          GameAudio.instance.unlock();
          _game.setInput(input, true);
        },
        onPointerUp: (_) => _game.setInput(input, false),
        onPointerCancel: (_) => _game.setInput(input, false),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x9efff4d0), width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0xcc0c0e0b), offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                glyph,
                style: const TextStyle(
                  color: Color(0xfffff7df),
                  fontSize: 22,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xfffff7df),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _badge(Widget child) => Container(
    constraints: const BoxConstraints(minHeight: 34),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _badgeColor,
      border: Border.all(color: _badgeBorder),
      borderRadius: BorderRadius.circular(999),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        color: _cream,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
      child: child,
    ),
  );

  Widget _tapBadge({required VoidCallback onTap, required Widget child}) =>
      GestureDetector(onTap: onTap, child: _badge(child));

  Widget _roundButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool highlight = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      minimumSize: const Size(34, 34),
      maximumSize: const Size(34, 34),
      padding: EdgeInsets.zero,
      backgroundColor: highlight ? const Color(0xfff2d792) : _badgeColor,
      side: BorderSide(
        color: highlight ? const Color(0xfffff3cc) : _badgeBorder,
      ),
    ),
    icon: Icon(
      icon,
      size: 19,
      color: highlight ? const Color(0xffa66934) : _cream,
    ),
  );

  Widget _centeredPill({double? top, double? bottom, required Widget child}) =>
      Positioned(
        top: top,
        bottom: bottom,
        left: 16,
        right: 16,
        child: IgnorePointer(child: Center(child: child)),
      );

  Widget _pill(
    String text, {
    Key? key,
    Color color = const Color(0xfffff4d0),
    Color background = const Color(0xd6141716),
    Color border = const Color(0x61ffecb9),
    double fontSize = 15,
    double letterSpacing = 0,
  }) => Container(
    key: key,
    constraints: const BoxConstraints(maxWidth: 520),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
        letterSpacing: letterSpacing,
      ),
    ),
  );

  void _toggleMap() {
    setState(() => _mapOpen = !_mapOpen);
    _game.setPaused(_mapOpen);
  }

  void _openHelp() {
    setState(() => _helpOpen = true);
    _game.setPaused(true);
  }

  void _closeTutorial() {
    setState(() => _helpOpen = false);
    if (_game.uiState.value.showTutorial) {
      unawaited(_game.dismissTutorial());
    } else {
      _game.setPaused(_mapOpen);
    }
  }

  Future<void> _backToMenu() async {
    await _game.saveProgressNow();
    if (mounted) await Navigator.of(context).maybePop();
  }

  // ---------------------------------------------------------------------------
  // Panels
  // ---------------------------------------------------------------------------

  Widget _buildMapPanel(BuildContext context, GameUiState state) => _overlay(
    child: _PaperPanel(
      maxWidth: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _PanelHeading(small: 'JALUR AKAR', title: 'Peta Dunia'),
              ),
              _CloseButton(onPressed: _toggleMap),
            ],
          ),
          const SizedBox(height: 14),
          _TwoColumnGrid(
            gap: 9,
            children: [
              for (final area in areas)
                _MapNode(
                  area: area,
                  state: state,
                  onTap: () async {
                    final loading = _game.travelTo(area.id);
                    if (mounted) setState(() => _mapOpen = false);
                    await loading;
                  },
                ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _summaryChip('Pencernaan', '${state.upgrades['metabolism']}/3'),
              _summaryChip('Bokong', '${state.upgrades['rump']}/3'),
              _summaryChip('Indra', '${state.upgrades['senses']}/3'),
              _summaryChip('Rayap', '${state.termiteCount}'),
            ],
          ),
          const SizedBox(height: 16),
          const _PanelHeading(
            small: '10 SKIN MOMO',
            title: 'Pilih Paket Animasi',
            titleSize: 17,
          ),
          const SizedBox(height: 8),
          _TwoColumnGrid(
            gap: 8,
            children: [
              for (final skin in skins)
                _SkinOption(
                  game: _game,
                  skin: skin,
                  current: state.selectedSkin == skin.id,
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _summaryChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x1f533b22),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text.rich(
      TextSpan(
        text: '$label ',
        children: [
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
      style: const TextStyle(color: Color(0xff3b2917), fontSize: 13),
    ),
  );

  Widget _buildUpgradePanel(GameUiState state) => _overlay(
    child: _PaperPanel(
      maxWidth: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeading(
            small: 'AKAR LANGKA BERGERAK',
            title: 'Pilih Evolusi',
          ),
          const SizedBox(height: 16),
          for (final (branch, label, detail) in const [
            ('metabolism', 'Metabolisme', 'Kubus lebih cepat dan lebih banyak'),
            ('rump', 'Bokong', 'Parry lebih kuat dan tahan lama'),
            ('senses', 'Indra', 'Rahasia dan akar lebih mudah terasa'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _UpgradeButton(
                label: label,
                detail: detail,
                level: state.upgrades[branch] ?? 0,
                onPressed: () => _game.chooseUpgrade(branch),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildCluePanel(GameUiState state) => _overlay(
    child: _PaperPanel(
      maxWidth: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xfff2d792),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lightbulb_rounded,
                  color: Color(0xffa66934),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PanelHeading(
                  small: 'CLUE MISI',
                  title: state.clueTitle,
                  titleSize: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.clueText,
            style: const TextStyle(color: _ink, fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 16),
          Center(
            child: _PrimaryButton(
              label: 'Siap, coba lagi',
              onPressed: _game.dismissClue,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildWinPanel(GameUiState state) => _overlay(
    child: _PaperPanel(
      maxWidth: 460,
      child: Column(
        children: [
          const Text(
            'AKAR DUNIA TERBANGUN',
            style: TextStyle(
              color: _inkSoft,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const Text(
            'Momo menyelamatkan jalur bawah tanah',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 28,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${state.rootCount}/24 Akar Langka ditemukan',
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _PrimaryButton(
            label: 'Lanjut menjelajah',
            onPressed: _game.continueAfterWin,
          ),
        ],
      ),
    ),
  );

  Widget _overlay({required Widget child}) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xb8070c0e),
      child: SafeArea(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Small widgets
// -----------------------------------------------------------------------------

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: ColoredBox(
      color: const Color(0xff173c3e),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LoadingCube(),
            const SizedBox(height: 12),
            const Text(
              'Menumbuhkan akar…',
              style: TextStyle(
                color: Color(0xfff9eac2),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (progress != null)
              Text(
                '${(progress! * 100).round()}%',
                style: const TextStyle(color: Color(0xfff9eac2), fontSize: 15),
              ),
          ],
        ),
      ),
    ),
  );
}

class _LoadingCube extends StatefulWidget {
  const _LoadingCube();

  @override
  State<_LoadingCube> createState() => _LoadingCubeState();
}

class _LoadingCubeState extends State<_LoadingCube>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final wave = math.sin(_controller.value * math.pi);
      return Transform.translate(
        offset: Offset(0, -8 * wave),
        child: Transform.rotate(angle: 0.14 * wave, child: child),
      );
    },
    child: Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xffbd7d43),
        border: Border.all(color: const Color(0xff503821), width: 4),
        borderRadius: BorderRadius.circular(11),
        boxShadow: const [BoxShadow(color: Color(0x3b81ffcf), blurRadius: 35)],
      ),
    ),
  );
}

/// Blinks a warm glow around [child] and gently pulses its size so the clue
/// button catches the player's eye.
class _PulsingGlow extends StatefulWidget {
  const _PulsingGlow({required this.child});

  final Widget child;

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final t = Curves.easeInOut.transform(_controller.value);
      return Transform.scale(
        scale: 1 + 0.14 * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color.lerp(
                  const Color(0x00ffd36a),
                  const Color(0xeeffd36a),
                  t,
                )!,
                blurRadius: 6 + 14 * t,
                spreadRadius: 1 + 4 * t,
              ),
            ],
          ),
          child: Opacity(opacity: 0.7 + 0.3 * t, child: child),
        ),
      );
    },
    child: widget.child,
  );
}

class _LeafPip extends StatelessWidget {
  const _LeafPip({required this.full});

  final bool full;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: Center(
      child: Opacity(
        opacity: full ? 1 : 0.28,
        child: Transform.rotate(
          angle: -35 * math.pi / 180,
          child: Container(
            width: 13,
            height: 18,
            decoration: BoxDecoration(
              color: full ? const Color(0xff8bd15e) : const Color(0xff9a9a9a),
              border: Border.all(color: const Color(0xff284d2b)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(11),
                bottomLeft: Radius.circular(3),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RecipeGem extends StatelessWidget {
  const _RecipeGem({required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: 8 * math.pi / 180,
    child: Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        color: _gemColors[recipeId] ?? _gemColors['earth'],
        border: Border.all(color: const Color(0xff4a2f1f), width: 2),
        borderRadius: BorderRadius.circular(4),
        boxShadow: recipeId == 'obsidian'
            ? const [BoxShadow(color: Color(0xffef6a35), spreadRadius: -2)]
            : null,
      ),
    ),
  );
}

class _PaperPanel extends StatelessWidget {
  const _PaperPanel({required this.child, this.maxWidth = 600});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    child: Container(
      decoration: BoxDecoration(
        color: _paperColor,
        border: Border.all(color: const Color(0xff5c432a), width: 3),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(24),
          bottomLeft: Radius.circular(14),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x6b19110b), offset: Offset(0, 12)),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    ),
  );
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.small,
    required this.title,
    this.titleSize = 30,
  });

  final String small;
  final String title;
  final double titleSize;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        small,
        style: const TextStyle(
          color: _inkSoft,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      Text(
        title,
        style: TextStyle(
          color: _ink,
          fontSize: titleSize,
          height: 1.05,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        backgroundColor: const Color(0xfff4e5b7),
        foregroundColor: const Color(0xff3c2b1b),
        side: const BorderSide(color: Color(0xff6f502f), width: 2),
      ),
      child: const Text('×', style: TextStyle(fontSize: 26, height: 1)),
    ),
  );
}

/// Two equal columns, like `grid-template-columns: repeat(2, 1fr)`.
class _TwoColumnGrid extends StatelessWidget {
  const _TwoColumnGrid({required this.children, required this.gap});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _MapNode extends StatelessWidget {
  const _MapNode({
    required this.area,
    required this.state,
    required this.onTap,
  });

  final AreaSpec area;
  final GameUiState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final discovered = state.discovered.contains(area.id);
    final current = state.areaId == area.id;
    final recipe = recipeById(area.recipe);
    return Opacity(
      opacity: discovered ? 1 : 0.38,
      child: OutlinedButton(
        onPressed: discovered ? onTap : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(66),
          padding: const EdgeInsets.all(8),
          alignment: Alignment.centerLeft,
          foregroundColor: const Color(0xff3b2a19),
          disabledForegroundColor: const Color(0xff3b2a19),
          backgroundColor: const Color(0x7afff7d7),
          side: BorderSide(
            color: current ? const Color(0xff2e7b68) : const Color(0xff85653e),
            width: current ? 3 : 2,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(13),
              topRight: Radius.circular(9),
              bottomRight: Radius.circular(15),
              bottomLeft: Radius.circular(10),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xff496d58),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${area.index + 1}',
                style: const TextStyle(
                  color: Color(0xfff8e8b8),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    area.shortName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    state.unlockedRecipes.contains(area.recipe)
                        ? '◆ ${recipe.label}'
                        : 'Belum ditemukan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkinOption extends StatelessWidget {
  const _SkinOption({
    required this.game,
    required this.skin,
    required this.current,
  });

  final CubewombatGame game;
  final SkinSpec skin;
  final bool current;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => game.chooseSkin(skin.id),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(64),
      padding: const EdgeInsets.all(5),
      alignment: Alignment.centerLeft,
      foregroundColor: const Color(0xff3b2917),
      backgroundColor: current
          ? const Color(0x4074b58e)
          : const Color(0x85fff7d5),
      side: BorderSide(
        color: current ? const Color(0xff2e7b68) : const Color(0xff866541),
        width: 2,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(13),
          topRight: Radius.circular(9),
          bottomRight: Radius.circular(14),
          bottomLeft: Radius.circular(10),
        ),
      ),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: CustomPaint(
            key: ValueKey('skin-preview-${skin.id}'),
            painter: _SkinPreviewPainter(game, skin.id),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            skin.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton({
    required this.label,
    required this.detail,
    required this.level,
    required this.onPressed,
  });

  final String label;
  final String detail;
  final int level;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: level >= 3 ? 0.38 : 1,
    child: OutlinedButton(
      onPressed: level >= 3 ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: Alignment.centerLeft,
        foregroundColor: const Color(0xff3b2917),
        disabledForegroundColor: const Color(0xff3b2917),
        backgroundColor: const Color(0x94fff7d5),
        side: const BorderSide(color: Color(0xff755230), width: 2),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(15),
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(17),
            bottomLeft: Radius.circular(11),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(detail, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('$level/3', style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size(44, 44),
      backgroundColor: const Color(0xff4f8066),
      foregroundColor: const Color(0xfffff7da),
      side: const BorderSide(color: Color(0xff315c4a), width: 2),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
  );
}

class _SkinPreviewPainter extends CustomPainter {
  const _SkinPreviewPainter(this.game, this.skinId);

  final CubewombatGame game;
  final String skinId;

  @override
  void paint(Canvas canvas, Size size) {
    game.drawSkinPreview(
      canvas,
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      skinId,
    );
  }

  @override
  bool shouldRepaint(covariant _SkinPreviewPainter oldDelegate) =>
      game != oldDelegate.game || skinId != oldDelegate.skinId;
}

class GameTutorialPanel extends StatelessWidget {
  const GameTutorialPanel({required this.onDismiss, super.key});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xb8070c0e),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _PaperPanel(
              maxWidth: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _PanelHeading(
                    small: 'PANDUAN MOMO',
                    title: 'Cara Bermain',
                  ),
                  const SizedBox(height: 4),
                  _step(
                    Icons.control_camera_rounded,
                    'Bergerak',
                    'Gunakan joystick atau tombol A/D maupun panah kiri/kanan. Ketuk arah dua kali untuk berlari.',
                  ),
                  _step(
                    Icons.arrow_upward_rounded,
                    'Melompat',
                    'Tekan LOMPAT atau Space untuk melewati lubang dan rintangan.',
                  ),
                  _step(
                    Icons.widgets_outlined,
                    'Makan daun & membuat kubus',
                    'Dekati daun lalu tekan KUBUS (E) untuk membuka resep. Tekan lagi untuk membuat kubus.',
                  ),
                  _step(
                    Icons.diamond_rounded,
                    'Skill',
                    'Tahan SKILL (Shift) untuk menangkis dan memantulkan proyektil. Tahan SKILL sambil menunduk untuk menggali, lalu lepas untuk menyerang ke atas.',
                  ),
                  _step(
                    Icons.map_outlined,
                    'Resep & peta',
                    'Ketuk ikon kubus (Q) untuk mengganti resep. Buka peta (M) untuk pindah ke area yang sudah ditemukan dan memilih skin.',
                  ),
                  _step(
                    Icons.volume_up_rounded,
                    'Suara & menu',
                    'Ikon speaker menyalakan/mematikan suara. Ikon rumah kembali ke menu utama. Ikon ? membuka panduan ini lagi. Progres tersimpan otomatis.',
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: _PrimaryButton(
                      label: 'Mengerti',
                      onPressed: onDismiss,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _step(IconData icon, String title, String detail) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0x334f8066),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: const Color(0xff376d5a)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                detail,
                style: const TextStyle(
                  color: Color(0xff493a2b),
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
