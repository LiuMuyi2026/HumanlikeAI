import 'package:web/web.dart' as web;

const _cookieName = 'hlai_device_id';

void saveCookie(String deviceId) {
  // Set cookie with 10-year expiry, accessible across all ports on localhost
  web.document.cookie =
      '$_cookieName=$deviceId; path=/; max-age=315360000; SameSite=Lax';
}

String? readCookie() {
  final cookies = web.document.cookie;
  if (cookies.isEmpty) return null;
  for (final part in cookies.split('; ')) {
    if (part.startsWith('$_cookieName=')) {
      return part.substring('$_cookieName='.length);
    }
  }
  return null;
}
