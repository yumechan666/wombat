import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/audio.dart';
import 'game_screen.dart';

/// Progress keys cleared by "Reset Progres". The mute setting is kept.
const _progressKeys = ['cubewombat.save', 'cubewombat.tutorialSeen'];

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  bool _hasSave = false;

  @override
  void initState() {
    super.initState();
    _checkSave();
  }

  Future<void> _checkSave() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _hasSave = preferences.containsKey('cubewombat.save'));
  }

  Future<void> _play() async {
    GameAudio.instance.unlock();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const GameScreen()));
    await GameAudio.instance.stopBgm();
    await _checkSave();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xffe7d39e),
        title: const Text(
          'Reset Progres?',
          style: TextStyle(
            color: Color(0xff332517),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Semua Akar Langka, upgrade, boss yang dikalahkan, dan posisi '
          'Momo akan dihapus. Tutorial akan muncul lagi. Tindakan ini '
          'tidak bisa dibatalkan.',
          style: TextStyle(color: Color(0xff493a2b)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Batal',
              style: TextStyle(color: Color(0xff49321d)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffa63f34),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final preferences = await SharedPreferences.getInstance();
    for (final key in _progressKeys) {
      await preferences.remove(key);
    }
    await _checkSave();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Progres berhasil direset')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff102a2c),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/bg_forest.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xff173c3e)),
          ),
          const ColoredBox(color: Color(0x88070c0e)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  // Landscape: title on the left, buttons on the right.
                  child: Row(
                    children: [
                      Expanded(child: _title()),
                      const SizedBox(width: 32),
                      SizedBox(width: 300, child: _buttons()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/images/logo.png',
        height: 130,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      const SizedBox(height: 8),
      const Text(
        'Akar Berulah,\nWombat Meluncur',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xfffff5d5),
          fontSize: 28,
          fontWeight: FontWeight.w900,
          height: 1.1,
        ),
      ),
    ],
  );

  Widget _buttons() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _menuButton(
        icon: Icons.play_arrow_rounded,
        label: _hasSave ? 'Lanjutkan' : 'Main',
        color: const Color(0xff487146),
        onPressed: _play,
      ),
      const SizedBox(height: 12),
      _menuButton(
        icon: Icons.restart_alt_rounded,
        label: 'Reset Progres',
        color: const Color(0xffa63f34),
        onPressed: _hasSave ? _confirmReset : null,
      ),
      const SizedBox(height: 12),
      ValueListenableBuilder<bool>(
        valueListenable: GameAudio.instance.muted,
        builder: (context, muted, _) => _menuButton(
          icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          label: muted ? 'Suara: Mati' : 'Suara: Nyala',
          color: const Color(0xff376d70),
          onPressed: GameAudio.instance.toggleMuted,
        ),
      ),
    ],
  );

  Widget _menuButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 26),
      label: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: const Color(0xfffff7df),
        disabledBackgroundColor: const Color(0x66555555),
        side: const BorderSide(color: Color(0x99fff4d0), width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    ),
  );
}
