import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'main_menu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The game is landscape-only and fullscreen.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await GameAudio.instance.loadSettings();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akar Berulah, Wombat Meluncur',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4f8066)),
        useMaterial3: true,
      ),
      home: const MainMenuScreen(),
    );
  }
}
