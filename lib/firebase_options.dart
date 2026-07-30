import "package:firebase_core/firebase_core.dart" show FirebaseOptions;
import "package:flutter/foundation.dart"
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          "DefaultFirebaseOptions have not been configured for linux.",
        );
      default:
        throw UnsupportedError(
          "DefaultFirebaseOptions are not supported for this platform.",
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyDYZQ2pvTV4BJ10g2VrO0W304g9j_cxafQ",
    appId: "1:12575732319:web:05ad7f28653d55955561ea",
    messagingSenderId: "12575732319",
    projectId: "prox-42bef",
    authDomain: "prox-42bef.firebaseapp.com",
    storageBucket: "prox-42bef.firebasestorage.app",
    measurementId: "G-DX866BZMF9",
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyDFmR-Cijm8vwK-8qEkdgyVNbMsIrZLMr0",
    appId: "1:12575732319:android:c5ec68ebc2de45de5561ea",
    messagingSenderId: "12575732319",
    projectId: "prox-42bef",
    storageBucket: "prox-42bef.firebasestorage.app",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyD5N4rN4BnNOiQoAqxBfuOM_vk_o3vjdWA",
    appId: "1:12575732319:ios:c647ed1f20cde1f45561ea",
    messagingSenderId: "12575732319",
    projectId: "prox-42bef",
    storageBucket: "prox-42bef.firebasestorage.app",
    iosBundleId: "com.prox.app",
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: "AIzaSyCZ9IznIChYN-K_iJNHtI4e_X0YIW0vq0A",
    appId: "1:12575732319:ios:041eca918efc24405561ea",
    messagingSenderId: "12575732319",
    projectId: "prox-42bef",
    storageBucket: "prox-42bef.firebasestorage.app",
    iosBundleId: "com.example.prox",
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: "AIzaSyDYZQ2pvTV4BJ10g2VrO0W304g9j_cxafQ",
    appId: "1:12575732319:web:d62cd46cb72398545561ea",
    messagingSenderId: "12575732319",
    projectId: "prox-42bef",
    authDomain: "prox-42bef.firebaseapp.com",
    storageBucket: "prox-42bef.firebasestorage.app",
    measurementId: "G-KVCVYBD87W",
  );
}
