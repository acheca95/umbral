import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'cloud.dart';
import 'game.dart';

/// The host owns the simulation. The guest only sends input and predicts motion.
class CoopSession extends ChangeNotifier {
  final FirebaseFirestore db;
  final String uid;
  final DateTime Function() now;
  final Game local;
  Game? other;
  bool isHost = false, ready = false, closed = false, backgrounded = false;
  bool peerPaused = false,
      _writing = false,
      _publishing = false,
      _disposed = false;
  String code = '', status = 'Conectando…', peerName = 'Compañero';
  String? error;
  DocumentReference<Map<String, dynamic>>? _room;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _sender, _heartbeat;
  int _nextAction = 0, _ack = 0, _viewSeq = 0, _seenView = -1;
  final List<Map<String, dynamic>> _actions = [];
  DateTime _peerSeen = DateTime.now(),
      _lastAck = DateTime.now(),
      _inputSeen = DateTime.now();
  CoopSession({
    required this.db,
    required this.uid,
    required this.local,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;
  bool get healthy =>
      DateTime.now().difference(_peerSeen).inSeconds < 9 &&
      DateTime.now().difference(_lastAck).inSeconds < 10;
  bool get canPlay =>
      ready && !closed && healthy && !backgrounded && !peerPaused;
  String get banner => closed
      ? 'Sala terminada. Guarda y vuelve al inicio.'
      : !ready
      ? 'Sala $code · esperando al compañero'
      : !healthy
      ? 'Conexión interrumpida · partida pausada'
      : peerPaused
      ? '$peerName está en un panel · pausa compartida'
      : 'Cooperativo · $code · $peerName';
  void changed() {
    if (!_disposed) notifyListeners();
  }

  String _code() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => letters[r.nextInt(letters.length)]).join();
  }

  Future<void> create(String name) async {
    isHost = true;
    for (var attempt = 0; attempt < 5; attempt++) {
      final ref = db.collection('umbralRoomsV1').doc(_code());
      final made = await db
          .runTransaction<bool>((tx) async {
            if ((await tx.get(ref)).exists) return false;
            tx.set(ref, {
              'version': 1,
              'hostUid': uid,
              'guestUid': null,
              'hostName': name,
              'guestName': '',
              'hostClass': local.heroClass.index,
              'guestClass': -1,
              'status': 'waiting',
              'createdAt': FieldValue.serverTimestamp(),
              'hostSeen': FieldValue.serverTimestamp(),
              'guestSeen': null,
              'expiresAt': Timestamp.fromDate(
                now().add(const Duration(hours: 2)),
              ),
            });
            return true;
          })
          .timeout(const Duration(seconds: 12));
      if (made) {
        _room = ref;
        code = ref.id;
        _watch();
        return;
      }
    }
    throw StateError('No se pudo crear la sala. Inténtalo otra vez.');
  }

  Future<void> join(String input, String name) async {
    final id = input.trim().toUpperCase();
    if (!RegExp(r'^[A-Z2-9]{6}$').hasMatch(id)) {
      throw StateError('Introduce el código de seis caracteres.');
    }
    final ref = db.collection('umbralRoomsV1').doc(id);
    await db
        .runTransaction((tx) async {
          final data = (await tx.get(ref)).data();
          if (data == null ||
              data['version'] != 1 ||
              data['status'] != 'waiting' ||
              data['hostUid'] == uid ||
              data['guestUid'] != null ||
              now()
                      .difference((data['hostSeen'] as Timestamp).toDate())
                      .inSeconds >
                  20 ||
              (data['expiresAt'] as Timestamp).toDate().isBefore(now())) {
            throw StateError(
              'La sala no está disponible. Comprueba el código y la conexión del anfitrión.',
            );
          }
          tx.update(ref, {
            'guestUid': uid,
            'guestName': name,
            'guestClass': local.heroClass.index,
            'guestSeen': FieldValue.serverTimestamp(),
            'status': 'playing',
          });
          tx.set(ref.collection('players').doc(uid), {
            'payload': jsonEncode(local.toJson()),
            'createdAt': FieldValue.serverTimestamp(),
          });
        })
        .timeout(const Duration(seconds: 12));
    _room = ref;
    code = id;
    isHost = false;
    local.remoteInput = enqueue;
    local.partyLeader = false;
    _watch();
  }

  void _watch() {
    _peerSeen = _lastAck = DateTime.now();
    _subs.add(
      _room!.snapshots(includeMetadataChanges: true).listen((snap) async {
        if (_disposed || !snap.exists || snap.metadata.isFromCache) return;
        final data = snap.data()!;
        if (data['status'] == 'closed') {
          closed = true;
          local.stop();
          local.networkBlocked = true;
          changed();
          return;
        }
        peerName = (data[isHost ? 'guestName' : 'hostName'] as String).isEmpty
            ? 'Compañero'
            : data[isHost ? 'guestName' : 'hostName'] as String;
        final stamp = data[isHost ? 'guestSeen' : 'hostSeen'];
        if (stamp is Timestamp &&
            now().difference(stamp.toDate()).inSeconds < 10) {
          _peerSeen = DateTime.now();
        }
        if (isHost && data['guestUid'] != null && other == null) {
          try {
            final profile = await _room!
                .collection('players')
                .doc(data['guestUid'] as String)
                .get(const GetOptions(source: Source.server));
            if (_disposed || other != null) return;
            final guest = Game.fromJson(
              jsonDecode(profile.data()!['payload'] as String)
                  as Map<String, dynamic>,
            );
            if (guest.heroClass.index != data['guestClass']) {
              throw StateError('La clase del invitado no coincide.');
            }
            attach(guest);
            await _publish();
          } catch (e) {
            error = firebaseMessage(e);
            changed();
          }
        }
        changed();
      }, onError: _onError),
    );
    if (isHost) {
      _subs.add(
        _room!.collection('input').doc('guest').snapshots().listen((snap) {
          if (_disposed || other == null || !snap.exists || closed) return;
          final d = snap.data()!, stamp = d['sentAt'];
          if (stamp is! Timestamp ||
              now().difference(stamp.toDate()).inMilliseconds > 3000) {
            return;
          }
          _peerSeen = _inputSeen = DateTime.now();
          applyInput(d);
          changed();
        }, onError: _onError),
      );
      _sender = Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => _publish(),
      );
    } else {
      _subs.add(
        _room!.collection('state').doc('world').snapshots().listen((snap) {
          if (_disposed ||
              !snap.exists ||
              snap.metadata.isFromCache ||
              closed) {
            return;
          }
          final d = snap.data()!;
          if ((d['seq'] as int) <= _seenView) return;
          _seenView = d['seq'] as int;
          _peerSeen = DateTime.now();
          try {
            final packet =
                jsonDecode(d['payload'] as String) as Map<String, dynamic>;
            local.applyNetwork(
              Map<String, dynamic>.from(packet['guest'] as Map),
              preserveMovement: true,
            );
            final hostData = Map<String, dynamic>.from(packet['host'] as Map);
            other ??= Game.fromJson(hostData);
            other!.applyNetwork(hostData);
            local.companion = other;
            other!.companion = local;
            local.partyLeader = false;
            _ack = packet['ack'] as int;
            _actions.removeWhere((a) => (a['id'] as int) <= _ack);
            peerPaused = packet['paused'] as bool;
            ready = true;
            error = null;
            changed();
          } catch (e) {
            _onError(e);
          }
        }, onError: _onError),
      );
      _sender = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _send(),
      );
    }
    _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) => _beat());
    unawaited(_beat());
    changed();
  }

  void attach(Game guest) {
    other = guest;
    guest.zones
      ..clear()
      ..addAll(local.zones);
    guest.zoneId = local.zoneId;
    guest.position = local.position + const Offset(0, 55);
    guest.portals
      ..clear()
      ..addAll(local.portals);
    guest.seals
      ..clear()
      ..addAll(local.seals);
    guest.won = local.won;
    guest.dead = false;
    guest.hp = guest.maxHp;
    guest.hazards = local.hazards;
    local.companion = guest;
    guest.companion = local;
    guest.partyLeader = false;
    ready = true;
    local.stop();
    guest.stop();
    changed();
  }

  void enqueue(String action, Map<String, dynamic> data) {
    if (closed || !ready || !healthy) {
      local.tell('Espera a recuperar la conexión.');
      return;
    }
    if (_actions.length >= 24) {
      local.tell('Esperando confirmación de tus acciones.');
      return;
    }
    _actions.add({'id': ++_nextAction, 'action': action, ...data});
    unawaited(_send());
  }

  void applyInput(Map<String, dynamic> input) {
    final guest = other!;
    peerPaused = input['paused'] as bool;
    guest.paused = peerPaused;
    if (peerPaused) {
      guest.stop();
    } else {
      guest.steer(
        Offset(
          (input['dx'] as num).toDouble(),
          (input['dy'] as num).toDouble(),
        ),
      );
      guest.attacking = input['attack'] as bool;
    }
    for (final raw in input['actions'] as List) {
      final a = Map<String, dynamic>.from(raw as Map), id = a['id'] as int;
      if (id <= _ack) continue;
      _ack = id;
      final kind = a['action'];
      // Menus pause the world but equipment and merchant actions remain valid.
      if (local.paused && !['equip', 'sell', 'buy', 'respawn'].contains(kind)) {
        continue;
      }
      switch (kind) {
        case 'tap':
        case 'walk':
          final x = a['x'], y = a['y'];
          if (x is num && y is num && x.isFinite && y.isFinite) {
            final p = Offset(x.toDouble(), y.toDouble());
            if (kind == 'tap') {
              guest.tapWorld(p);
            } else {
              guest.walkTo(p);
            }
          }
        case 'primary':
          guest.castPrimary();
        case 'ward':
          guest.castWard();
        case 'potion':
          guest.drinkPotion();
        case 'interact':
          guest.interact();
        case 'respawn':
          guest.respawn();
        case 'buy':
          guest.buyPotion();
        case 'equip':
        case 'sell':
          final items = guest.inventory.where((i) => i.id == a['idItem']);
          if (items.isNotEmpty) {
            if (kind == 'equip') {
              guest.equip(items.first);
            } else {
              guest.sell(items.first);
            }
          }
      }
    }
  }

  Future<void> _send() async {
    if (_disposed || _writing || isHost || _room == null || closed) return;
    _writing = true;
    try {
      await _room!
          .collection('input')
          .doc('guest')
          .set({
            'dx': local.movement.dx,
            'dy': local.movement.dy,
            'attack': local.attacking,
            'paused': local.paused || backgrounded,
            'actions': _actions.take(4).toList(),
            'sentAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 6));
      _lastAck = DateTime.now();
    } catch (e) {
      _onError(e);
    } finally {
      _writing = false;
    }
  }

  Future<void> _publish() async {
    if (_disposed ||
        _publishing ||
        !isHost ||
        !ready ||
        closed ||
        other == null) {
      return;
    }
    _publishing = true;
    try {
      final packet = {
        'host': local.networkSnapshot(),
        'guest': other!.networkSnapshot(),
        'ack': _ack,
        'paused': local.paused || backgrounded,
      };
      await _room!
          .collection('state')
          .doc('world')
          .set({
            'payload': jsonEncode(packet),
            'seq': ++_viewSeq,
            'sentAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 6));
      _lastAck = DateTime.now();
      error = null;
    } catch (e) {
      _onError(e);
    } finally {
      _publishing = false;
    }
  }

  Future<void> _beat() async {
    if (_room == null || closed || _disposed) return;
    try {
      await _room!
          .update({
            isHost ? 'hostSeen' : 'guestSeen': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 6));
      _lastAck = DateTime.now();
      changed();
    } catch (e) {
      _onError(e);
    }
  }

  void frame(double dt) {
    if (!canPlay || local.paused) return;
    dt = dt.clamp(0, .05);
    if (!isHost) {
      local.predict(dt);
      return;
    }
    final guest = other!;
    if (DateTime.now().difference(_inputSeen).inMilliseconds > 1200) {
      guest.stop();
    }
    if (local.dead && !guest.dead) {
      guest.tick(dt);
    } else {
      local.tick(dt);
      guest.tick(dt, simulateWorld: false);
    }
    local.portals.addAll(guest.portals);
    guest.portals.addAll(local.portals);
    local.seals.addAll(guest.seals);
    guest.seals.addAll(local.seals);
  }

  void _onError(Object e) {
    error = firebaseMessage(e);
    changed();
  }

  Future<void> leave() async {
    final ref = _room;
    closed = true;
    _sender?.cancel();
    _heartbeat?.cancel();
    local.stop();
    local.remoteInput = null;
    local.companion = null;
    local.partyLeader = true;
    local.networkBlocked = false;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await ref
          ?.update({
            'status': 'closed',
            isHost ? 'hostSeen' : 'guestSeen': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      error = firebaseMessage(e);
    }
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _sender?.cancel();
    _heartbeat?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    local.remoteInput = null;
    local.companion = null;
    local.partyLeader = true;
    local.networkBlocked = false;
    other?.companion = null;
    other?.dispose();
    super.dispose();
  }
}
