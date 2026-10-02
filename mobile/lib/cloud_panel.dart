import 'package:flutter/material.dart';

import 'cloud.dart';
import 'coop.dart';
import 'game.dart';
import 'world.dart';

class CloudPanel extends StatefulWidget {
  final CloudService cloud;
  final Game? saved;
  final HeroClass selected;
  final Future<void> Function(Game) onRestore;
  final void Function(CoopSession) onPlay;
  const CloudPanel({
    super.key,
    required this.cloud,
    required this.saved,
    required this.selected,
    required this.onRestore,
    required this.onPlay,
  });
  @override
  State<CloudPanel> createState() => _CloudPanelState();
}

class _CloudPanelState extends State<CloudPanel> {
  final mail = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(text: 'Viajero'),
      code = TextEditingController();
  bool working = false;
  String? message;
  Game? current;
  CloudService get cloud => widget.cloud;
  @override
  void initState() {
    super.initState();
    current = widget.saved;
    if (!cloud.connected) cloud.connect();
  }

  @override
  void dispose() {
    mail.dispose();
    password.dispose();
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> play(bool host) async {
    setState(() {
      working = true;
      message = null;
    });
    final game = current == null
        ? Game(widget.selected)
        : Game.fromJson(current!.toJson());
    final session = CoopSession(
      db: cloud.database!,
      uid: cloud.uid!,
      local: game,
      clock: () => cloud.serverNow,
    );
    try {
      final label = name.text.trim().isEmpty ? 'Viajero' : name.text.trim();
      if (host) {
        await session.create(label);
      } else {
        await session.join(code.text, label);
      }
      if (!mounted) {
        await session.leave();
        session.dispose();
        game.dispose();
        return;
      }
      Navigator.pop(context);
      widget.onPlay(session);
    } catch (e) {
      session.dispose();
      game.dispose();
      if (mounted) setState(() => message = firebaseMessage(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650, maxHeight: 720),
      child: AnimatedBuilder(
        animation: cloud,
        builder: (_, _) {
          final locked = working || cloud.busy || cloud.syncing;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Firebase · Nube y cooperativo',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar Firebase',
                      onPressed: working ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        cloud.status,
                        style: TextStyle(
                          color: cloud.error == null
                              ? const Color(0xff84cbb8)
                              : const Color(0xffdfbd84),
                        ),
                      ),
                      if (locked)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (!cloud.connected)
                        FilledButton(
                          onPressed: locked ? null : cloud.connect,
                          child: const Text('Conectar a Firebase'),
                        ),
                      if (cloud.connected) ...[
                        const SizedBox(height: 16),
                        Text(
                          cloud.anonymous
                              ? 'CUENTA RECUPERABLE'
                              : 'CUENTA: ${cloud.email}',
                          style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                        if (cloud.anonymous) ...[
                          const Text(
                            'Puedes jugar como invitado. Vincula un correo y contraseña para recuperar tu progreso en otro móvil.',
                            style: TextStyle(fontSize: 12),
                          ),
                          TextField(
                            controller: mail,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                            ),
                          ),
                          TextField(
                            controller: password,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña (mínimo 8 caracteres)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: locked
                                    ? null
                                    : () => cloud.account(
                                        mail.text,
                                        password.text,
                                        register: true,
                                      ),
                                child: const Text('Crear cuenta'),
                              ),
                              OutlinedButton(
                                onPressed: locked
                                    ? null
                                    : () => cloud.account(
                                        mail.text,
                                        password.text,
                                        register: false,
                                      ),
                                child: const Text('Entrar'),
                              ),
                              TextButton(
                                onPressed: locked
                                    ? null
                                    : () => cloud.resetPassword(mail.text),
                                child: const Text('Recuperar contraseña'),
                              ),
                            ],
                          ),
                        ] else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: locked ? null : cloud.signOut,
                              child: const Text('Cerrar sesión'),
                            ),
                          ),
                        const Divider(height: 30),
                        const Text(
                          'PROGRESO EN LA NUBE',
                          style: TextStyle(letterSpacing: 1),
                        ),
                        Text(
                          cloud.summary == null
                              ? 'Aún no hay partida guardada en esta cuenta.'
                              : 'Partida remota: nivel ${cloud.summary!['level']} · revisión ${cloud.summary!['revision']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const Text(
                          'Tras subir o restaurar, sincronización automática cada minuto mientras juegas. Si otro dispositivo avanzó, se detiene para que elijas qué conservar.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: locked || current == null
                                  ? null
                                  : () async {
                                      if (cloud.summary != null &&
                                          !await confirm(
                                            '¿Sustituir la nube?',
                                            'Se guardará el progreso de este dispositivo sobre la partida de la cuenta.',
                                          )) {
                                        return;
                                      }
                                      final ok = await cloud.upload(
                                        current!,
                                        replace: true,
                                      );
                                      if (mounted) {
                                        setState(
                                          () => message = ok
                                              ? 'Partida subida. Sincronización automática activada.'
                                              : null,
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Subir partida'),
                            ),
                            OutlinedButton.icon(
                              onPressed: locked || cloud.summary == null
                                  ? null
                                  : () async {
                                      if (!await confirm(
                                        '¿Restaurar desde la nube?',
                                        'La partida de la cuenta sustituirá la partida local de este dispositivo.',
                                      )) {
                                        return;
                                      }
                                      final game = await cloud.download();
                                      if (game != null) {
                                        await widget.onRestore(game);
                                        if (mounted) {
                                          setState(() {
                                            current = game;
                                            message = 'Progreso restaurado en el dispositivo.';
                                          });
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('Restaurar partida'),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        const Text(
                          'EXPEDICIÓN COOPERATIVA · 2 JUGADORES',
                          style: TextStyle(letterSpacing: 1, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Comparte el código con tu compañero. Se explora el mundo del anfitrión; ambos conservan equipo y recompensas. El anfitrión dirige los viajes. Los paneles pausan a todo el grupo.',
                          style: TextStyle(fontSize: 12),
                        ),
                        TextField(
                          controller: name,
                          maxLength: 20,
                          decoration: const InputDecoration(
                            labelText: 'Nombre en la expedición',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: locked ? null : () => play(true),
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Crear sala cooperativa'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: code,
                          maxLength: 6,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Código de sala',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: locked ? null : () => play(false),
                          icon: const Icon(Icons.login),
                          label: const Text('Unirse a la sala'),
                        ),
                      ],
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            message!,
                            style: const TextStyle(color: Color(0xffdfbd84)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
