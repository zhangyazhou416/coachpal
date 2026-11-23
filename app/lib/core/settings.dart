/// 应用设置：服务器地址与认证 token（SharedPreferences）。
library;

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _kServerUrl = 'server_url';
  static const _kToken = 'auth_token';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> serverUrl() async =>
      (await _prefs).getString(_kServerUrl);

  Future<String?> token() async => (await _prefs).getString(_kToken);

  Future<void> setServerUrl(String url) async =>
      (await _prefs).setString(_kServerUrl, url);

  Future<void> setToken(String? token) async {
    final p = await _prefs;
    if (token == null || token.isEmpty) {
      await p.remove(_kToken);
    } else {
      await p.setString(_kToken, token);
    }
  }

  /// 已完整配置（有地址且已登录）
  Future<bool> isConfigured() async {
    final url = await serverUrl();
    final t = await token();
    return url != null && url.isNotEmpty && t != null && t.isNotEmpty;
  }
}
