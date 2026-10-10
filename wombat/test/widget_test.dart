// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wombat/game/asset_catalog.dart';
import 'package:wombat/game/audio.dart';
import 'package:wombat/game/cubewombat_game.dart';
import 'package:wombat/game/world_data.dart';
import 'package:wombat/game_screen.dart';
import 'package:wombat/main_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cubewombat data contains all zones, recipes, and rare roots', () {
    expect(areas, hasLength(10));
    expect(recipes, hasLength(10));
    expect(skins, hasLength(10));
    expect(areas.expand((area) => area.roots), hasLength(24));
    expect(areasById.keys.toSet(), areas.map((area) => area.id).toSet());
    // Progression starts like the JS game: one area, one recipe.
    expect(const GameUiState().discovered, {'forest'});
    expect(const GameUiState().unlockedRecipes, {'earth'});
  });

  test('all bundled sprite atlases have local frame metadata', () async {
    final manifest =
        jsonDecode(
              await rootBundle.loadString('assets/json/asset_manifest.json'),
            )
            as Map<String, dynamic>;
    final frameFiles = manifest.values
        .map((value) => value.toString())
        .where((path) => path.contains('transparent') || path.contains('tiles'))
        .map(
          (path) => path.split('/').last.replaceFirst('.webp', '.frames.json'),
        )
        .toSet();

    expect(frameFiles, hasLength(93));
    for (final file in frameFiles) {
      final metadata =
          jsonDecode(await rootBundle.loadString('assets/json/$file'))
              as Map<String, dynamic>;
      expect(metadata['frames'], isNotEmpty, reason: file);
    }
  });

  test('Flame asset catalog decodes the game art and default skin', () async {
    final assets = await GameAssetCatalog.load();
    expect(assets['BG_BOG'], isNull);
    await assets.loadKeys([
      'BG_FOREST',
      'CUBE_ATLAS',
      'TERRAIN_ATLAS',
      'WORLD_ATLAS',
      'OBSTACLE_ATLAS',
      'AREA_PUZZLE_ATLAS',
      'PROJECTILE_ATLAS',
      'SKIN_ICON_ATLAS',
      'RANGED_ENEMY_SHEET_1',
      'ENEMY_SHEET_1',
    ]);
    await assets.loadSkin('BUSH');
    expect(assets['BG_FOREST'], isNotNull);
    expect(assets['CUBE_ATLAS'], isNotNull);
    expect(assets['ENEMY_SHEET_1'], isNotNull);
    expect(assets['SKIN_ICON_ATLAS']?.frames['bush_ranger'], isNotNull);
    expect(assets['SKIN_BUSH_MOVE']?.animations['walk'], hasLength(5));
    assets.dispose();
  });

  testWidgets('tutorial panel explains controls and acknowledges dismissal', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [GameTutorialPanel(onDismiss: () => dismissed = true)],
          ),
        ),
      ),
    );

    expect(find.text('Cara Bermain'), findsOneWidget);
    expect(find.text('Bergerak'), findsOneWidget);
    expect(find.text('Skill'), findsOneWidget);
    await tester.ensureVisible(find.text('Mengerti'));
    await tester.tap(find.text('Mengerti'));
    expect(dismissed, isTrue);
  });

  testWidgets('main menu resets saved progress after confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'cubewombat.save': '{}',
      'cubewombat.tutorialSeen': true,
      'cubewombat.muted': true,
    });
    // Landscape phone size: the menu must fit without overflowing.
    tester.view.physicalSize = const Size(780, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: MainMenuScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Lanjutkan'), findsOneWidget);
    await tester.tap(find.text('Reset Progres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('cubewombat.save'), isFalse);
    expect(preferences.containsKey('cubewombat.tutorialSeen'), isFalse);
    expect(preferences.getBool('cubewombat.muted'), isTrue);
    expect(find.text('Main'), findsOneWidget);
  });

  testWidgets('clue pops up after lingering at an unsolved mission', (
    tester,
  ) async {
    GameAudio.instance.muted.value = true;
    addTearDown(() => GameAudio.instance.muted.value = false);
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'cubewombat.tutorialSeen': true,
      'cubewombat.save':
          '{"area":"forest","playerPosition":{"x":450,"y":580},'
          '"tutorialSeen":true}',
    });
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    // Let the game decode its assets (real async work).
    for (
      var i = 0;
      i < 40 && find.byTooltip('Lihat clue').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byTooltip('Lihat clue'), findsOneWidget);
    expect(find.text('CLUE MISI'), findsNothing);

    // Stand next to the closed tutorial gate for longer than the threshold.
    for (var i = 0; i < 13 * 30; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(find.text('CLUE MISI'), findsOneWidget);
    expect(find.text('Pelat kayu'), findsOneWidget);

    await tester.ensureVisible(find.text('Siap, coba lagi'));
    await tester.tap(find.text('Siap, coba lagi'));
    await tester.pump();
    expect(find.text('CLUE MISI'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Cubewombat screen shows HUD and touch controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Eucalyptus'), findsOneWidget);
    expect(find.text('LOMPAT'), findsOneWidget);
    expect(find.byTooltip('Cara bermain'), findsOneWidget);
    expect(find.byTooltip('Matikan suara'), findsOneWidget);
    expect(find.byTooltip('Menu utama'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(find.text('Peta Dunia'), findsOneWidget);
    expect(find.text('10 SKIN MOMO'), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-preview-bush')), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-preview-root')), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
