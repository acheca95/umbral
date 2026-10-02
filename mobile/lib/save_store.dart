import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';

class SaveStore {
  final SharedPreferences preferences;
  Future<void> _pending = Future.value();
  String? warning;
  SaveStore(this.preferences);
  Game? load() {
    for (final key in ['umbral.save.v1', 'umbral.backup.v1']) {
      final raw = preferences.getString(key);
      if (raw == null) continue;
      try {
        final game = Game.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (key.contains('backup')) {
          warning = 'Se ha recuperado la copia anterior del progreso.';
        }
        return game;
      } catch (_) {
        warning = 'No se ha podido leer la partida guardada.';
      }
    }
    return null;
  }

  Future<void> save(Game game) {
    final snapshot = jsonEncode(game.toJson());
    _pending = _pending.catchError((Object _) {}).then((_) async {
      final previous = preferences.getString('umbral.save.v1');
      if (previous != null) {
        var valid = false;
        try {
          final checked = Game.fromJson(
            jsonDecode(previous) as Map<String, dynamic>,
          );
          checked.dispose();
          valid = true;
        } catch (_) {
          // Keep the last valid backup when the primary file was damaged.
        }
        if (valid &&
            !await preferences.setString('umbral.backup.v1', previous)) {
          throw StateError('No se pudo guardar la copia de respaldo');
        }
      }
      if (!await preferences.setString('umbral.save.v1', snapshot)) {
        throw StateError('No se pudo guardar el progreso');
      }
    });
    return _pending;
  }
}
