import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'game.dart';
import 'cloud.dart';
import 'cloud_panel.dart';
import 'coop.dart';
import 'save_store.dart';
import 'world.dart';
import 'world_painter.dart';

const gold = Color(0xffdfbd84),
    muted = Color(0xff9daaab),
    surface = Color(0xff172327),
    teal = Color(0xff84cbb8);

class UmbralApp extends StatefulWidget {
  final SaveStore store;
  const UmbralApp({super.key, required this.store});
  @override
  State<UmbralApp> createState() => _UmbralAppState();
}

class _UmbralAppState extends State<UmbralApp> {
  Game? saved;
  late final CloudService cloud;
  CoopSession? coop;
  bool playing = false;
  @override
  void initState() {
    super.initState();
    saved = widget.store.load();
    cloud = CloudService(widget.store.preferences);
    if (widget.store.preferences.containsKey('umbral.cloud.owner')) {
      unawaited(cloud.connect());
    }
  }

  @override
  void dispose() {
    coop?.dispose();
    cloud.dispose();
    saved?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Umbral • Ecos de la Ceniza',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff0e181b),
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: teal,
        surface: surface,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(height: 1.5),
        titleLarge: TextStyle(
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w500,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: Color(0xff40504e)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    home: playing && saved != null
        ? GameScreen(
            game: saved!,
            store: widget.store,
            cloud: cloud,
            coop: coop,
            onExit: () async {
              await coop?.leave();
              if (!mounted) return;
              final previous = coop;
              setState(() {
                playing = false;
                coop = null;
              });
              // The screen removes its listener before this session is disposed.
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => previous?.dispose(),
              );
            },
          )
        : HomeScreen(
            saved: saved,
            warning: widget.store.warning,
            onOnline: (ctx, type) => showDialog<void>(
              context: ctx,
              builder: (_) => CloudPanel(
                cloud: cloud,
                saved: saved,
                selected: type,
                onRestore: (game) async {
                  await widget.store.save(game);
                  final old = saved;
                  if (!mounted) return;
                  setState(() => saved = game);
                  old?.dispose();
                },
                onPlay: (session) {
                  final old = saved;
                  setState(() {
                    coop = session;
                    saved = session.local;
                    playing = true;
                  });
                  old?.dispose();
                },
              ),
            ),
            onContinue: () {
              saved!.setPaused(false);
              setState(() => playing = true);
            },
            onStart: (type) async {
              final old = saved;
              final game = Game(type);
              setState(() {
                saved = game;
                playing = true;
              });
              old?.dispose();
              try {
                await widget.store.save(game);
              } catch (_) {
                game.tell('No se pudo guardar. Comprueba el almacenamiento.');
              }
            },
          ),
  );
}

class HomeScreen extends StatefulWidget {
  final Game? saved;
  final String? warning;
  final ValueChanged<HeroClass> onStart;
  final VoidCallback onContinue;
  final void Function(BuildContext, HeroClass) onOnline;
  const HomeScreen({
    super.key,
    required this.saved,
    required this.onStart,
    required this.onContinue,
    required this.onOnline,
    this.warning,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HeroClass selected = HeroClass.guardian;
  late final Game backdrop = Game(HeroClass.guardian)
    ..zoneId = 1
    ..position = const Offset(1100, 820);
  @override
  void dispose() {
    backdrop.dispose();
    super.dispose();
  }

  Future<void> start() async {
    if (widget.saved != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Comenzar otra aventura?'),
          content: const Text(
            'La nueva aventura sustituirá tu partida guardada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Nueva aventura'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    widget.onStart(selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: WorldPainter(backdrop, cinematic: true)),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xff091317).withValues(alpha: .78),
                  const Color(0xff0c171b).withValues(alpha: .96),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.brightness_4_outlined,
                          color: gold,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'UMBRA STUDIO  /  DEMO JUGABLE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: muted,
                              letterSpacing: 2,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('0.2', style: TextStyle(color: muted)),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'UN MUNDO AL BORDE DEL OLVIDO',
                      style: TextStyle(
                        color: teal,
                        letterSpacing: 3,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'UMBRAL',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 68,
                          height: 1.05,
                          letterSpacing: 9,
                          color: Color(0xfff0e3c9),
                        ),
                      ),
                    ),
                    const Text(
                      'E C O S   D E   L A   C E N I Z A',
                      style: TextStyle(color: gold, fontSize: 12, height: 2),
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(
                      width: 600,
                      child: Text(
                        'Tres sellos guardan el corazón de un reino caído. Cruza el bosque, desciende a la cripta y acaba con el Rey de Ceniza.',
                        style: TextStyle(
                          color: Color(0xffb7c2bd),
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _Tag(Icons.explore_outlined, '4 zonas conectadas'),
                        _Tag(Icons.auto_awesome, 'Botín y hechizos'),
                        _Tag(Icons.save_outlined, 'Guardado local'),
                        _Tag(Icons.cloud_outlined, 'Firebase cooperativo'),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Text(
                          'ELIGE TU CLASE',
                          style: TextStyle(
                            color: gold,
                            fontSize: 11,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: gold.withValues(alpha: .2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, box) {
                        final narrow = box.maxWidth < 580;
                        final cards = HeroClass.values
                            .map((type) => _classCard(type, compact: narrow))
                            .toList();
                        return narrow
                            ? Column(
                                children: cards
                                    .map(
                                      (c) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: c,
                                      ),
                                    )
                                    .toList(),
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < cards.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 12),
                                    Expanded(child: cards[i]),
                                  ],
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (widget.saved != null)
                          FilledButton.icon(
                            onPressed: widget.onContinue,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              'Continuar · Nv. ${widget.saved!.level}',
                            ),
                          ),
                        if (widget.saved == null)
                          FilledButton.icon(
                            onPressed: start,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Comenzar aventura'),
                          )
                        else
                          OutlinedButton(
                            onPressed: start,
                            child: const Text('Nueva aventura'),
                          ),
                        TextButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => const HelpDialog(),
                          ),
                          icon: const Icon(Icons.help_outline, size: 18),
                          label: const Text('Cómo jugar'),
                        ),
                      ],
                    ),
                    if (widget.saved != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '${widget.saved!.heroClass.label} · ${widget.saved!.zone.name} · ${widget.saved!.seals.length}/3 sellos',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    if (widget.warning != null)
                      Text(
                        widget.warning!,
                        style: const TextStyle(color: gold),
                      ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => widget.onOnline(context, selected),
                      icon: const Icon(Icons.groups_outlined),
                      label: const Text('Firebase · Nube y cooperativo'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'AVENTURA INDIVIDUAL O COOPERATIVA  •  2 JUGADORES',
                      style: TextStyle(
                        color: muted,
                        letterSpacing: 1.5,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _classCard(HeroClass type, {required bool compact}) {
    final active = selected == type, color = Color(type.color);
    final art = SizedBox(
      width: compact ? 65 : double.infinity,
      height: compact ? 77 : 100,
      child: CustomPaint(painter: PortraitPainter(type)),
    );
    final text = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          type.label,
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 21,
            color: active ? color : Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(type.role, style: const TextStyle(color: muted, fontSize: 11)),
        if (!compact) ...[
          const SizedBox(height: 14),
          Text(
            type.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xffbcc5bf),
              height: 1.5,
            ),
          ),
        ],
      ],
    );
    return Semantics(
      selected: active,
      button: true,
      label: 'Clase ${type.label}',
      child: InkWell(
        onTap: () => setState(() => selected = type),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(compact ? 10 : 18),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: .10)
                : const Color(0xff162328).withValues(alpha: .8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color : const Color(0xff344447)),
          ),
          child: compact
              ? Row(
                  children: [
                    art,
                    const SizedBox(width: 14),
                    Expanded(child: text),
                    Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: active ? color : muted,
                      size: 18,
                    ),
                  ],
                )
              : Column(mainAxisSize: MainAxisSize.min, children: [art, text]),
        ),
      ),
    );
  }
}

class PortraitPainter extends CustomPainter {
  final HeroClass type;
  PortraitPainter(this.type);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.height * .44,
      Paint()..color = Color(type.color).withValues(alpha: .05),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height - 8);
    canvas.scale(size.height / 90);
    WorldPainter.drawHero(canvas, Offset.zero, type);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PortraitPainter oldDelegate) =>
      oldDelegate.type != type;
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tag(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: teal, size: 15),
      const SizedBox(width: 7),
      Text(text, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

class GameScreen extends StatefulWidget {
  final CloudService? cloud;
  final CoopSession? coop;
  final Game game;
  final SaveStore store;
  final VoidCallback onExit;
  const GameScreen({
    super.key,
    required this.game,
    required this.store,
    required this.onExit,
    this.cloud,
    this.coop,
  });
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker ticker;
  final FocusNode focus = FocusNode();
  Duration last = Duration.zero;
  late final Timer autosave;
  bool modal = false, victorySeen = false, backgrounded = false;
  String? saveError;
  Game get g => widget.game;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    victorySeen = g.won;
    widget.coop?.addListener(_sessionChanged);
    ticker = createTicker((elapsed) {
      final dt = (elapsed - last).inMicroseconds / 1000000;
      last = elapsed;
      final session = widget.coop;
      g.networkBlocked =
          session != null &&
          (!session.ready || !session.healthy || session.closed);
      if (!g.won || victorySeen) {
        if (widget.coop != null) {
          widget.coop!.frame(dt);
        } else {
          g.tick(dt);
        }
      }
    })..start();
    autosave = Timer.periodic(const Duration(seconds: 8), (_) => save());
  }

  @override
  void dispose() {
    widget.coop?.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    autosave.cancel();
    ticker.dispose();
    focus.dispose();
    g.stop();
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> save() async {
    try {
      await widget.store.save(g);
      unawaited(widget.cloud?.autoUpload(g) ?? Future<void>.value());
      if (mounted && saveError != null) setState(() => saveError = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError = 'Error al guardar. Comprueba el almacenamiento.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      backgrounded = true;
      widget.coop?.backgrounded = true;
      g.setPaused(true);
      unawaited(save());
    } else if (backgrounded) {
      backgrounded = false;
      widget.coop?.backgrounded = false;
      if (!modal) g.setPaused(false);
    }
  }

  Future<void> sheet(String title, Widget Function(BuildContext) body) async {
    if (modal) return;
    modal = true;
    g.setPaused(true);
    await save();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xff47534b)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740, maxHeight: 650),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 24,
                          color: gold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Volver al juego',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: AnimatedBuilder(
                  animation: g,
                  builder: (_, _) => SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: body(dialogContext),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    modal = false;
    g.setPaused(backgrounded);
    focus.requestFocus();
    await save();
  }

  Future<void> inventory() =>
      sheet('Equipo y mochila', (_) => InventoryPanel(game: g));
  Future<void> map() => sheet(
    'Atlas de los ecos',
    (ctx) => MapPanel(
      game: g,
      onTravel: (id) {
        if (g.enter(id, fast: true)) Navigator.pop(ctx);
      },
    ),
  );
  Future<void> pause() => sheet(
    'Un momento junto al fuego',
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'PARTIDA EN PAUSA',
          style: TextStyle(color: teal, letterSpacing: 2, fontSize: 11),
        ),
        const SizedBox(height: 16),
        Text(g.objective),
        if (widget.coop != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              container: true,
              label: 'Código: ${widget.coop!.code}',
              child: SelectableText(
                'Código: ${widget.coop!.code}\n${widget.coop!.banner}',
              ),
            ),
          ),
        if (widget.cloud != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              widget.cloud!.status,
              style: const TextStyle(color: teal, fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Seguir explorando'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const HelpDialog(),
          ),
          child: const Text('Controles y consejos'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () async {
            await save();
            if (!ctx.mounted || !mounted) return;
            if (saveError != null) return;
            Navigator.pop(ctx);
            widget.onExit();
          },
          child: const Text('Guardar y volver al inicio'),
        ),
        if (saveError != null)
          Text(saveError!, style: const TextStyle(color: gold)),
        const SizedBox(height: 18),
        const Text(
          'Guardado automático cada 8 s y al abrir/cerrar paneles.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
  );

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (modal || g.dead || (g.won && !victorySeen)) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    double axis(
      LogicalKeyboardKey a,
      LogicalKeyboardKey b,
      LogicalKeyboardKey c,
      LogicalKeyboardKey d,
    ) =>
        (keys.contains(a) || keys.contains(b) ? 1 : 0) -
        (keys.contains(c) || keys.contains(d) ? 1 : 0);
    g.steer(
      Offset(
        axis(
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.arrowLeft,
        ),
        axis(
          LogicalKeyboardKey.keyS,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.arrowUp,
        ),
      ),
    );
    g.attacking = keys.contains(LogicalKeyboardKey.space);
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyQ) g.castPrimary();
      if (key == LogicalKeyboardKey.keyE) g.castWard();
      if (key == LogicalKeyboardKey.keyH) g.drinkPotion();
      if (key == LogicalKeyboardKey.keyF) {
        if (g.atPortal && g.interaction.contains('Portal')) {
          map();
        } else {
          g.interact();
        }
      }
      if (key == LogicalKeyboardKey.keyI || key == LogicalKeyboardKey.tab) {
        inventory();
      }
      if (key == LogicalKeyboardKey.keyM) map();
      if (key == LogicalKeyboardKey.escape) pause();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !modal) pause();
    },
    child: Scaffold(
      body: Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: onKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final small = constraints.maxWidth < 620,
                short = constraints.maxHeight < 480;
            return AnimatedBuilder(
              animation: g,
              builder: (context, _) => Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        focus.requestFocus();
                        g.tapWorld(
                          WorldPainter.screenToWorld(
                            details.localPosition,
                            constraints.biggest,
                            g,
                          ),
                        );
                      },
                      child: RepaintBoundary(
                        child: CustomPaint(painter: WorldPainter(g)),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: small ? 226 : 310,
                                    child: _vitals(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _panel(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _topButton(
                                          Icons.backpack_outlined,
                                          'Mochila [I]',
                                          inventory,
                                        ),
                                        _topButton(
                                          Icons.map_outlined,
                                          'Mapa [M]',
                                          map,
                                        ),
                                        _topButton(Icons.pause, 'Pausa', pause),
                                      ],
                                    ),
                                  ),
                                  if (!small && !short) ...[
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: map,
                                      child: _panel(
                                        child: SizedBox(
                                          width: 148,
                                          height: 95,
                                          child: CustomPaint(
                                            painter: MiniMapPainter(
                                              g,
                                              g.zoneId,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          if (widget.coop != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                widget.coop!.banner,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: teal,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          if (!short)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _panel(
                                  child: SizedBox(
                                    width: small ? 240 : 310,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            g.zone.name.toUpperCase(),
                                            style: const TextStyle(
                                              color: gold,
                                              letterSpacing: 1.4,
                                              fontSize: 10,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            g.objective,
                                            style: const TextStyle(
                                              color: Color(0xffc2ccc5),
                                              fontSize: 11,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (saveError != null)
                            Text(
                              saveError!,
                              style: const TextStyle(color: gold, fontSize: 11),
                            ),
                          if (g.messageTime > 0 && !short)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: IgnorePointer(
                                child: _panel(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      g.message,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xffe4d5b8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (g.interaction.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: small ? 300 : 430,
                                ),
                                child: FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xee263e39),
                                    foregroundColor: const Color(0xffc4e4d2),
                                    minimumSize: const Size(48, 42),
                                  ),
                                  onPressed: () {
                                    if (g.atPortal &&
                                        g.interaction.contains('Portal')) {
                                      map();
                                    } else {
                                      g.interact();
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.pan_tool_alt_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    g.interaction,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Joystick(onChanged: g.steer, compact: short),
                              const Spacer(),
                              _combatControls(small || short),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (g.dead) _endCard(false),
                  if (g.won && !victorySeen && !g.dead) _endCard(true),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _topButton(IconData icon, String tooltip, VoidCallback action) =>
      IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 42, minHeight: 44),
        padding: const EdgeInsets.all(8),
        onPressed: action,
        icon: Icon(icon, color: const Color(0xffddd4bd), size: 21),
      );
  Widget _vitals() => _panel(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withValues(alpha: .12),
                  border: Border.all(color: gold.withValues(alpha: .5)),
                ),
                child: Text(
                  '${g.level}',
                  style: const TextStyle(
                    color: gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  g.heroClass.label,
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 17),
                ),
              ),
              const Icon(Icons.toll, size: 13, color: gold),
              const SizedBox(width: 4),
              Text(
                '${g.gold}',
                style: const TextStyle(color: gold, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _bar(
            g.hp / g.maxHp,
            const Color(0xffb45f58),
            '${g.hp.ceil()} / ${g.maxHp.round()}',
          ),
          const SizedBox(height: 5),
          _bar(
            g.mana / g.maxMana,
            const Color(0xff668ea7),
            '${g.mana.floor()} energía',
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (g.xp / g.nextLevelXp).clamp(0, 1),
              minHeight: 2,
              backgroundColor: const Color(0xff35413b),
              color: gold,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _bar(double value, Color color, String text) => SizedBox(
    height: 15,
    child: Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value.clamp(0, 1),
              backgroundColor: const Color(0xff111b1e),
              color: color,
            ),
          ),
        ),
        Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xfff3eee5),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _combatControls(bool compact) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _skill(
            Icons.local_drink_outlined,
            'Poción · ${g.potions}',
            g.potionCooldown,
            () => g.drinkPotion(),
            color: const Color(0xffd19082),
            small: compact,
          ),
          const SizedBox(width: 7),
          _skill(
            Icons.shield_outlined,
            'Amparo',
            g.wardCooldown,
            () => g.castWard(),
            color: teal,
            small: compact,
            disabled: g.mana < 20,
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _skill(
            Icons.auto_awesome,
            ['Torbellino', 'Nova', 'Lluvia'][g.heroClass.index],
            g.skillCooldown,
            () => g.castPrimary(),
            color: Color(g.heroClass.color),
            small: compact,
            disabled: g.mana < 28,
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Atacar. Mantener pulsado',
            child: Listener(
              onPointerDown: (_) {
                g.attacking = true;
                g.basicAttack();
              },
              onPointerUp: (_) => g.attacking = false,
              onPointerCancel: (_) => g.attacking = false,
              child: Container(
                width: compact ? 72 : 86,
                height: compact ? 72 : 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xee3a3630),
                  border: Border.all(
                    color: gold.withValues(alpha: .85),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x55000000), blurRadius: 15),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sports_martial_arts, size: 29, color: gold),
                    SizedBox(height: 3),
                    Text(
                      'ATACAR',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 1.2,
                        color: gold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  Widget _skill(
    IconData icon,
    String label,
    double cooldown,
    VoidCallback action, {
    required Color color,
    required bool small,
    bool disabled = false,
  }) => Tooltip(
    message: label,
    child: SizedBox(
      width: small ? 62 : 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: small ? 52 : 60,
            height: small ? 52 : 60,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: const Color(0xe6142226),
                side: BorderSide(color: color.withValues(alpha: .5)),
                shape: const CircleBorder(),
              ),
              onPressed: cooldown > 0 || disabled ? null : action,
              child: cooldown > 0
                  ? Text(
                      '${cooldown.ceil()}',
                      style: TextStyle(color: color, fontSize: 18),
                    )
                  : Icon(icon, color: disabled ? muted : color, size: 24),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 9, color: color), maxLines: 1),
        ],
      ),
    ),
  );
  Widget _endCard(bool victory) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xd9081115),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _panel(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      victory ? Icons.wb_twilight : Icons.brightness_3_outlined,
                      color: gold,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      victory ? 'El alba regresa' : 'La llama aún vive',
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 30,
                        color: gold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      victory
                          ? 'Has roto los tres sellos y derrotado al Rey de Ceniza. El reino recuerda tu nombre.'
                          : 'Regresa al refugio con tu equipo y progreso. Pierdes hasta 15 monedas y recuperas al menos tres pociones.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Nivel ${g.level}  ·  ${g.kills} enemigos  ·  ${g.seals.length}/3 sellos',
                      style: const TextStyle(color: teal, fontSize: 12),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        if (victory) {
                          setState(() => victorySeen = true);
                        } else {
                          g.respawn();
                        }
                        unawaited(save());
                      },
                      child: Text(
                        victory ? 'Seguir explorando' : 'Volver al refugio',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _panel({required Widget child}) => DecoratedBox(
  decoration: BoxDecoration(
    color: const Color(0xe6111e22),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: const Color(0xff3b4945)),
    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12)],
  ),
  child: child,
);

class Joystick extends StatefulWidget {
  final ValueChanged<Offset> onChanged;
  final bool compact;
  const Joystick({super.key, required this.onChanged, this.compact = false});
  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset delta = Offset.zero;
  int? pointer;
  double get size => widget.compact ? 100 : 122;
  void move(Offset local) {
    final d = (local - Offset(size / 2, size / 2)) / (size * .32);
    setState(() => delta = d.distance > 1 ? d / d.distance : d);
    widget.onChanged(delta);
  }

  void stop() {
    pointer = null;
    setState(() => delta = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Palanca de movimiento',
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (pointer == null) {
          pointer = e.pointer;
          move(e.localPosition);
        }
      },
      onPointerMove: (e) {
        if (pointer == e.pointer) move(e.localPosition);
      },
      onPointerUp: (e) {
        if (pointer == e.pointer) stop();
      },
      onPointerCancel: (e) {
        if (pointer == e.pointer) stop();
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size - 8,
              height: size - 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xa6142226),
                border: Border.all(
                  color: const Color(0xff657569).withValues(alpha: .5),
                ),
              ),
            ),
            Icon(
              Icons.add,
              color: muted.withValues(alpha: .3),
              size: size - 30,
            ),
            Transform.translate(
              offset: delta * size * .26,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xe641514c),
                  border: Border.all(
                    color: const Color(0xffa5b4a1),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.navigation_outlined,
                  color: Color(0xffc5cebb),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class InventoryPanel extends StatelessWidget {
  final Game game;
  const InventoryPanel({super.key, required this.game});
  @override
  Widget build(BuildContext context) {
    final g = game;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${g.heroClass.label} · NIVEL ${g.level}',
          style: const TextStyle(color: teal, letterSpacing: 1),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            _Tag(Icons.bolt, '${g.attack} daño'),
            _Tag(Icons.shield_outlined, '${g.armor} armadura'),
            _Tag(Icons.favorite_outline, '${g.maxHp.round()} vida'),
            _Tag(Icons.toll, '${g.gold} monedas'),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'EQUIPADO',
          style: TextStyle(color: gold, letterSpacing: 2, fontSize: 11),
        ),
        const SizedBox(height: 8),
        for (final slot in Slot.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _panel(
              child: ListTile(
                leading: Icon(
                  _slotIcon(slot),
                  color: g.equipment[slot] == null
                      ? muted
                      : Color(g.equipment[slot]!.color),
                ),
                title: Text(
                  g.equipment[slot]?.name ?? '${slot.label} • vacío',
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  g.equipment[slot] == null
                      ? 'Busca botín en cofres y monstruos'
                      : _stats(g.equipment[slot]!),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                trailing: Text(
                  slot.label,
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            Text(
              'MOCHILA ${g.inventory.length}/24',
              style: const TextStyle(
                color: gold,
                letterSpacing: 2,
                fontSize: 11,
              ),
            ),
            if (g.zoneId == 0)
              const Text(
                'Mercader disponible',
                style: TextStyle(color: teal, fontSize: 10),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (g.inventory.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Tu mochila está vacía. Abre cofres y recoge el botín brillante de los enemigos con el botón de interacción.',
              style: TextStyle(color: muted),
            ),
          ),
        for (final item in g.inventory.toList())
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(item.color).withValues(alpha: .06),
              border: Border.all(
                color: Color(item.color).withValues(alpha: .25),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _slotIcon(item.slot),
                      color: Color(item.color),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          color: Color(item.color),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      item.rarity,
                      style: TextStyle(color: Color(item.color), fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_stats(item), style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  _comparison(item, g.equipment[item.slot]),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => g.equip(item),
                      child: const Text('Equipar'),
                    ),
                    if (g.zoneId == 0)
                      OutlinedButton(
                        onPressed: () => g.sell(item),
                        child: Text('Vender · ${item.price} oro'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (g.zoneId == 0) ...[
          const Divider(height: 28),
          const Text(
            'SUMINISTROS DEL REFUGIO',
            style: TextStyle(color: gold, fontSize: 11, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Llevas ${g.potions} pociones. Cada una restaura el 55% de vida.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: g.gold >= 20 ? () => g.buyPotion() : null,
            icon: const Icon(Icons.local_drink_outlined),
            label: const Text('Comprar poción · 20 oro'),
          ),
        ] else
          const Text(
            'Vuelve al Refugio para vender equipo y comprar pociones.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
      ],
    );
  }

  static IconData _slotIcon(Slot slot) =>
      [Icons.bolt, Icons.shield_outlined, Icons.diamond_outlined][slot.index];
  static String _stats(Item i) => [
    if (i.power > 0) '+${i.power} daño',
    if (i.armor > 0) '+${i.armor} armadura',
    if (i.vitality > 0) '+${i.vitality} vida',
  ].join('  ·  ');
  static String _comparison(Item item, Item? old) {
    String signed(int n) => n >= 0 ? '+$n' : '$n';
    return 'Al equipar: ${signed(item.power - (old?.power ?? 0))} daño / ${signed(item.armor - (old?.armor ?? 0))} armadura / ${signed(item.vitality - (old?.vitality ?? 0))} vida';
  }
}

class MapPanel extends StatefulWidget {
  final Game game;
  final ValueChanged<int> onTravel;
  const MapPanel({super.key, required this.game, required this.onTravel});
  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  late int selected = widget.game.zoneId;
  @override
  Widget build(BuildContext context) {
    final g = widget.game, zone = Zone.all[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${g.seals.length} DE 3 SELLOS RECUPERADOS',
          style: const TextStyle(color: teal, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Text(g.objective, style: const TextStyle(color: muted)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final z in Zone.all)
              ChoiceChip(
                label: Text(z.name, style: const TextStyle(fontSize: 11)),
                selected: selected == z.id,
                onSelected: (_) => setState(() => selected = z.id),
                avatar: Icon(
                  g.seals.contains(z.id)
                      ? Icons.check_circle_outline
                      : g.portals.contains(z.id)
                      ? Icons.explore_outlined
                      : Icons.lock_outline,
                  size: 16,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AspectRatio(
          aspectRatio: 1.65,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xff46564e)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: CustomPaint(painter: MiniMapPainter(g, selected)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Tag(Icons.circle, 'Blanco: tú'),
            _Tag(Icons.auto_awesome, 'Verde: portal'),
            _Tag(Icons.warning_amber, 'Rojo: enemigos'),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          zone.name,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 24,
            color: gold,
          ),
        ),
        Text(
          zone.subtitle,
          style: const TextStyle(color: muted, letterSpacing: 1, fontSize: 10),
        ),
        const SizedBox(height: 12),
        Text(
          g.portals.contains(selected)
              ? 'Portal descubierto. El terreno oscuro aún no ha sido explorado.'
              : 'Explora a pie para descubrir y activar el portal de esta zona.',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed:
              g.canTravel &&
                  g.portals.contains(selected) &&
                  selected != g.zoneId
              ? () => widget.onTravel(selected)
              : null,
          icon: const Icon(Icons.auto_awesome),
          label: Text(
            selected == g.zoneId
                ? 'Estás en esta zona'
                : 'Viajar a ${zone.name}',
          ),
        ),
        if (!g.canTravel)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Acércate al portal de tu zona para usar el viaje rápido.',
              style: TextStyle(color: gold, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class HelpDialog extends StatelessWidget {
  const HelpDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      'Tu primera expedición',
      style: TextStyle(fontFamily: 'Georgia', color: gold),
    ),
    content: const SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'EXPLORA · COMBATE · MEJORA',
              style: TextStyle(color: teal, letterSpacing: 2, fontSize: 11),
            ),
            SizedBox(height: 14),
            Text(
              '1. Mueve la palanca o toca el terreno para caminar. El camino del este conecta las zonas. Usa Interactuar junto a una salida.\n\n2. Mantén ATACAR para golpear al enemigo más cercano. Tocar un monstruo hace que te acerques y ataques. La Arcanista y la Exploradora atacan a distancia.\n\n3. La habilidad ofensiva cuesta 28 de energía; Amparo cuesta 20, cura y reduce el daño durante 4 s. La energía se regenera. Sal de los círculos rojos antes de que exploten.\n\n4. Acércate a cofres y al botín brillante y usa Interactuar. Abre la mochila para comparar y equipar. En el Refugio puedes vender equipo y comprar pociones.\n\n5. Los portales se activan al acercarte. Abre el mapa junto a uno para viajar a cualquier otro descubierto.\n\n6. Derrota al guardián del Bosque para abrir la Cripta; al de la Cripta para acceder al Rey de Ceniza. Morir conserva tu equipo y progreso.',
            ),
            SizedBox(height: 20),
            Text(
              'TECLADO',
              style: TextStyle(color: gold, letterSpacing: 2, fontSize: 11),
            ),
            SizedBox(height: 8),
            Text(
              'WASD / flechas: moverse\nEspacio: atacar · Q: habilidad · E: amparo\nH: poción · F: interactuar\nI / Tab: mochila · M: mapa · Esc: pausa',
            ),
            SizedBox(height: 18),
            Text(
              'Los paneles pausan la partida. Guardado local automático; una partida por instalación. Arte vectorial original generado con Flutter Canvas.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Entendido'),
      ),
    ],
  );
}
