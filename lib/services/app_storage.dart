import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

class AppStorage {
  static SharedPreferences? prefs;
  static late final Future<FirebaseApp> firebaseInitFuture;

  static String? get cachedUid {
    final direct = prefs?.getString('cached_user_uid');
    if (direct != null && direct.isNotEmpty) return direct;

    // Backward-compatibility fallback: discover from existing user_<uid>_initialized keys
    final keys = prefs?.getKeys() ?? {};
    for (final key in keys) {
      if (key.startsWith('user_') && key.endsWith('_initialized')) {
        if (prefs?.getBool(key) == true) {
          final extractedUid = key.substring(5, key.length - 12);
          if (extractedUid.isNotEmpty) {
            prefs?.setString('cached_user_uid', extractedUid);
            return extractedUid;
          }
        }
      }
    }
    return null;
  }

  static bool get isReturningUser {
    final uid = cachedUid;
    if (uid == null || uid.isEmpty) return false;
    final isInit = prefs?.getBool('user_${uid}_initialized') ?? false;
    final needsRestore = prefs?.getBool('needs_device_reregistration') ?? false;
    return isInit && !needsRestore;
  }
}
