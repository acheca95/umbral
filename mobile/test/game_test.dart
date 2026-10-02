import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbral_rpg/game.dart';
import 'package:umbral_rpg/save_store.dart';
import 'package:umbral_rpg/world.dart';

void advance(Game g, double seconds) {
  for (var i = 0; i < seconds * 30; i++) {
    g.tick(1 / 30);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Classes have distinct reach, resources and abilities', () {
    final guardian = Game(HeroClass.guardian),
        mage = Game(HeroClass.arcanist),
        ranger = Game(HeroClass.ranger);
    expect(guardian.maxHp, greaterThan(mage.maxHp));
    expect(guardian.range, lessThan(mage.range));
    expect(ranger.speed, greaterThan(guardian.speed));
    expect(mage.maxMana, greaterThan(guardian.maxMana));
  });
  test('Routes navigate around a house and reveal unexplored terrain', () {
    final g = Game(HeroClass.guardian)..position = const Offset(550, 520);
    final previous = g.state.explored.length;
    g.walkTo(const Offset(880, 520));
    expect(g.route, isNotEmpty);
    for (var i = 0; i < 500; i++) {
      g.tick(1 / 30);
      expect(g.walkable(g.position), isTrue);
    }
    expect((g.position - const Offset(880, 520)).distance, lessThan(15));
    expect(g.state.explored.length, greaterThan(previous));
    g.steer(const Offset(-1, 0));
    advance(g, 30);
    expect(g.position.dx, greaterThanOrEqualTo(60));
  });
  test('Portals must be discovered and travel requires proximity', () {
    final g = Game(HeroClass.ranger);
    expect(g.enter(1, fast: true), isFalse);
    g.position = g.zone.gates.first.position;
    expect(g.enter(1), isTrue);
    expect(g.portals.contains(1), isFalse);
    g.position = g.zone.portal;
    g.tick(.03);
    expect(g.portals.contains(1), isTrue);
    expect(g.enter(0, fast: true), isTrue);
    g.position = const Offset(1500, 800);
    expect(g.enter(1, fast: true), isFalse);
  });
  test('Seals gate progression and zones cannot be entered remotely', () {
    final g = Game(HeroClass.guardian)
      ..zoneId = 1
      ..position = const Offset(1980, 800);
    expect(g.enter(2), isFalse);
    g.seals.add(1);
    expect(g.enter(2), isTrue);
    expect(g.enter(3), isFalse);
    g.position = const Offset(1970, 800);
    expect(g.enter(3), isFalse);
    g.seals.add(2);
    expect(g.enter(3), isTrue);
  });
  test('Basic attacks respect range and cooldown, death awards loot once', () {
    final g = Game(HeroClass.guardian)..zoneId = 1;
    final m = g.state.monsters.first;
    g.position = m.position - const Offset(200, 0);
    expect(g.basicAttack(), isFalse);
    g.position = m.position - const Offset(60, 0);
    expect(g.basicAttack(), isTrue);
    expect(g.basicAttack(), isFalse);
    while (m.alive) {
      g.attackCooldown = 0;
      g.basicAttack();
    }
    final kills = g.kills, coins = g.gold;
    g.hit(m, 500);
    expect(g.kills, kills);
    expect(g.gold, coins);
  });
  test('Primary consumes mana, hits groups and respects cooldown', () {
    final g = Game(HeroClass.arcanist)..zoneId = 1;
    final a = g.state.monsters[0], b = g.state.monsters[1];
    g.position = a.position;
    b.position = a.position + const Offset(70, 0);
    expect(g.castPrimary(), isTrue);
    expect(g.mana, 72);
    expect(a.hp, lessThan(a.maxHp));
    expect(b.hp, lessThan(b.maxHp));
    expect(g.castPrimary(), isFalse);
    g.skillCooldown = 0;
    g.mana = 0;
    expect(g.castPrimary(), isFalse);
  });
  test('Ward reduces damage and potion cannot be spammed', () {
    final g = Game(HeroClass.guardian)..zoneId = 1;
    g.damagePlayer(40);
    final normal = g.maxHp - g.hp;
    g.castWard();
    g.hp = g.maxHp;
    g.damagePlayer(40);
    expect(g.maxHp - g.hp, lessThan(normal * .5));
    g.hp = 20;
    expect(g.drinkPotion(), isTrue);
    expect(g.potions, 4);
    expect(g.drinkPotion(), isFalse);
  });
  test('Boss telegraphs can be dodged before impact', () {
    final g = Game(HeroClass.ranger)..zoneId = 3;
    for (final m in g.state.monsters.where((m) => !m.boss)) {
      m.hp = 0;
    }
    final boss = g.state.monsters.last;
    g.position = boss.position - const Offset(180, 0);
    g.tick(.03);
    expect(g.hazards, hasLength(1));
    final hp = g.hp;
    g.steer(const Offset(0, -1));
    advance(g, 1.3);
    expect(g.hp, hp);
    expect(g.hazards, isEmpty);
  });
  test('Equipment swaps atomically and merchant enforces zone and price', () {
    final g = Game(HeroClass.guardian);
    final original = g.equipment[Slot.weapon]!, before = g.attack;
    const loot = Item(9, 'Hoja de prueba', Slot.weapon, 2, 15, 0, 0);
    g.inventory.add(loot);
    expect(g.equip(loot), isTrue);
    expect(g.inventory, contains(original));
    expect(g.attack, before + 11);
    expect(g.equip(loot), isFalse);
    g.zoneId = 1;
    expect(g.sell(original), isFalse);
    expect(g.buyPotion(), isFalse);
    g.zoneId = 0;
    expect(g.sell(original), isTrue);
    g.gold = 20;
    expect(g.buyPotion(), isTrue);
    expect(g.gold, 0);
    expect(g.buyPotion(), isFalse);
  });
  test(
    'Chest is reachable, pays once and full inventory retains ground loot',
    () {
      for (var zone = 1; zone < 4; zone++) {
        final g = Game(HeroClass.guardian, seed: 42)..zoneId = zone;
        final chest = g.state.chests.first;
        expect(g.walkable(chest.position), isTrue);
        g.position = chest.position;
        g.interact();
        expect(chest.opened, isTrue);
        expect(g.gold, 60);
        g.inventory.addAll(List.generate(24, (_) => g.rollItem()));
        g.interact();
        expect(g.state.drops, hasLength(1));
        g.inventory.removeLast();
        g.interact();
        expect(g.state.drops, isEmpty);
        g.interact();
        expect(g.gold, 60);
      }
    },
  );
  test('Pause freezes combat and movement; death preserves progression', () {
    final g = Game(HeroClass.guardian)..zoneId = 1;
    g.seals.add(1);
    g.hp = 50;
    g.setPaused(true);
    final p = g.position;
    g.steer(const Offset(1, 0));
    advance(g, 10);
    expect(g.position, p);
    expect(g.hp, 50);
    expect(g.castPrimary(), isFalse);
    g.setPaused(false);
    g.damagePlayer(9999);
    expect(g.dead, isTrue);
    g.respawn();
    expect(g.zoneId, 0);
    expect(g.hp, g.maxHp);
    expect(g.seals, contains(1));
    expect(g.gold, 20);
  });
  test(
    'Save round trip preserves every zone, loot, equipment and exploration',
    () {
      final g = Game(HeroClass.ranger)
        ..zoneId = 2
        ..position = const Offset(820, 810);
      g.portals.addAll([1, 2]);
      g.seals.add(1);
      g.hit(g.state.monsters.first, 9999);
      g.state.chests.first.opened = true;
      g.inventory.add(g.rollItem());
      g.equip(g.inventory.first);
      g.reveal();
      final restored = Game.fromJson(
        jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), g.toJson());
      expect(restored.state.monsters.first.alive, isFalse);
    },
  );
  test(
    'Corrupted primary save recovers backup and subsequent writes succeed',
    () async {
      final g = Game(HeroClass.arcanist);
      SharedPreferences.setMockInitialValues({
        'umbral.save.v1': '{"version":1}',
        'umbral.backup.v1': jsonEncode(g.toJson()),
      });
      final store = SaveStore(await SharedPreferences.getInstance());
      final recovered = store.load();
      expect(recovered, isNotNull);
      expect(store.warning, contains('recuperado'));
      recovered!.gold = 77;
      await store.save(recovered);
      expect(store.load()!.gold, 77);
    },
  );
  test('Queued saves keep newest state with a valid previous backup', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance(),
        store = SaveStore(await SharedPreferences.getInstance());
    final g = Game(HeroClass.guardian);
    final first = store.save(g);
    g.gold = 80;
    final second = store.save(g);
    await Future.wait([first, second]);
    expect(store.load()!.gold, 80);
    expect(
      (jsonDecode(prefs.getString('umbral.backup.v1')!) as Map)['gold'],
      35,
    );
  });

  for (final type in HeroClass.values) {
    test('Playable campaign combat and three bosses: ${type.label}', () {
      final g = Game(type, seed: 14);
      for (var zone = 1; zone <= 3; zone++) {
        g.position = g.zone.gates.last.position;
        expect(g.enter(zone), isTrue);
        // A deterministic player: approach, attack, use skills/potions and dodge.
        for (
          var frame = 0;
          frame < 18000 && g.state.monsters.any((m) => m.alive);
          frame++
        ) {
          final enemy = g.nearest(5000)!;
          final delta = enemy.position - g.position;
          if (g.hp < g.maxHp * .6) g.drinkPotion();
          if (g.hp < g.maxHp * .7) g.castWard();
          if (delta.distance < (type == HeroClass.guardian ? 155 : 250)) {
            g.castPrimary();
          }
          final danger = g.hazards.where(
            (h) => (h.position - g.position).distance < h.radius + 25,
          );
          if (danger.isNotEmpty) {
            final away = g.position - danger.first.position;
            g.steer(
              away.distance < 1 ? const Offset(0, -1) : away / away.distance,
            );
          } else if (delta.distance > g.range * .8) {
            g.steer(delta / delta.distance);
          } else {
            g.steer(Offset.zero);
          }
          g.attacking = true;
          g.tick(1 / 30);
          expect(
            g.dead,
            isFalse,
            reason: '${type.label}, zone $zone, frame $frame',
          );
          for (final drop in g.state.drops.toList()) {
            if ((drop.position - g.position).distance < 85) g.interact();
          }
          for (final item in g.inventory.toList()) {
            final old = g.equipment[item.slot];
            if (old == null ||
                item.power + item.armor + item.vitality >
                    old.power + old.armor + old.vitality) {
              g.equip(item);
            }
          }
        }
        expect(g.seals, contains(zone));
        expect(g.state.monsters.where((m) => m.alive), isEmpty);
      }
      expect(g.won, isTrue);
      expect(g.kills, 42);
      expect(g.level, greaterThan(4));
    });
  }
}
