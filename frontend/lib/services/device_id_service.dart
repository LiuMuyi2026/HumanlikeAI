import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/constants.dart';

// On web, also persist via cookie so it survives port changes
import 'device_id_web.dart' if (dart.library.io) 'device_id_stub.dart'
    as platform;

class DeviceIdService {
  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Check SharedPreferences (primary storage)
    final existing = prefs.getString(AppConstants.deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      // Also sync to cookie on web
      if (kIsWeb) platform.saveCookie(existing);
      return existing;
    }

    // 2. On web, try to recover from cookie (survives port changes)
    if (kIsWeb) {
      final fromCookie = platform.readCookie();
      if (fromCookie != null && fromCookie.isNotEmpty) {
        await prefs.setString(AppConstants.deviceIdKey, fromCookie);
        return fromCookie;
      }
    }

    // 3. Generate new ID
    final newId = const Uuid().v4();
    await prefs.setString(AppConstants.deviceIdKey, newId);
    if (kIsWeb) platform.saveCookie(newId);
    return newId;
  }
}
