import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbral_rpg/coop.dart';
import 'package:umbral_rpg/game.dart';
import 'package:umbral_rpg/world.dart';

void main() {
  CoopSession session(Game host, Game guest) {
    final s = CoopSession(db: FakeFirebaseFirestore(), uid: 'host', local: host)
      ..isHost = true;
    s.attach(guest);
    return s;
  }

  test('Host attaches guest to one shared world without replacing personal equipment', () {
    final h = Game(HeroClass.guardian)..zoneId = 1,
        g = Game(HeroClass.arcanist)..level = 3;
    final s = session(h, g);
    expect(identical(h.state, g.state), isTrue);
    expect(g.heroClass, HeroClass.arcanist);
    expect(g.level, 3);
    expect(h.companion, g);
    expect(g.partyLeader, isFalse);
    s.dispose();
    h.dispose();
  });
  test('Guest damage kills a shared monster and awards both players once', () {
    final h = Game(HeroClass.guardian)..zoneId = 1,
        g = Game(HeroClass.arcanist);
    final s = session(h, g), mob = h.state.monsters.first;
    g.hit(mob, 999);
    expect(h.kills, 1);
    expect(g.kills, 1);
    expect(h.xp, g.xp);
    expect(h.gold, g.gold);
    h.hit(mob, 999);
    expect(g.kills, 1);
    s.dispose();
    h.dispose();
  });
  test(
    'Shared ground loot can be picked up only once and item IDs remain unique',
    () {
      final h = Game(HeroClass.guardian)..zoneId = 1,
          g = Game(HeroClass.arcanist);
      final s = session(h, g);
      final one = h.rollItem(), two = g.rollItem(), three = h.rollItem();
      expect({one.id, two.id, three.id}, hasLength(3));
      h.state.drops.add(Drop(h.position, one));
      g.position = h.position;
      g.interact();
      h.interact();
      expect(g.inventory, contains(one));
      expect(h.inventory, isNot(contains(one)));
      s.dispose();
      h.dispose();
    },
  );
  test(
    'Leader travel moves the entire party and guest cannot move the party',
    () {
      final h = Game(HeroClass.guardian), g = Game(HeroClass.arcanist);
      final s = session(h, g);
      h.position = h.zone.gates.first.position;
      expect(h.enter(1), isTrue);
      expect(g.zoneId, 1);
      expect((h.position - g.position).distance, 55);
      g.position = g.zone.gates.first.position;
      expect(g.enter(0), isFalse);
      expect(h.zoneId, 1);
      s.dispose();
      h.dispose();
    },
  );
  test(
    'Only world simulator moves monsters; enemy attacks closest party member',
    () {
      final h = Game(HeroClass.guardian)..zoneId = 1,
          g = Game(HeroClass.arcanist);
      final s = session(h, g), mob = h.state.monsters.first;
      h.position = const Offset(100, 100);
      g.position = mob.position + const Offset(20, 0);
      final before = g.hp, old = mob.position;
      g.tick(.03, simulateWorld: false);
      expect(mob.position, old);
      expect(g.hp, before);
      h.tick(.03);
      expect(g.hp, lessThan(before));
      expect(h.hp, h.maxHp);
      s.dispose();
      h.dispose();
    },
  );
  test(
    'Input action replay is deduplicated and inventory commands use item IDs',
    () {
      final h = Game(HeroClass.guardian)..zoneId = 1,
          g = Game(HeroClass.arcanist);
      final s = session(h, g);
      g.position = h.state.monsters.first.position;
      final input = {
        'dx': 0,
        'dy': 0,
        'attack': false,
        'paused': false,
        'actions': [
          {'id': 1, 'action': 'primary'},
        ],
      };
      s.applyInput(input);
      final mana = g.mana;
      g.skillCooldown = 0;
      s.applyInput(input);
      expect(g.mana, mana);
      final item = g.rollItem();
      g.inventory.add(item);
      s.applyInput({
        'dx': 0,
        'dy': 0,
        'attack': false,
        'paused': true,
        'actions': [
          {'id': 2, 'action': 'equip', 'idItem': item.id},
        ],
      });
      expect(g.equipment[item.slot], item);
      s.dispose();
      h.dispose();
    },
  );
  test('Guest input is transmitted instead of performing local combat', () {
    final g = Game(HeroClass.ranger)..zoneId = 1;
    final commands = <String>[];
    g.remoteInput = (kind, data) => commands.add(kind);
    final mob = g.state.monsters.first;
    g.position = mob.position;
    g.castPrimary();
    g.basicAttack();
    g.interact();
    expect(mob.hp, mob.maxHp);
    expect(commands, ['primary', 'interact']);
    g.dispose();
  });
  test(
    'Network snapshots retain cooldowns, hazards and personal character',
    () {
      final h = Game(HeroClass.guardian)..zoneId = 1;
      h.reveal();
      h.skillCooldown = 4;
      h.wardTime = 3;
      h.hazards.add(Hazard(h.position, 80, 25, .8));
      final guestView = Game(HeroClass.guardian);
      guestView.applyNetwork(
        jsonDecode(jsonEncode(h.networkSnapshot())) as Map<String, dynamic>,
      );
      expect(guestView.skillCooldown, 4);
      expect(guestView.hazards.first.remaining, .8);
      expect(guestView.toJson(), h.toJson());
      h.dispose();
      guestView.dispose();
    },
  );
  test('A downed companion returns beside the living hero', () {
    final h = Game(HeroClass.guardian)..zoneId = 2,
        g = Game(HeroClass.arcanist);
    final s = session(h, g);
    g.damagePlayer(9999);
    expect(g.dead, isTrue);
    g.respawn();
    expect(g.zoneId, 2);
    expect(g.dead, isFalse);
    expect((h.position - g.position).distance, 40);
    s.dispose();
    h.dispose();
  });
}
