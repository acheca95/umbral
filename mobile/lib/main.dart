import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'save_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xff10191c),
      statusBarIconBrightness: Brightness.light,
    ),
  );
  final store = SaveStore(await SharedPreferences.getInstance());
  runApp(UmbralApp(store: store));
}
