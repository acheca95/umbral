import 'dart:math';
import 'dart:ui';

enum HeroClass { guardian, arcanist, ranger }

extension HeroClassInfo on HeroClass {
  String get label => ['Guardián', 'Arcanista', 'Exploradora'][index];
  String get role => [
    'Acero y resistencia',
    'Fuego y magia ancestral',
    'Arco y artes del bosque',
  ][index];
  String get description => [
    'Combate cercano. Mucha vida, armadura y un torbellino que golpea a todos los enemigos alrededor.',
    'Ataques a distancia. Desata una nova de fuego y recupera energía bajo una barrera arcana.',
    'Ataques a distancia. Una lluvia de flechas y un paso veloz para curarte y reposicionarte.',
  ][index];
  String get primary =>
      ['Torbellino', 'Nova de fuego', 'Lluvia de flechas'][index];
  String get secondary =>
      ['Bastión', 'Barrera arcana', 'Paso del bosque'][index];
  int get color => [0xffe2bd7c, 0xffac9aff, 0xff79ceb0][index];
}

enum Slot { weapon, armor, charm }

extension SlotInfo on Slot {
  String get label => ['Arma', 'Armadura', 'Talismán'][index];
}

class Item {
  final int id, tier, power, armor, vitality;
  final Slot slot;
  final String name;
  const Item(
    this.id,
    this.name,
    this.slot,
    this.tier,
    this.power,
    this.armor,
    this.vitality,
  );
  int get price => 8 + tier * 10 + power * 2 + armor * 2;
  int get color => [0xffc1c6bc, 0xff78cfad, 0xffa798ef, 0xffedc16f][tier];
  String get rarity => ['Común', 'Inusual', 'Épico', 'Legendario'][tier];
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slot': slot.index,
    'tier': tier,
    'power': power,
    'armor': armor,
    'vitality': vitality,
  };
  factory Item.fromJson(Map<String, dynamic> j) => Item(
    j['id'] as int,
    j['name'] as String,
    Slot.values[j['slot'] as int],
    j['tier'] as int,
    j['power'] as int,
    j['armor'] as int,
    j['vitality'] as int,
  );
}

class Gate {
  final Offset position;
  final int target;
  final String label;
  const Gate(this.position, this.target, this.label);
}

class Zone {
  final int id;
  final String name, subtitle;
  final int ground, accent;
  final Offset portal;
  final List<Gate> gates;
  const Zone(
    this.id,
    this.name,
    this.subtitle,
    this.ground,
    this.accent,
    this.portal,
    this.gates,
  );
  static const double width = 2200, height = 1600;
  static const all = [
    Zone(
      0,
      'Refugio del Alba',
      'SANTUARIO • ZONA SEGURA',
      0xff232f2c,
      0xffe4c389,
      Offset(850, 850),
      [Gate(Offset(1920, 800), 1, 'Bosque de espinas')],
    ),
    Zone(
      1,
      'Bosque de espinas',
      'TERRITORIO I • NIVEL 1–3',
      0xff1b2d29,
      0xff79c8a4,
      Offset(550, 800),
      [
        Gate(Offset(170, 800), 0, 'Refugio del Alba'),
        Gate(Offset(1980, 800), 2, 'Cripta olvidada'),
      ],
    ),
    Zone(
      2,
      'Cripta olvidada',
      'TERRITORIO II • NIVEL 3–5',
      0xff252731,
      0xffa79adb,
      Offset(520, 800),
      [
        Gate(Offset(170, 800), 1, 'Bosque de espinas'),
        Gate(Offset(1970, 800), 3, 'Corazón de ceniza'),
      ],
    ),
    Zone(
      3,
      'Corazón de ceniza',
      'TERRITORIO III • EL ÚLTIMO SELLO',
      0xff322523,
      0xffec9a70,
      Offset(480, 800),
      [Gate(Offset(170, 800), 2, 'Cripta olvidada')],
    ),
  ];

  static final Map<int, List<Rect>> _obstacleCache = {};
  List<Rect> get obstacles => _obstacleCache.putIfAbsent(id, _makeObstacles);
  List<Rect> _makeObstacles() {
    if (id == 0) {
      return [
        const Rect.fromLTWH(600, 430, 210, 160),
        const Rect.fromLTWH(1040, 400, 260, 190),
        const Rect.fromLTWH(1150, 1050, 240, 170),
      ];
    }
    // The central road, portal, gates and boss arena stay traversable.
    final random = Random(71 + id * 43);
    return List.generate(32, (i) {
          final x = 280 + random.nextDouble() * 1520;
          final y = i.isEven
              ? 160 + random.nextDouble() * 360
              : 1030 + random.nextDouble() * 290;
          return Rect.fromLTWH(
            x,
            y,
            45 + random.nextDouble() * 65,
            35 + random.nextDouble() * 60,
          );
        })
        .where(
          (r) =>
              !r.inflate(90).contains(const Offset(870, 320)) &&
              !r.inflate(90).contains(const Offset(1460, 1280)),
        )
        .toList(growable: false);
  }
}

enum MonsterKind { crawler, brute, wisp, boss }

class Monster {
  final int id;
  final MonsterKind kind;
  final String name;
  final Offset home;
  final double maxHp;
  Offset position;
  double hp, cooldown = 0, slow = 0, flash = 0;
  Monster(this.id, this.kind, this.name, this.home, this.maxHp)
    : position = home,
      hp = maxHp;
  bool get alive => hp > 0;
  bool get boss => kind == MonsterKind.boss;
  double get radius => boss
      ? 32
      : kind == MonsterKind.brute
      ? 24
      : 17;
}

class Drop {
  final Offset position;
  final Item item;
  Drop(this.position, this.item);
}

class Chest {
  final Offset position;
  bool opened = false;
  Chest(this.position);
}

class ZoneState {
  final List<Monster> monsters;
  final List<Chest> chests;
  final List<Drop> drops = [];
  final Set<int> explored = {};
  ZoneState(this.monsters, this.chests);
  factory ZoneState.generate(int zone) {
    if (zone == 0) return ZoneState([], []);
    final random = Random(zone * 37);
    final monsters = <Monster>[];
    for (var i = 0; i < 13; i++) {
      final kind = i % 4 == 3
          ? MonsterKind.wisp
          : i % 4 == 2
          ? MonsterKind.brute
          : MonsterKind.crawler;
      final pos = Offset(
        800 + (i % 5) * 210 + random.nextDouble() * 75,
        620 + (i ~/ 5) * 150 + random.nextDouble() * 40,
      );
      monsters.add(
        Monster(
          zone * 100 + i,
          kind,
          ['Acechador', 'Quebrantahuesos', 'Espectro'][kind.index],
          pos,
          (kind == MonsterKind.brute ? 85 : 48) + zone * 17.0,
        ),
      );
    }
    monsters.add(
      Monster(
        zone * 100 + 99,
        MonsterKind.boss,
        [
          '',
          'Raíz corrompida',
          'Custodio del olvido',
          'El Rey de Ceniza',
        ][zone],
        const Offset(1770, 800),
        zone == 3 ? 760 : 270 + zone * 100,
      ),
    );
    return ZoneState(monsters, [
      Chest(const Offset(870, 320)),
      Chest(const Offset(1460, 1280)),
    ]);
  }
}

class VisualEffect {
  final Offset from, to;
  final int color;
  final String text;
  final String kind;
  final double duration;
  double life;
  VisualEffect(
    this.kind,
    this.from,
    this.to,
    this.color, {
    this.text = '',
    this.duration = .45,
  }) : life = duration;
}

class Hazard {
  final Offset position;
  final double radius, damage;
  double remaining;
  Hazard(this.position, this.radius, this.damage, this.remaining);
}
