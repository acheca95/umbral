import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'world.dart';

class Game extends ChangeNotifier {
  Game? companion;
  bool partyLeader = true;
  bool networkBlocked = false;
  void Function(String action, Map<String, dynamic> data)? remoteInput;
  bool _remote(String action, [Map<String, dynamic> data = const {}]) {
    if (remoteInput == null) return false;
    remoteInput!(action, data);
    return true;
  }

  final HeroClass heroClass;
  final Map<int, ZoneState> zones = {
    for (var i = 0; i < 4; i++) i: ZoneState.generate(i),
  };
  final Set<int> portals = {0}, seals = {};
  final List<Item> inventory = [];
  final Map<Slot, Item> equipment = {};
  final List<VisualEffect> effects = [];
  List<Hazard> hazards = [];
  final Random random;
  int zoneId = 0,
      level = 1,
      xp = 0,
      gold = 35,
      potions = 5,
      kills = 0,
      nextItem = 10;
  double hp = 1,
      mana = 100,
      time = 0,
      attackCooldown = 0,
      skillCooldown = 0,
      wardCooldown = 0,
      wardTime = 0,
      potionCooldown = 0;
  Offset position = const Offset(940, 850),
      movement = Offset.zero,
      facing = const Offset(1, 0);
  final List<Offset> route = [];
  bool paused = false, dead = false, won = false, attacking = false;
  int? targetId;
  int revision = 0;
  String message =
      'Bienvenido al Refugio. El camino del este conduce al bosque.';
  double messageTime = 7;
  Game(this.heroClass, {int? seed}) : random = Random(seed) {
    equipment[Slot.weapon] = Item(
      1,
      [
        'Espada del alba',
        'Báculo de aprendiz',
        'Arco de fresno',
      ][heroClass.index],
      Slot.weapon,
      0,
      4,
      0,
      0,
    );
    equipment[Slot.armor] = const Item(
      2,
      'Vestiduras de viajero',
      Slot.armor,
      0,
      0,
      2,
      12,
    );
    hp = maxHp;
    reveal();
  }
  Zone get zone => Zone.all[zoneId];
  ZoneState get state => zones[zoneId]!;
  int get attack =>
      [18, 23, 20][heroClass.index] +
      (level - 1) * 3 +
      equipment.values.fold(0, (v, e) => v + e.power);
  int get armor =>
      [5, 1, 2][heroClass.index] +
      level -
      1 +
      equipment.values.fold(0, (v, e) => v + e.armor);
  double get maxHp =>
      [160.0, 108.0, 125.0][heroClass.index] +
      (level - 1) * 18 +
      equipment.values.fold(0, (v, e) => v + e.vitality);
  double get maxMana => heroClass == HeroClass.arcanist ? 125 : 100;
  int get nextLevelXp => 65 + (level - 1) * 35;
  double get range => heroClass == HeroClass.guardian ? 95 : 320;
  double get speed => heroClass == HeroClass.ranger ? 215 : 190;
  bool get atPortal => (position - zone.portal).distance < 130;
  bool get canTravel => atPortal && portals.contains(zoneId) && !dead;
  String get objective {
    if (won) return 'El alba regresa. Explora y reúne el equipo restante.';
    if (!seals.contains(1)) {
      return 'Derrota a Raíz corrompida en el Bosque de espinas.';
    }
    if (!seals.contains(2)) {
      return 'Encuentra al Custodio del olvido en la Cripta.';
    }
    return 'Cruza a Corazón de ceniza y derrota al Rey.';
  }

  String get interaction {
    if (dead) return 'Regresar al refugio';
    for (final drop in state.drops) {
      if ((drop.position - position).distance < 85) {
        return 'Recoger ${drop.item.name}';
      }
    }
    for (final chest in state.chests) {
      if (!chest.opened && (chest.position - position).distance < 110) {
        return 'Abrir cofre antiguo';
      }
    }
    for (final gate in zone.gates) {
      if ((gate.position - position).distance < 115) {
        return 'Entrar: ${gate.label}';
      }
    }
    if (zoneId == 0 && (position - const Offset(1060, 800)).distance < 150) {
      return 'Descansar en la hoguera';
    }
    if (atPortal) {
      return portals.contains(zoneId)
          ? 'Portal activo • abre el mapa'
          : 'Activar portal';
    }
    return '';
  }

  void tell(String text) {
    message = text;
    messageTime = 4;
    notifyListeners();
  }

  void changed() {
    revision++;
    notifyListeners();
  }

  void stop() {
    movement = Offset.zero;
    route.clear();
    targetId = null;
    attacking = false;
  }

  void setPaused(bool value) {
    paused = value;
    stop();
    notifyListeners();
  }

  void steer(Offset input) {
    movement = input.distance > 1 ? input / input.distance : input;
    if (movement.distance > .05) {
      route.clear();
      targetId = null;
    }
  }

  bool walkable(Offset p, [double radius = 19]) {
    if (p.dx < 60 ||
        p.dy < 60 ||
        p.dx > Zone.width - 60 ||
        p.dy > Zone.height - 60) {
      return false;
    }
    return !zone.obstacles.any((r) => r.inflate(radius).contains(p));
  }

  Offset moveBody(Offset p, Offset delta, [double radius = 19]) {
    if (walkable(p + delta, radius)) return p + delta;
    final x = Offset(p.dx + delta.dx, p.dy);
    if (walkable(x, radius)) return x;
    final y = Offset(p.dx, p.dy + delta.dy);
    return walkable(y, radius) ? y : p;
  }

  // Bounded grid search gives tap-to-move real navigation around scenery.
  void walkTo(Offset destination) {
    if (_remote('walk', {'x': destination.dx, 'y': destination.dy})) return;
    if (dead || paused || networkBlocked || !walkable(destination)) return;
    targetId = null;
    const cell = 40.0, cols = 55, rows = 40;
    int index(Offset p) => (p.dy ~/ cell) * cols + p.dx ~/ cell;
    Offset center(int i) =>
        Offset((i % cols + .5) * cell, (i ~/ cols + .5) * cell);
    final start = index(position), end = index(destination);
    final queue = <int>[start];
    final parent = <int, int>{start: -1};
    var head = 0;
    while (head < queue.length && !parent.containsKey(end)) {
      final current = queue[head++], x = current % cols, y = current ~/ cols;
      for (final d in const [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
      ]) {
        final nx = x + d.dx.toInt(), ny = y + d.dy.toInt();
        final next = ny * cols + nx;
        if (nx < 0 ||
            ny < 0 ||
            nx >= cols ||
            ny >= rows ||
            parent.containsKey(next) ||
            !walkable(center(next), 25)) {
          continue;
        }
        parent[next] = current;
        queue.add(next);
      }
    }
    route.clear();
    if (!parent.containsKey(end)) {
      tell('El paso está bloqueado. Busca otro camino.');
      return;
    }
    final reverse = <Offset>[destination];
    var cursor = end;
    while (cursor != start) {
      reverse.add(center(cursor));
      cursor = parent[cursor]!;
    }
    route.addAll(reverse.reversed);
  }

  void tapWorld(Offset p) {
    if (_remote('tap', {'x': p.dx, 'y': p.dy})) return;
    if (paused || dead) return;
    Monster? selected;
    for (final m in state.monsters.where((m) => m.alive)) {
      if ((m.position - p).distance < 48 &&
          (m.position - position).distance < 600) {
        selected = m;
        break;
      }
    }
    if (selected != null) {
      walkTo(selected.position);
      targetId = selected.id;
    } else {
      walkTo(p);
    }
  }

  void reveal() {
    final cx = position.dx ~/ 80, cy = position.dy ~/ 80;
    for (var y = max(0, cy - 4); y <= min(19, cy + 4); y++) {
      for (var x = max(0, cx - 4); x <= min(27, cx + 4); x++) {
        if (pow(x - cx, 2) + pow(y - cy, 2) < 21) {
          state.explored.add(y * 28 + x);
        }
      }
    }
  }

  void tick(double dt, {bool simulateWorld = true}) {
    if (paused || dead) return;
    dt = dt.clamp(0, .05);
    time += dt;
    messageTime = max(0, messageTime - dt);
    attackCooldown = max(0, attackCooldown - dt);
    skillCooldown = max(0, skillCooldown - dt);
    wardCooldown = max(0, wardCooldown - dt);
    wardTime = max(0, wardTime - dt);
    potionCooldown = max(0, potionCooldown - dt);
    mana = min(maxMana, mana + dt * (heroClass == HeroClass.arcanist ? 7 : 5));
    if (zoneId == 0) hp = min(maxHp, hp + dt * 18);
    for (final e in effects) {
      e.life -= dt;
    }
    effects.removeWhere((e) => e.life <= 0);

    Monster? target;
    for (final m in state.monsters) {
      if (m.id == targetId && m.alive) target = m;
    }
    if (target != null && (target.position - position).distance <= range) {
      route.clear();
      basicAttack();
    }
    Offset direction = movement;
    if (direction.distance < .05 && route.isNotEmpty) {
      final delta = route.first - position;
      if (delta.distance < 12) {
        route.removeAt(0);
      } else {
        direction = delta / delta.distance;
      }
    }
    if (direction.distance > .05) {
      facing = direction / direction.distance;
      position = moveBody(
        position,
        direction *
            speed *
            (heroClass == HeroClass.ranger && wardTime > 0 ? 1.5 : 1) *
            dt,
      );
      reveal();
    }
    if (attacking) basicAttack();
    if (atPortal && !portals.contains(zoneId)) {
      portals.add(zoneId);
      changed();
      tell('Portal descubierto: ${zone.name}. Viaje rápido disponible.');
      effects.add(
        VisualEffect('ring', position, position, 0xff84dece, duration: 1),
      );
    }
    if (!simulateWorld) {
      notifyListeners();
      return;
    }
    for (final m in state.monsters.where((m) => m.alive)) {
      m.cooldown = max(0, m.cooldown - dt);
      m.slow = max(0, m.slow - dt);
      m.flash = max(0, m.flash - dt);
      final ally = companion;
      final victim =
          ally != null &&
              !ally.dead &&
              (dead ||
                  (ally.position - m.position).distance <
                      (position - m.position).distance)
          ? ally
          : this;
      final delta = victim.position - m.position, distance = delta.distance;
      if (distance > (m.boss ? 490 : 360)) continue;
      final reach = m.kind == MonsterKind.wisp ? 250 : m.radius + 30;
      if (distance > reach && distance > 0) {
        var direction = delta / distance;
        for (final other in state.monsters) {
          if (other == m || !other.alive) continue;
          final separation = m.position - other.position;
          if (separation.distance > 0 &&
              separation.distance < m.radius + other.radius + 5) {
            direction += separation / separation.distance * .7;
          }
        }
        final step =
            direction *
            (m.boss
                ? 62
                : m.kind == MonsterKind.crawler
                ? 106
                : 76) *
            (m.slow > 0 ? .4 : 1) *
            dt;
        m.position = moveBody(m.position, step, m.radius);
      }
      if (m.cooldown <= 0) {
        if (m.boss && distance < 440) {
          hazards.add(
            Hazard(
              victim.position,
              zoneId == 3 ? 100 : 78,
              23 + zoneId * 8,
              1.15,
            ),
          );
          m.cooldown = zoneId == 3 ? 2.0 : 2.8;
        } else if (distance <= reach + 8) {
          victim.damagePlayer(
            (m.kind == MonsterKind.brute ? 15 : 9) + zoneId * 3.0,
          );
          effects.add(
            VisualEffect('bolt', m.position, victim.position, 0xffe49b85),
          );
          m.cooldown = m.kind == MonsterKind.wisp ? 1.9 : 1.25;
        }
      }
      if (dead) break;
    }
    for (final h in hazards.toList()) {
      h.remaining -= dt;
      if (h.remaining <= 0) {
        if ((h.position - position).distance < h.radius + 15) {
          damagePlayer(h.damage);
        }
        final ally = companion;
        if (ally != null &&
            (h.position - ally.position).distance < h.radius + 15) {
          ally.damagePlayer(h.damage);
        }
        effects.add(
          VisualEffect('blast', h.position, Offset(h.radius, 0), 0xffed826c),
        );
        hazards.remove(h);
      }
    }
    notifyListeners();
  }

  Monster? nearest(double reach) {
    Monster? result;
    var best = reach;
    for (final m in state.monsters.where((m) => m.alive)) {
      final d = (m.position - position).distance;
      if (d < best) {
        best = d;
        result = m;
      }
    }
    return result;
  }

  bool basicAttack() {
    if (remoteInput != null) return false;
    if (dead || paused || networkBlocked || attackCooldown > 0) return false;
    final m = nearest(range);
    if (m == null) return false;
    facing = (m.position - position) / max(1, (m.position - position).distance);
    attackCooldown = heroClass == HeroClass.ranger ? .48 : .62;
    effects.add(
      VisualEffect(
        heroClass == HeroClass.guardian ? 'slash' : 'bolt',
        position,
        m.position,
        heroClass.color,
      ),
    );
    hit(m, attack.toDouble());
    return true;
  }

  bool castPrimary() {
    if (_remote('primary')) return true;
    if (paused || dead || networkBlocked || skillCooldown > 0) return false;
    if (mana < 28) {
      tell('Necesitas 28 de energía. Se regenera con el tiempo.');
      return false;
    }
    mana -= 28;
    skillCooldown = 5;
    final radius = heroClass == HeroClass.guardian ? 165.0 : 265.0;
    final center = heroClass == HeroClass.ranger
        ? nearest(420)?.position ?? position
        : position;
    effects.add(
      VisualEffect(
        'blast',
        center,
        Offset(radius, 0),
        heroClass.color,
        duration: .65,
      ),
    );
    for (final m in state.monsters.where((m) => m.alive).toList()) {
      if ((m.position - center).distance < radius + m.radius) {
        m.slow = 2;
        hit(m, attack * 2.25);
      }
    }
    changed();
    return true;
  }

  bool castWard() {
    if (_remote('ward')) return true;
    if (paused || dead || networkBlocked || wardCooldown > 0) return false;
    if (mana < 20) {
      tell('Necesitas 20 de energía.');
      return false;
    }
    mana -= 20;
    wardCooldown = 13;
    wardTime = 4;
    hp = min(maxHp, hp + maxHp * .22);
    if (heroClass == HeroClass.arcanist) mana = min(maxMana, mana + 40);
    effects.add(
      VisualEffect('ring', position, position, heroClass.color, duration: .8),
    );
    tell('${heroClass.secondary}: curación y protección durante 4 s.');
    changed();
    return true;
  }

  void hit(Monster m, double damage) {
    if (!m.alive) return;
    m.hp = max(0, m.hp - damage);
    m.flash = .16;
    effects.add(
      VisualEffect(
        'text',
        m.position,
        m.position,
        0xfff8e7c6,
        text: '${damage.round()}',
        duration: .8,
      ),
    );
    if (m.alive) return;
    kills++;
    final ally = companion;
    if (ally != null) {
      ally.kills++;
      ally.gold += m.boss ? 65 : 6 + zoneId * 2;
      ally.gainXp(m.boss ? 100 : 19 + zoneId * 5);
      if (ally.kills % 5 == 0) ally.potions++;
    }
    gold += m.boss ? 65 : 6 + zoneId * 2;
    gainXp(m.boss ? 100 : 19 + zoneId * 5);
    if (m.boss || random.nextDouble() < .58) {
      state.drops.add(Drop(m.position, rollItem(boss: m.boss)));
    }
    if (kills % 5 == 0) {
      potions++;
      tell('Has encontrado una poción.');
    }
    if (m.boss) {
      seals.add(zoneId);
      if (ally != null) {
        ally.seals.add(zoneId);
        ally.potions += 2;
        ally.hp = ally.maxHp;
        ally.mana = ally.maxMana;
      }
      hp = maxHp;
      mana = maxMana;
      potions += 2;
      tell('Sello recuperado. Botín especial y 2 pociones junto al guardián.');
      if (zoneId == 3) {
        won = true;
        if (ally != null) ally.won = true;
        tell('El Rey ha caído. La ceniza da paso al alba.');
      }
    }
    changed();
  }

  void gainXp(int amount) {
    xp += amount;
    while (xp >= nextLevelXp && level < 12) {
      xp -= nextLevelXp;
      level++;
      hp = maxHp;
      mana = maxMana;
      tell('Nivel $level • Tu vida y energía se han restaurado.');
      effects.add(
        VisualEffect('ring', position, position, 0xffedc16f, duration: 1),
      );
    }
  }

  void damagePlayer(double amount) {
    if (dead) return;
    final damage = max(1.0, amount - armor * .65) * (wardTime > 0 ? .35 : 1);
    hp = max(0, hp - damage);
    effects.add(
      VisualEffect(
        'text',
        position,
        position,
        0xffffa091,
        text: '-${damage.round()}',
        duration: .65,
      ),
    );
    if (hp <= 0) {
      dead = true;
      stop();
      changed();
    }
  }

  bool drinkPotion() {
    if (_remote('potion')) return true;
    if (dead || paused || networkBlocked || potionCooldown > 0) return false;
    if (potions == 0) {
      tell('Sin pociones. Compra más en el refugio.');
      return false;
    }
    if (hp >= maxHp) {
      tell('Tu vida ya está completa.');
      return false;
    }
    potions--;
    potionCooldown = 4;
    hp = min(maxHp, hp + maxHp * .55);
    effects.add(VisualEffect('ring', position, position, 0xff83d6a5));
    changed();
    return true;
  }

  Item rollItem({bool boss = false}) {
    nextItem = max(nextItem, companion?.nextItem ?? 0);
    final slot = Slot.values[random.nextInt(3)];
    final tier = boss
        ? (zoneId == 3 ? 3 : 2)
        : (random.nextDouble() < .22
              ? 2
              : random.nextBool()
              ? 1
              : 0);
    final quality = zoneId + tier + 1;
    final base = slot == Slot.weapon
        ? ['Hoja', 'Vara', 'Arco'][heroClass.index]
        : slot == Slot.armor
        ? 'Manto'
        : 'Talismán';
    return Item(
      nextItem++,
      '$base ${['del viajero', 'de espinas', 'del olvido', 'del alba'][tier]}',
      slot,
      tier,
      slot == Slot.weapon
          ? 4 + quality * 3
          : slot == Slot.charm
          ? quality * 2
          : 0,
      slot == Slot.armor ? 2 + quality * 2 : 0,
      slot == Slot.weapon ? 0 : quality * 7,
    );
  }

  bool equip(Item item) {
    if (_remote('equip', {'idItem': item.id})) return true;
    if (!inventory.contains(item) || dead) return false;
    final previous = equipment[item.slot];
    inventory.remove(item);
    equipment[item.slot] = item;
    if (previous != null) inventory.add(previous);
    hp = min(hp, maxHp);
    changed();
    return true;
  }

  bool sell(Item item) {
    if (_remote('sell', {'idItem': item.id})) return true;
    if (zoneId != 0 || !inventory.contains(item)) return false;
    inventory.remove(item);
    gold += item.price;
    changed();
    return true;
  }

  bool buyPotion() {
    if (_remote('buy')) return true;
    if (zoneId != 0 || gold < 20) return false;
    gold -= 20;
    potions++;
    changed();
    return true;
  }

  void interact() {
    if (_remote('interact')) return;
    if (paused || dead || networkBlocked) return;
    for (final drop in state.drops.toList()) {
      if ((position - drop.position).distance < 85) {
        if (inventory.length >= 24) {
          tell('Mochila llena. Vende objetos en el refugio.');
          return;
        }
        inventory.add(drop.item);
        state.drops.remove(drop);
        tell('${drop.item.rarity}: ${drop.item.name}');
        changed();
        return;
      }
    }
    for (final chest in state.chests) {
      if (!chest.opened && (chest.position - position).distance < 110) {
        chest.opened = true;
        gold += 25;
        potions++;
        state.drops.add(Drop(chest.position + const Offset(0, 40), rollItem()));
        tell('Cofre abierto: 25 monedas, una poción y equipo.');
        changed();
        return;
      }
    }
    for (final gate in zone.gates) {
      if ((position - gate.position).distance < 115) {
        enter(gate.target);
        return;
      }
    }
    if (zoneId == 0) {
      hp = maxHp;
      mana = maxMana;
      tell('La hoguera restaura tu vida y energía.');
      changed();
    }
  }

  bool unlocked(int id) =>
      id < 2 ||
      (id == 2 ? seals.contains(1) : seals.contains(1) && seals.contains(2));
  bool enter(int id, {bool fast = false}) {
    if (companion != null && !partyLeader) {
      tell('El anfitrión dirige los viajes de todo el grupo.');
      return false;
    }
    if (dead || networkBlocked || id < 0 || id > 3) return false;
    if (fast) {
      if (!canTravel || !portals.contains(id)) {
        tell('Viaja desde un portal activo hacia otro descubierto.');
        return false;
      }
    } else if (!zone.gates.any(
      (g) => g.target == id && (g.position - position).distance < 115,
    )) {
      return false;
    }
    if (!unlocked(id)) {
      tell(
        id == 2
            ? 'Recupera el sello de Raíz corrompida para abrir la cripta.'
            : 'Necesitas los sellos del Bosque y la Cripta.',
      );
      return false;
    }
    final previous = zoneId;
    zoneId = id;
    position = fast
        ? zone.portal + const Offset(65, 0)
        : id > previous
        ? const Offset(285, 800)
        : const Offset(1830, 800);
    stop();
    effects.clear();
    hazards.clear();
    reveal();
    final ally = companion;
    if (ally != null) {
      ally.zoneId = zoneId;
      ally.position = position + const Offset(0, 55);
      ally.stop();
      ally.hazards.clear();
      ally.effects.clear();
      ally.reveal();
    }
    tell(zone.name);
    changed();
    return true;
  }

  void respawn() {
    if (_remote('respawn')) return;
    if (!dead) return;
    final ally = companion;
    if (ally != null && !ally.dead) {
      gold = max(0, gold - 15);
      position = ally.position + const Offset(0, 40);
      zoneId = ally.zoneId;
      hp = maxHp;
      mana = maxMana;
      dead = false;
      potions = max(3, potions);
      stop();
      changed();
      return;
    }
    gold = max(0, gold - 15);
    zoneId = 0;
    position = const Offset(940, 850);
    hp = maxHp;
    mana = maxMana;
    dead = false;
    paused = false;
    hazards.clear();
    effects.clear();
    potions = max(3, potions);
    stop();
    reveal();
    if (ally != null) {
      ally.zoneId = 0;
      ally.position = position + const Offset(0, 45);
      ally.hp = ally.maxHp;
      ally.mana = ally.maxMana;
      ally.dead = false;
      ally.gold = max(0, ally.gold - 15);
      ally.potions = max(3, ally.potions);
      ally.stop();
      ally.hazards.clear();
      ally.effects.clear();
      ally.reveal();
    }
    changed();
    tell(
      'Vuelves al refugio. Coste: hasta 15 monedas. Conservas tu equipo y progreso.',
    );
  }

  void predict(double dt) {
    if (paused || dead) return;
    time += dt;
    if (movement.distance > .05) {
      facing = movement / movement.distance;
      position = moveBody(position, movement * speed * dt);
    }
    for (final e in effects) {
      e.life -= dt;
    }
    effects.removeWhere((e) => e.life <= 0);
    notifyListeners();
  }

  Map<String, dynamic> networkSnapshot() => {
    ...toJson(),
    'clock': time,
    'message': message,
    'messageTime': messageTime,
    'cooldowns': [
      attackCooldown,
      skillCooldown,
      wardCooldown,
      wardTime,
      potionCooldown,
    ],
    'facing': [facing.dx, facing.dy],
    'hazards': hazards
        .map(
          (h) => [
            h.position.dx,
            h.position.dy,
            h.radius,
            h.damage,
            h.remaining,
          ],
        )
        .toList(),
    'effects': effects
        .map(
          (e) => {
            'kind': e.kind,
            'x': e.from.dx,
            'y': e.from.dy,
            'tx': e.to.dx,
            'ty': e.to.dy,
            'color': e.color,
            'text': e.text,
            'duration': e.duration,
            'life': e.life,
          },
        )
        .toList(),
  };

  void applyNetwork(
    Map<String, dynamic> data, {
    bool preserveMovement = false,
  }) {
    final fresh = Game.fromJson(data);
    if (fresh.heroClass != heroClass) {
      throw const FormatException('Clase incompatible');
    }
    zones
      ..clear()
      ..addAll(fresh.zones);
    inventory
      ..clear()
      ..addAll(fresh.inventory);
    equipment
      ..clear()
      ..addAll(fresh.equipment);
    portals
      ..clear()
      ..addAll(fresh.portals);
    seals
      ..clear()
      ..addAll(fresh.seals);
    zoneId = fresh.zoneId;
    position = fresh.position;
    level = fresh.level;
    xp = fresh.xp;
    gold = fresh.gold;
    potions = fresh.potions;
    kills = fresh.kills;
    nextItem = fresh.nextItem;
    hp = fresh.hp;
    mana = fresh.mana;
    won = fresh.won;
    dead = fresh.dead;
    time = (data['clock'] as num).toDouble();
    message = data['message'] as String;
    messageTime = (data['messageTime'] as num).toDouble();
    final timers = (data['cooldowns'] as List)
        .map((v) => (v as num).toDouble())
        .toList();
    attackCooldown = timers[0];
    skillCooldown = timers[1];
    wardCooldown = timers[2];
    wardTime = timers[3];
    potionCooldown = timers[4];
    facing = Offset(
      (data['facing'][0] as num).toDouble(),
      (data['facing'][1] as num).toDouble(),
    );
    hazards
      ..clear()
      ..addAll(
        (data['hazards'] as List).map(
          (h) => Hazard(
            Offset((h[0] as num).toDouble(), (h[1] as num).toDouble()),
            (h[2] as num).toDouble(),
            (h[3] as num).toDouble(),
            (h[4] as num).toDouble(),
          ),
        ),
      );
    effects
      ..clear()
      ..addAll(
        (data['effects'] as List).map(
          (e) => VisualEffect(
            e['kind'] as String,
            Offset((e['x'] as num).toDouble(), (e['y'] as num).toDouble()),
            Offset((e['tx'] as num).toDouble(), (e['ty'] as num).toDouble()),
            e['color'] as int,
            text: e['text'] as String,
            duration: (e['duration'] as num).toDouble(),
          )..life = (e['life'] as num).toDouble(),
        ),
      );
    if (!preserveMovement) stop();
    fresh.dispose();
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'class': heroClass.index,
    'zone': zoneId,
    'position': [position.dx, position.dy],
    'level': level,
    'xp': xp,
    'gold': gold,
    'potions': potions,
    'kills': kills,
    'nextItem': nextItem,
    'hp': hp,
    'mana': mana,
    'won': won,
    'dead': dead,
    'portals': portals.toList(),
    'seals': seals.toList(),
    'inventory': inventory.map((e) => e.toJson()).toList(),
    'equipment': equipment.values.map((e) => e.toJson()).toList(),
    'zones': {
      for (final entry in zones.entries)
        '${entry.key}': {
          'monsters': entry.value.monsters
              .map(
                (m) => {
                  'id': m.id,
                  'hp': m.hp,
                  'x': m.position.dx,
                  'y': m.position.dy,
                },
              )
              .toList(),
          'chests': entry.value.chests.map((c) => c.opened).toList(),
          'explored': entry.value.explored.toList(),
          'drops': entry.value.drops
              .map(
                (d) => {
                  'x': d.position.dx,
                  'y': d.position.dy,
                  'item': d.item.toJson(),
                },
              )
              .toList(),
        },
    },
  };

  factory Game.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Versión de partida incompatible');
    }
    final g = Game(HeroClass.values[j['class'] as int]);
    g.zoneId = j['zone'] as int;
    if (g.zoneId < 0 || g.zoneId > 3) {
      throw const FormatException('Zona inválida');
    }
    g.position = Offset(
      (j['position'][0] as num).toDouble(),
      (j['position'][1] as num).toDouble(),
    );
    g.level = j['level'] as int;
    g.xp = j['xp'] as int;
    g.gold = j['gold'] as int;
    g.potions = j['potions'] as int;
    g.kills = j['kills'] as int;
    g.nextItem = j['nextItem'] as int;
    g.won = j['won'] as bool;
    g.dead = j['dead'] as bool;
    g.portals
      ..clear()
      ..addAll((j['portals'] as List).cast<int>());
    g.seals.addAll((j['seals'] as List).cast<int>());
    g.inventory.addAll(
      (j['inventory'] as List).map(
        (e) => Item.fromJson(Map<String, dynamic>.from(e)),
      ),
    );
    g.equipment.clear();
    for (final e in j['equipment'] as List) {
      final item = Item.fromJson(Map<String, dynamic>.from(e));
      g.equipment[item.slot] = item;
    }
    g.hp = (j['hp'] as num).toDouble().clamp(0, g.maxHp);
    g.mana = (j['mana'] as num).toDouble().clamp(0, g.maxMana);
    for (final entry in (j['zones'] as Map<String, dynamic>).entries) {
      final s = g.zones[int.parse(entry.key)]!, saved = entry.value;
      for (final data in saved['monsters'] as List) {
        final m = s.monsters.firstWhere((m) => m.id == data['id']);
        m.hp = (data['hp'] as num).toDouble().clamp(0, m.maxHp);
        m.position = Offset(
          (data['x'] as num).toDouble(),
          (data['y'] as num).toDouble(),
        );
      }
      for (var i = 0; i < s.chests.length; i++) {
        s.chests[i].opened = saved['chests'][i] as bool;
      }
      s.explored
        ..clear()
        ..addAll((saved['explored'] as List).cast<int>());
      s.drops.addAll(
        (saved['drops'] as List).map(
          (d) => Drop(
            Offset((d['x'] as num).toDouble(), (d['y'] as num).toDouble()),
            Item.fromJson(Map<String, dynamic>.from(d['item'])),
          ),
        ),
      );
    }
    if (!g.position.dx.isFinite ||
        !g.position.dy.isFinite ||
        !g.walkable(g.position)) {
      g.position = g.zone.portal + const Offset(70, 0);
    }
    if (g.hp <= 0) g.dead = true;
    g.message = 'Tu aventura continúa.';
    g.reveal();
    return g;
  }
}
