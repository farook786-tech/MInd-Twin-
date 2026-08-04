import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const FirebaseOptions _options = FirebaseOptions(
    apiKey: 'AIzaSyAI9CJ8CRd85luatnuoUVvBtvXKO1CHdTQ',
    appId: '1:1060019659721:web:29d85a408b17681c89fe18',
    messagingSenderId: '1060019659721',
    projectId: 'mindtwin-60879',
    authDomain: 'mindtwin-60879.firebaseapp.com',
    storageBucket: 'mindtwin-60879.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform => _options;
}