import 'dart:math';

import 'package:flutter/material.dart';

import 'game.dart';
import 'world.dart';

class WorldPainter extends CustomPainter {
  final Game game;
  final bool cinematic;
  WorldPainter(this.game, {this.cinematic = false}) : super(repaint: game);

  static double zoom(Size size) => size.width < 600 ? .78 : 1.0;
  static Offset screenToWorld(Offset point, Size size, Game game) =>
      (point - Offset(size.width / 2, size.height * .48)) / zoom(size) +
      game.position;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = zoom(size);
    final origin =
        Offset(size.width / 2, size.height * .48) - game.position * scale;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff101819),
    );
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final view = Rect.fromLTWH(
      -origin.dx / scale - 140,
      -origin.dy / scale - 170,
      size.width / scale + 280,
      size.height / scale + 340,
    );
    final zone = game.zone;
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, Zone.width, Zone.height),
      Paint()..color = Color(zone.ground),
    );
    final rng = Random(426 + zone.id);
    for (var i = 0; i < 2000; i++) {
      final p = Offset(
        rng.nextDouble() * Zone.width,
        rng.nextDouble() * Zone.height,
      );
      final radius = rng.nextDouble() * 20 + 3;
      if (!view.contains(p)) continue;
      canvas.drawOval(
        Rect.fromCenter(center: p, width: radius * 2, height: radius * .6),
        Paint()
          ..color = (i % 2 == 0 ? Colors.white : Colors.black).withValues(
            alpha: .025 + i % 3 * .012,
          ),
      );
    }
    // Worn stone road links the entrance, waystone and the guardian arena.
    final road = Path()
      ..moveTo(110, 800)
      ..cubicTo(700, 830, 1300, 760, 2090, 800);
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xff938577).withValues(alpha: .12)
        ..strokeWidth = 165
        ..style = PaintingStyle.stroke,
    );
    for (var x = 100.0; x < 2110; x += 58) {
      for (var row = 0; row < 3; row++) {
        final y = 746 + row * 47.0 + sin(x * .006) * 11;
        final stone = Rect.fromLTWH(x + (row.isEven ? 0 : 23), y, 48, 37);
        if (!view.overlaps(stone)) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(stone, const Radius.circular(5)),
          Paint()
            ..color = Color(zone.id == 2 ? 0xff454550 : 0xff5b5c50)
                .withValues(alpha: .32),
        );
        canvas.drawLine(
          stone.topLeft + const Offset(4, 0),
          stone.topRight - const Offset(4, 0),
          Paint()
            ..color = Colors.white.withValues(alpha: .045)
            ..strokeWidth = 2,
        );
      }
    }
    if (zone.id == 0) {
      canvas.drawCircle(
        const Offset(1060, 800),
        145,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xffeda357).withValues(alpha: .11),
              Colors.transparent,
            ],
          ).createShader(const Rect.fromLTWH(915, 655, 290, 290)),
      );
    }
    final accent = Color(zone.accent);
    for (final gate in zone.gates) {
      _runeCircle(canvas, gate.position, 48, accent.withValues(alpha: .55));
      for (final dx in [-52.0, 52.0]) {
        _pillar(canvas, gate.position + Offset(dx, 0), accent);
      }
      _label(
        canvas,
        gate.label.toUpperCase(),
        gate.position + const Offset(0, -95),
        accent,
        12,
      );
      _label(
        canvas,
        game.unlocked(gate.target) ? 'PASO ENTRE ZONAS' : 'REQUIERE UN SELLO',
        gate.position + const Offset(0, 60),
        const Color(0xffa3aaa5),
        9,
      );
    }
    final portal = zone.portal;
    _runeCircle(canvas, portal, 65, const Color(0xff76cec1));
    canvas.drawOval(
      Rect.fromCenter(
        center: portal - const Offset(0, 36),
        width: 44 + sin(game.time * 2) * 4,
        height: 94,
      ),
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xffc3f7e4).withValues(alpha: .6),
                const Color(0xff75d8bf).withValues(alpha: .05),
              ],
            ).createShader(
              Rect.fromCenter(
                center: portal - const Offset(0, 36),
                width: 50,
                height: 100,
              ),
            ),
    );
    _pillar(canvas, portal + const Offset(-40, 0), const Color(0xff79d7c8));
    _pillar(canvas, portal + const Offset(40, 0), const Color(0xff79d7c8));
    _label(
      canvas,
      'PORTAL DEL ALBA',
      portal + const Offset(0, -105),
      const Color(0xffb2e1d3),
      10,
    );

    for (final h in game.hazards) {
      canvas.drawCircle(
        h.position,
        h.radius,
        Paint()
          ..color = const Color(0xffff5b3e)
              .withValues(alpha: .10 + (1.15 - h.remaining) * .12),
      );
      canvas.drawCircle(
        h.position,
        h.radius,
        Paint()
          ..color = const Color(0xffff9f74)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        h.position,
        h.radius * (1 - h.remaining / 1.15).clamp(0, 1),
        Paint()
          ..color = const Color(0xffff7c4b).withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    final drawables = <({double y, VoidCallback draw})>[];
    for (final obstacle in zone.obstacles) {
      if (!view.overlaps(obstacle.inflate(160))) continue;
      drawables.add((
        y: obstacle.bottom,
        draw: () {
          if (zone.id == 0) {
            _house(canvas, obstacle);
          } else if (zone.id == 1) {
            _tree(canvas, obstacle);
          } else {
            _ruin(canvas, obstacle, zone.id == 3);
          }
        },
      ));
    }
    for (final chest in game.state.chests) {
      drawables.add((
        y: chest.position.dy,
        draw: () => _chest(canvas, chest.position, chest.opened),
      ));
    }
    for (final drop in game.state.drops) {
      final p = drop.position, color = Color(drop.item.color);
      canvas.drawOval(
        Rect.fromCenter(center: p, width: 36, height: 18),
        Paint()..color = color.withValues(alpha: .18),
      );
      canvas.drawRect(
        Rect.fromLTWH(p.dx - 2, p.dy - 65, 4, 65),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0), color.withValues(alpha: .6)],
          ).createShader(Rect.fromLTWH(p.dx - 2, p.dy - 65, 4, 65)),
      );
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - 14)
          ..lineTo(p.dx + 8, p.dy - 5)
          ..lineTo(p.dx, p.dy + 3)
          ..lineTo(p.dx - 8, p.dy - 5)
          ..close(),
        Paint()..color = color,
      );
      if ((p - game.position).distance < 120) {
        _label(canvas, drop.item.name, p + const Offset(0, -82), color, 11);
      }
    }
    if (zone.id == 0) {
      drawables.add((
        y: 820,
        draw: () => _bonfire(canvas, const Offset(1060, 800)),
      ));
    }
    for (final m in game.state.monsters) {
      if (!view.contains(m.position)) continue;
      if (!game.state.explored.contains(
        (m.position.dy ~/ 80) * 28 + m.position.dx ~/ 80,
      )) {
        continue;
      }
      drawables.add((y: m.position.dy, draw: () => _monster(canvas, m)));
    }
    drawables.add((
      y: game.position.dy,
      draw: () {
        if (game.wardTime > 0) {
          canvas.drawCircle(
            game.position - const Offset(0, 22),
            47,
            Paint()..color = Color(game.heroClass.color).withValues(alpha: .12),
          );
          canvas.drawCircle(
            game.position - const Offset(0, 22),
            47,
            Paint()
              ..color = Color(game.heroClass.color).withValues(alpha: .6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        drawHero(
          canvas,
          game.position,
          game.heroClass,
          time: game.time,
          moving: game.movement.distance > .05 || game.route.isNotEmpty,
          facing: game.facing,
          dead: game.dead,
        );
      },
    ));
    final companion = game.companion;
    if (companion != null && companion.zoneId == game.zoneId) {
      drawables.add((
        y: companion.position.dy,
        draw: () {
          drawHero(
            canvas,
            companion.position,
            companion.heroClass,
            time: game.time,
            facing: companion.facing,
            dead: companion.dead,
          );
          _label(
            canvas,
            'COMPAÑERO · ${companion.hp.ceil()}',
            companion.position - const Offset(0, 100),
            const Color(0xff84cbb8),
            10,
          );
        },
      ));
    }
    drawables.sort((a, b) => a.y.compareTo(b.y));
    for (final drawable in drawables) {
      drawable.draw();
    }
    for (final effect in game.effects) {
      _effect(canvas, effect);
    }
    if (!cinematic) {
      final fog = Paint()
        ..color = const Color(0xff0a1214).withValues(alpha: .94);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 28; x++) {
          final rect = Rect.fromLTWH(x * 80, y * 80, 80.5, 80.5);
          if (view.overlaps(rect) &&
              !game.state.explored.contains(y * 28 + x)) {
            canvas.drawRect(rect, fog);
          }
        }
      }
    }
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: .9,
          colors: [
            Colors.transparent,
            const Color(0xff081012).withValues(alpha: .55),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  void _runeCircle(Canvas c, Offset p, double radius, Color color) {
    c.drawOval(
      Rect.fromCenter(center: p, width: radius * 2.2, height: radius * 1.25),
      Paint()..color = color.withValues(alpha: .07),
    );
    for (final r in [radius, radius - 10]) {
      c.drawOval(
        Rect.fromCenter(center: p, width: r * 2, height: r),
        Paint()
          ..color = color.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    for (var i = 0; i < 10; i++) {
      final a = i * pi / 5 + game.time * .06;
      final at = p + Offset(cos(a) * (radius - 5), sin(a) * (radius - 5) / 2);
      c.drawLine(
        at,
        at + Offset(cos(a) * 7, sin(a) * 7),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
    }
  }

  void _pillar(Canvas c, Offset p, Color accent) {
    _shadow(c, p, 30);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(p.dx - 13, p.dy - 70, 26, 76),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xff46534e),
    );
    c.drawRect(
      Rect.fromLTWH(p.dx - 12, p.dy - 68, 8, 71),
      Paint()..color = const Color(0xff657369),
    );
    c.drawLine(
      p + const Offset(2, -53),
      p + const Offset(2, -20),
      Paint()
        ..color = accent
        ..strokeWidth = 3,
    );
    c.drawCircle(p - const Offset(0, 78), 6, Paint()..color = accent);
  }

  void _house(Canvas c, Rect r) {
    _shadow(c, Offset(r.center.dx, r.bottom), r.width * .65);
    c.drawRect(r, Paint()..color = const Color(0xff55584b));
    c.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width * .3, r.height),
      Paint()..color = const Color(0xff414a42),
    );
    final roof = Path()
      ..moveTo(r.left - 22, r.top + 20)
      ..lineTo(r.center.dx, r.top - 75)
      ..lineTo(r.right + 22, r.top + 20)
      ..lineTo(r.right, r.top + 60)
      ..lineTo(r.center.dx, r.top - 27)
      ..lineTo(r.left, r.top + 60)
      ..close();
    c.drawPath(roof, Paint()..color = const Color(0xff6b4e42));
    c.drawLine(
      Offset(r.center.dx, r.top - 72),
      Offset(r.right + 22, r.top + 20),
      Paint()
        ..color = const Color(0xffac8970)
        ..strokeWidth = 3,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.center.dx - 20, r.bottom - 64, 40, 64),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xff222e2b),
    );
    for (final x in [r.left + 26, r.right - 44]) {
      c.drawRect(
        Rect.fromLTWH(x, r.bottom - 87, 22, 31),
        Paint()..color = const Color(0xffefbf73),
      );
      c.drawLine(
        Offset(x + 11, r.bottom - 87),
        Offset(x + 11, r.bottom - 56),
        Paint()
          ..color = const Color(0xff63513c)
          ..strokeWidth = 3,
      );
    }
  }

  void _tree(Canvas c, Rect r) {
    final p = Offset(r.center.dx, r.bottom);
    _shadow(c, p, r.width * .8);
    c.drawPath(
      Path()
        ..moveTo(p.dx - 12, p.dy)
        ..lineTo(p.dx - 7, p.dy - 105)
        ..lineTo(p.dx + 5, p.dy - 110)
        ..lineTo(p.dx + 16, p.dy)
        ..close(),
      Paint()..color = const Color(0xff4e4635),
    );
    for (var i = 0; i < 4; i++) {
      final top = p - Offset(0, 170 - i * 28.0),
          spread = r.width * (.35 + i * .16);
      c.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..lineTo(top.dx + spread, top.dy + 72)
          ..quadraticBezierTo(top.dx, top.dy + 55, top.dx - spread, top.dy + 72)
          ..close(),
        Paint()
          ..color = [
            const Color(0xff344f42),
            const Color(0xff304b3e),
            const Color(0xff2b4438),
            const Color(0xff263e32),
          ][i],
      );
      c.drawLine(
        top,
        top + Offset(-spread, 72),
        Paint()
          ..color = const Color(0xff698367).withValues(alpha: .4)
          ..strokeWidth = 2,
      );
    }
  }

  void _ruin(Canvas c, Rect r, bool lava) {
    final p = r.bottomCenter;
    _shadow(c, p, r.width * .8);
    final rock = Path()
      ..moveTo(r.left - 4, r.bottom)
      ..lineTo(r.left + 5, r.top - 35)
      ..lineTo(r.center.dx, r.top - 58)
      ..lineTo(r.right, r.top - 25)
      ..lineTo(r.right + 8, r.bottom)
      ..close();
    c.drawPath(rock, Paint()..color = Color(lava ? 0xff4a3833 : 0xff494955));
    c.drawPath(
      Path()
        ..moveTo(r.center.dx, r.top - 55)
        ..lineTo(r.center.dx + 8, r.bottom)
        ..lineTo(r.left - 4, r.bottom)
        ..lineTo(r.left + 5, r.top - 35)
        ..close(),
      Paint()..color = Color(lava ? 0xff665045 : 0xff62616b),
    );
    c.drawPath(
      Path()
        ..moveTo(r.center.dx + 4, r.top - 20)
        ..lineTo(r.center.dx - 5, r.top + 14)
        ..lineTo(r.center.dx + 12, r.top + 20)
        ..lineTo(r.center.dx + 3, r.bottom - 10),
      Paint()
        ..color = Color(lava ? 0xffd88050 : 0xffaaa0cc)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _chest(Canvas c, Offset p, bool opened) {
    _shadow(c, p, 31);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(p.dx - 24, p.dy - 30, 48, 32),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xff79553c),
    );
    c.drawRect(
      Rect.fromLTWH(p.dx - 25, p.dy - (opened ? 43 : 32), 50, 12),
      Paint()..color = const Color(0xffa1794a),
    );
    for (final dx in [-15.0, 12.0]) {
      c.drawRect(
        Rect.fromLTWH(p.dx + dx, p.dy - 31, 4, 32),
        Paint()..color = const Color(0xffccae70),
      );
    }
    if (!opened) {
      c.drawCircle(
        p - const Offset(0, 17),
        4,
        Paint()..color = const Color(0xfff6d68b),
      );
      _label(c, 'COFRE', p - const Offset(0, 60), const Color(0xffcfb789), 10);
    }
  }

  void _bonfire(Canvas c, Offset p) {
    _runeCircle(c, p, 38, const Color(0xffd7a56a));
    for (var i = 0; i < 7; i++) {
      final a = i * pi * 2 / 7;
      c.drawOval(
        Rect.fromCenter(
          center: p + Offset(cos(a) * 27, sin(a) * 14),
          width: 17,
          height: 12,
        ),
        Paint()..color = const Color(0xff6b7162),
      );
    }
    for (var i = 0; i < 3; i++) {
      final x = p.dx - 13 + i * 12, h = 35 + sin(game.time * 8 + i) * 10;
      c.drawPath(
        Path()
          ..moveTo(x - 10, p.dy)
          ..quadraticBezierTo(x - 16, p.dy - 18, x + 3, p.dy - h)
          ..quadraticBezierTo(x + 18, p.dy - 12, x + 9, p.dy)
          ..close(),
        Paint()
          ..color = [
            const Color(0xffce703e),
            const Color(0xfff3bc61),
            const Color(0xffe89748),
          ][i],
      );
    }
    _label(
      c,
      'HOGUERA DEL REFUGIO',
      p - const Offset(0, 72),
      const Color(0xffe0c99c),
      10,
    );
  }

  static void _shadow(Canvas c, Offset p, double width) => c.drawOval(
    Rect.fromCenter(
      center: p + const Offset(5, 4),
      width: width * 2,
      height: width * .65,
    ),
    Paint()..color = const Color(0x66070c0c),
  );

  static void drawHero(
    Canvas c,
    Offset p,
    HeroClass type, {
    double time = 0,
    bool moving = false,
    Offset facing = const Offset(1, 0),
    bool dead = false,
  }) {
    c.save();
    c.translate(p.dx, p.dy);
    if (dead) {
      c.rotate(pi / 2);
    }
    _shadow(c, Offset.zero, 24);
    final bob = moving ? sin(time * 14) * 3 : sin(time * 2) * 1.2;
    c.translate(0, bob);
    final color = Color(type.color),
        metal = type == HeroClass.guardian ? const Color(0xffa6b6b6) : color;
    final cape = Path()
      ..moveTo(-12, -42)
      ..quadraticBezierTo(-22, -20, -22 - sin(time * 4) * 3, -1)
      ..lineTo(2, -7)
      ..lineTo(19, -1)
      ..lineTo(12, -42)
      ..close();
    c.drawPath(
      cape,
      Paint()
        ..color = Color(
          type == HeroClass.guardian
              ? 0xff7d4142
              : type == HeroClass.arcanist
              ? 0xff65527c
              : 0xff3c7563,
        ),
    );
    for (final sign in [-1, 1]) {
      final step = moving ? sin(time * 14) * sign * 5 : 0.0;
      c.drawLine(
        Offset(sign * 7.0, -17),
        Offset(sign * 9.0, step),
        Paint()
          ..color = const Color(0xff343b3b)
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
      c.drawLine(
        Offset(sign * 8.0, step),
        Offset(sign * 8.0 + 4, step),
        Paint()
          ..color = const Color(0xff899590)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
    }
    c.drawPath(
      Path()
        ..moveTo(-14, -43)
        ..lineTo(14, -43)
        ..lineTo(10, -16)
        ..lineTo(-10, -16)
        ..close(),
      Paint()..color = metal,
    );
    c.drawLine(
      const Offset(0, -41),
      const Offset(0, -20),
      Paint()
        ..color = Colors.white.withValues(alpha: .25)
        ..strokeWidth = 2,
    );
    c.drawLine(
      const Offset(-10, -18),
      const Offset(10, -18),
      Paint()
        ..color = const Color(0xff564633)
        ..strokeWidth = 5,
    );
    c.drawCircle(
      const Offset(0, -17),
      3,
      Paint()..color = const Color(0xffe3c386),
    );
    c.drawCircle(
      const Offset(0, -54),
      11,
      Paint()..color = const Color(0xffd6b899),
    );
    if (type == HeroClass.guardian) {
      c.drawArc(
        const Rect.fromLTWH(-12, -67, 24, 24),
        pi,
        pi,
        true,
        Paint()..color = const Color(0xffa9b9b7),
      );
      c.drawRect(
        const Rect.fromLTWH(-11, -56, 22, 6),
        Paint()..color = const Color(0xff3c4848),
      );
      c.drawLine(
        const Offset(0, -67),
        const Offset(0, -49),
        Paint()
          ..color = const Color(0xffd8d3b1)
          ..strokeWidth = 3,
      );
      c.drawPath(
        Path()
          ..moveTo(-31, -42)
          ..lineTo(-14, -45)
          ..lineTo(-10, -26)
          ..lineTo(-23, -14)
          ..lineTo(-34, -26)
          ..close(),
        Paint()..color = const Color(0xff7b9290),
      );
      c.drawLine(
        const Offset(-23, -40),
        const Offset(-23, -21),
        Paint()
          ..color = color
          ..strokeWidth = 3,
      );
      c.drawLine(
        const Offset(20, -23),
        const Offset(37, -64),
        Paint()
          ..color = const Color(0xffd6e2da)
          ..strokeWidth = 5,
      );
      c.drawLine(
        const Offset(16, -34),
        const Offset(29, -29),
        Paint()
          ..color = color
          ..strokeWidth = 4,
      );
    } else if (type == HeroClass.arcanist) {
      c.drawPath(
        Path()
          ..moveTo(-16, -55)
          ..lineTo(0, -81)
          ..lineTo(15, -55)
          ..close(),
        Paint()..color = const Color(0xff76668c),
      );
      c.drawLine(
        const Offset(24, -3),
        const Offset(28, -64),
        Paint()
          ..color = const Color(0xffb28e66)
          ..strokeWidth = 4,
      );
      c.drawCircle(const Offset(28, -67), 7, Paint()..color = color);
      c.drawCircle(
        const Offset(28, -67),
        13,
        Paint()..color = color.withValues(alpha: .13),
      );
    } else {
      c.drawArc(
        const Rect.fromLTWH(-14, -69, 28, 28),
        pi,
        pi,
        true,
        Paint()..color = const Color(0xff497b68),
      );
      c.drawArc(
        const Rect.fromLTWH(8, -55, 33, 53),
        -pi / 2,
        pi,
        false,
        Paint()
          ..color = const Color(0xffd0b789)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      c.drawLine(
        const Offset(24, -55),
        const Offset(24, -2),
        Paint()
          ..color = const Color(0xffe0d9bb)
          ..strokeWidth = 1,
      );
    }
    c.drawCircle(
      Offset(facing.dx * 3 + 3, -55),
      1.3,
      Paint()..color = const Color(0xff202827),
    );
    c.restore();
  }

  void _monster(Canvas c, Monster m) {
    final p = m.position;
    if (!m.alive) {
      c.drawOval(
        Rect.fromCenter(center: p, width: 34, height: 17),
        Paint()..color = const Color(0xff706c62).withValues(alpha: .4),
      );
      return;
    }
    c.save();
    c.translate(p.dx, p.dy);
    if (m.boss) c.scale(1.7);
    _shadow(c, Offset.zero, m.kind == MonsterKind.brute ? 28 : 24);
    final color = m.flash > 0
        ? const Color(0xffffecd2)
        : Color(
            m.boss
                ? [0, 0xff81935f, 0xffa394bd, 0xffd68c63][game.zoneId]
                : m.kind == MonsterKind.wisp
                ? 0xffa6b0d6
                : m.kind == MonsterKind.brute
                ? 0xffad8c75
                : 0xff8f9e82,
          );
    final bob = sin(game.time * 4 + m.id) * 2;
    c.translate(0, bob);
    if (m.kind == MonsterKind.wisp) {
      c.drawPath(
        Path()
          ..moveTo(0, -55)
          ..quadraticBezierTo(28, -43, 17, -5)
          ..lineTo(7, -11)
          ..lineTo(0, 2)
          ..lineTo(-7, -11)
          ..lineTo(-18, -5)
          ..quadraticBezierTo(-27, -42, 0, -55)
          ..close(),
        Paint()..color = color.withValues(alpha: .65),
      );
      c.drawCircle(
        const Offset(0, -34),
        9,
        Paint()..color = const Color(0xffd5d6eb),
      );
    } else {
      for (final s in [-1.0, 1.0]) {
        c.drawLine(
          Offset(s * 9, -17),
          Offset(s * 14, 0),
          Paint()
            ..color = color
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round,
        );
        c.drawLine(
          Offset(s * 16, -38),
          Offset(s * 29, -16),
          Paint()
            ..color = color
            ..strokeWidth = m.boss ? 9 : 7
            ..strokeCap = StrokeCap.round,
        );
      }
      c.drawOval(const Rect.fromLTWH(-19, -49, 38, 37), Paint()..color = color);
      c.drawOval(const Rect.fromLTWH(-11, -62, 22, 24), Paint()..color = color);
      c.drawPath(
        Path()
          ..moveTo(-9, -56)
          ..lineTo(-18, -76)
          ..lineTo(-2, -62)
          ..moveTo(9, -56)
          ..lineTo(18, -76)
          ..lineTo(2, -62),
        Paint()
          ..color = const Color(0xffc9b794)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      c.drawLine(
        const Offset(-9, -27),
        const Offset(9, -27),
        Paint()
          ..color = const Color(0xff34372d)
          ..strokeWidth = 4,
      );
    }
    c.drawCircle(
      const Offset(-4, -51),
      2.5,
      Paint()..color = const Color(0xfff5c389),
    );
    c.drawCircle(
      const Offset(4, -51),
      2.5,
      Paint()..color = const Color(0xfff5c389),
    );
    c.restore();
    if (m.hp < m.maxHp || m.boss) {
      final width = m.boss ? 100.0 : 40.0, y = p.dy - (m.boss ? 148 : 84);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(p.dx - width / 2, y, width, 4),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xff162020),
      );
      c.drawRect(
        Rect.fromLTWH(p.dx - width / 2, y, width * m.hp / m.maxHp, 4),
        Paint()..color = const Color(0xffc98779),
      );
      if (m.boss) {
        _label(c, m.name, Offset(p.dx, y - 22), const Color(0xffefc497), 12);
      }
    }
  }

  void _effect(Canvas c, VisualEffect e) {
    final t = 1 - e.life / e.duration,
        color = Color(e.color).withValues(alpha: (1 - t).clamp(0, 1));
    if (e.kind == 'text') {
      _label(c, e.text, e.from - Offset(0, 90 + t * 35), color, 19);
    } else if (e.kind == 'bolt') {
      final p = Offset.lerp(
        e.from - const Offset(0, 32),
        e.to - const Offset(0, 32),
        min(1, t * 3),
      )!;
      c.drawLine(
        Offset.lerp(e.from - const Offset(0, 32), p, .65)!,
        p,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      c.drawCircle(p, 5, Paint()..color = color);
    } else if (e.kind == 'slash') {
      final a = atan2(e.to.dy - e.from.dy, e.to.dx - e.from.dx);
      c.drawArc(
        Rect.fromCircle(center: e.from - const Offset(0, 20), radius: 70),
        a - .9 + t,
        1.5,
        false,
        Paint()
          ..color = color
          ..strokeWidth = 8 * (1 - t)
          ..style = PaintingStyle.stroke,
      );
    } else {
      final r = e.kind == 'blast' ? e.to.dx : 105.0;
      c.drawCircle(
        e.from,
        r * (.3 + .7 * t),
        Paint()..color = color.withValues(alpha: (1 - t) * .09),
      );
      c.drawCircle(
        e.from,
        r * (.3 + .7 * t),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t),
      );
    }
  }

  static void _label(
    Canvas c,
    String text,
    Offset p,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: size < 12 ? 1.5 : .4,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(c, p - Offset(painter.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant WorldPainter oldDelegate) =>
      oldDelegate.game != game || cinematic != oldDelegate.cinematic;
}

class MiniMapPainter extends CustomPainter {
  final Game game;
  final int zoneId;
  MiniMapPainter(this.game, this.zoneId) : super(repaint: game);
  @override
  void paint(Canvas c, Size size) {
    final zone = Zone.all[zoneId], state = game.zones[zoneId]!;
    c.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = const Color(0xff0c171a),
    );
    c.save();
    c.clipRect(Offset.zero & size);
    c.scale(size.width / Zone.width, size.height / Zone.height);
    for (final cell in state.explored) {
      c.drawRect(
        Rect.fromLTWH(cell % 28 * 80, cell ~/ 28 * 80, 81, 81),
        Paint()..color = Color(zone.ground).withValues(red: .20, green: .27),
      );
    }
    bool seen(Offset p) =>
        state.explored.contains((p.dy ~/ 80) * 28 + p.dx ~/ 80);
    for (final rect in zone.obstacles) {
      if (seen(rect.center)) {
        c.drawRect(rect, Paint()..color = const Color(0xff626860));
      }
    }
    for (final gate in zone.gates) {
      if (seen(gate.position)) {
        c.drawCircle(
          gate.position,
          40,
          Paint()..color = const Color(0xffd4b784),
        );
      }
    }
    if (game.portals.contains(zoneId)) {
      c.drawCircle(zone.portal, 45, Paint()..color = const Color(0xff7edac6));
    }
    for (final chest in state.chests) {
      if (!chest.opened && seen(chest.position)) {
        c.drawCircle(
          chest.position,
          26,
          Paint()..color = const Color(0xffd4b784),
        );
      }
    }
    for (final m in state.monsters) {
      if (m.alive && seen(m.position)) {
        c.drawCircle(
          m.position,
          m.boss ? 40 : 20,
          Paint()..color = const Color(0xffd68375),
        );
      }
    }
    if (zoneId == game.zoneId) {
      c.drawCircle(game.position, 38, Paint()..color = const Color(0xfff5efe1));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant MiniMapPainter oldDelegate) =>
      oldDelegate.game != game || oldDelegate.zoneId != zoneId;
}
