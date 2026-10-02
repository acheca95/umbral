import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class FirebaseConfig {
  // Public client identifiers. Authorization is enforced by Firestore rules.
  static FirebaseOptions get options => kIsWeb
      ? const FirebaseOptions(
          apiKey: 'AIzaSyBYZshkCJotuezsj1ZhlYspr_GP1DSkeqE',
          appId: '1:36477231534:web:51717ccfc4130c35a0283f',
          messagingSenderId: '36477231534',
          projectId: 'nova-5d1c5',
          authDomain: 'nova-5d1c5.firebaseapp.com',
        )
      : const FirebaseOptions(
          apiKey: 'AIzaSyBCJrGNxDuLTQhYSO97LUuem54ctgD3X7k',
          appId: '1:36477231534:android:8ca5cee49a6534dfa0283f',
          messagingSenderId: '36477231534',
          projectId: 'nova-5d1c5',
        );
}
