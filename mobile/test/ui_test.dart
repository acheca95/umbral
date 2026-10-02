import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbral_rpg/app.dart';
import 'package:umbral_rpg/game.dart';
import 'package:umbral_rpg/save_store.dart';
import 'package:umbral_rpg/world.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(320, 640),
  ]) {
    testWidgets('Menu, gameplay and panels fit ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = SaveStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(UmbralApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('UMBRAL'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Comenzar aventura'));
      await tester.tap(find.text('Comenzar aventura'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ATACAR'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Mochila [I]'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Equipo y mochila'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Volver al juego'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Mapa [M]'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Atlas de los ecos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
  testWidgets('Death and victory overlays offer working continuation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = SaveStore(await SharedPreferences.getInstance());
    final g = Game(HeroClass.guardian)..dead = true;
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(game: g, store: store, onExit: () {}),
      ),
    );
    await tester.tap(find.text('Volver al refugio'));
    await tester.pump();
    expect(g.dead, isFalse);
    g.won = true;
    g.changed();
    await tester.pump();
    expect(find.text('El alba regresa'), findsOneWidget);
    await tester.tap(find.text('Seguir explorando'));
    await tester.pump();
    expect(find.text('El alba regresa'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    g.dispose();
  });
}
