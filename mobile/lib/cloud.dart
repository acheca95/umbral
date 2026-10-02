import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';
import 'game.dart';

String firebaseMessage(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is TimeoutException) {
    return 'Firebase no responde. Comprueba la conexión y vuelve a intentarlo.';
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'email-already-in-use' ||
      'credential-already-in-use' => 'Ese correo ya tiene cuenta. Usa Entrar.',
      'invalid-email' => 'Introduce un correo válido.',
      'weak-password' => 'Utiliza una contraseña de al menos 8 caracteres.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Correo o contraseña incorrectos.',
      'permission-denied' => 'Firebase ha rechazado la operación. Revisa la cuenta y actualiza la app.',
      'resource-exhausted' =>
        'Se ha alcanzado la cuota de Firebase. Inténtalo más tarde.',
      'unavailable' || 'network-request-failed' => 'Sin conexión con Firebase. El progreso sigue guardado en el dispositivo.',
      'too-many-requests' => 'Demasiados intentos. Espera un momento.',
      _ => 'No se pudo completar la operación (${error.code}).',
    };
  }
  return 'No se pudo completar la operación con Firebase.';
}

class CloudService extends ChangeNotifier {
  final SharedPreferences preferences;
  FirebaseFirestore? database;
  String? uid, email, error;
  bool busy = false, anonymous = true, syncing = false, available = false;
  int revision = 0;
  Map<String, dynamic>? summary;
  DateTime lastUpload = DateTime.fromMillisecondsSinceEpoch(0);
  Duration serverOffset = Duration.zero;
  bool _disposed = false;
  CloudService(this.preferences);
  bool get connected => available && uid != null && database != null;
  bool get autoSync =>
      connected && preferences.getString('umbral.cloud.owner') == uid;
  DateTime get serverNow => DateTime.now().add(serverOffset);
  String get status =>
      error ??
      (syncing
          ? 'Guardando en Firebase…'
          : !connected
          ? 'Firebase sin conectar'
          : anonymous
          ? 'Invitado • vincula un correo para recuperar la partida'
          : autoSync
          ? 'Nube activa · $email'
          : 'Cuenta conectada · sincronización pendiente');
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> connect() async {
    if (busy) return false;
    busy = true;
    error = null;
    changed();
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: FirebaseConfig.options);
      }
      if (database == null) {
        database = FirebaseFirestore.instance;
        database!.settings = const Settings(persistenceEnabled: false);
      }
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
      uid = user.uid;
      email = user.email;
      anonymous = user.isAnonymous;
      final clock = database!.collection('umbralPresenceV1').doc(uid);
      await clock
          .set({'seenAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));
      final snap = await clock
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      serverOffset = (snap.data()!['seenAt'] as Timestamp).toDate().difference(
        DateTime.now(),
      );
      available = true;
      await refresh();
      return true;
    } catch (e) {
      available = false;
      error = firebaseMessage(e);
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> account(
    String mail,
    String password, {
    required bool register,
  }) async {
    if (busy || !connected) return;
    busy = true;
    error = null;
    changed();
    try {
      if (register && password.length < 8) {
        throw StateError('Utiliza una contraseña de al menos 8 caracteres.');
      }
      final auth = FirebaseAuth.instance;
      final credential = EmailAuthProvider.credential(
        email: mail.trim(),
        password: password,
      );
      final result = register && auth.currentUser?.isAnonymous == true
          ? await auth.currentUser!.linkWithCredential(credential)
          : register
          ? await auth.createUserWithEmailAndPassword(
              email: mail.trim(),
              password: password,
            )
          : await auth.signInWithEmailAndPassword(
              email: mail.trim(),
              password: password,
            );
      uid = result.user!.uid;
      email = result.user!.email;
      anonymous = result.user!.isAnonymous;
      await refresh();
    } catch (e) {
      error = firebaseMessage(e);
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> resetPassword(String mail) async {
    if (!connected || busy) return;
    busy = true;
    error = null;
    changed();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: mail.trim());
      error = 'Si existe una cuenta con ese correo, recibirás instrucciones para recuperar el acceso.';
    } catch (e) {
      error = firebaseMessage(e);
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> signOut() async {
    if (busy || syncing) return;
    await FirebaseAuth.instance.signOut();
    uid = null;
    email = null;
    summary = null;
    revision = 0;
    anonymous = true;
    available = false;
    await preferences.remove('umbral.cloud.owner');
    changed();
  }

  DocumentReference<Map<String, dynamic>> get saveRef =>
      database!.collection('umbralSavesV1').doc(uid);
  Future<void> refresh() async {
    final snap = await saveRef
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    summary = snap.data();
    // Never adopt a newer revision silently when this device has a bound save.
    if (!autoSync) {
      revision = summary?['revision'] as int? ?? 0;
    } else {
      revision = preferences.getInt('umbral.cloud.revision.$uid') ?? 0;
    }
    changed();
  }

  Future<bool> upload(Game game, {bool replace = false}) async {
    if (!connected || syncing || (!replace && !autoSync)) return false;
    syncing = true;
    lastUpload = DateTime.now();
    error = null;
    changed();
    final owner = uid!, payload = jsonEncode(game.toJson());
    try {
      if (payload.length > 240000) {
        throw StateError(
          'La partida supera el tamaño permitido para esta demo.',
        );
      }
      final ref = saveRef;
      final next = await database!
          .runTransaction<int>((tx) async {
            final current = (await tx.get(ref)).data();
            final remoteRev = current?['revision'] as int? ?? 0;
            if (!replace && remoteRev != revision) {
              throw StateError(
                'Hay progreso más reciente en otro dispositivo. Restaura la nube o elige subir esta partida desde el menú.',
              );
            }
            tx.set(ref, {
              'version': 1,
              'revision': remoteRev + 1,
              'payload': payload,
              'heroClass': game.heroClass.index,
              'level': game.level,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            return remoteRev + 1;
          })
          .timeout(const Duration(seconds: 12));
      if (uid != owner) return false;
      revision = next;
      lastUpload = DateTime.now();
      await preferences.setString('umbral.cloud.owner', owner);
      await preferences.setInt('umbral.cloud.revision.$owner', revision);
      summary = {
        'level': game.level,
        'heroClass': game.heroClass.index,
        'revision': revision,
      };
      return true;
    } catch (e) {
      error = firebaseMessage(e);
      return false;
    } finally {
      syncing = false;
      changed();
    }
  }

  Future<Game?> download() async {
    if (!connected || busy || syncing) return null;
    busy = true;
    error = null;
    changed();
    try {
      final data =
          (await saveRef
                  .get(const GetOptions(source: Source.server))
                  .timeout(const Duration(seconds: 10)))
              .data();
      if (data == null) {
        throw StateError(
          'Esta cuenta todavía no tiene una partida en la nube.',
        );
      }
      final game = Game.fromJson(
        jsonDecode(data['payload'] as String) as Map<String, dynamic>,
      );
      revision = data['revision'] as int;
      summary = data;
      await preferences.setString('umbral.cloud.owner', uid!);
      await preferences.setInt('umbral.cloud.revision.$uid', revision);
      return game;
    } catch (e) {
      error = firebaseMessage(e);
      return null;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> autoUpload(Game game) async {
    if (autoSync &&
        !busy &&
        DateTime.now().difference(lastUpload).inSeconds >= 60) {
      await upload(game);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
