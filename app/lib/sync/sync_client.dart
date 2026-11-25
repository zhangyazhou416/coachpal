/// 同步客户端：登录、pull（LWW 应用）、push（本地变更）。
///
/// 同步协议见 docs/CROSS_PLATFORM_PLAN.md：
/// - 每行 uuid + updated_at(UTC) + deleted 墓碑
/// - push 服务端 LWW（旧 updated_at 跳过）
/// - pull 应用变更与墓碑
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class SyncConfig {
  final String baseUrl; // 例如 https://coachpal.example.com
  final String? token;
  const SyncConfig(this.baseUrl, {this.token});
}

class SyncResult {
  final bool ok;
  final String? error;
  const SyncResult(this.ok, {this.error});
}

class SyncClient {
  final SyncConfig config;
  final http.Client _http = http.Client();

  SyncClient(this.config);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (config.token != null) 'Authorization': 'Bearer ${config.token}',
      };

  Future<({String? token, String? error})> login(String password) async {
    final r = await _http.post(
      Uri.parse('${config.baseUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) {
      return (token: null, error: '登录失败 HTTP ${r.statusCode}');
    }
    return (token: jsonDecode(r.body)['token'] as String, error: null);
  }

  /// 拉取变更。onRow 由调用方按表分发写入本地（本地更旧才覆盖 = LWW）。
  Future<SyncResult> pull(
    String since,
    Future<void> Function(String table, List<dynamic> rows) onTable,
  ) async {
    final r = await _http.post(
      Uri.parse('${config.baseUrl}/api/sync/pull'),
      headers: _headers,
      body: jsonEncode({'since': since}),
    );
    if (r.statusCode != 200) return SyncResult(false, error: 'HTTP ${r.statusCode}');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final tombstones = (data['_tombstones'] as List?) ?? const [];
    for (final row in tombstones) {
      await onTable('_tombstone', row);
    }
    for (final entry in data.entries) {
      if (entry.key.startsWith('_')) continue;
      await onTable(entry.key, entry.value as List);
    }
    return SyncResult(true);
  }

  /// 推送本地变更行。
  Future<SyncResult> push(Map<String, List<Map<String, dynamic>>> rows) async {
    if (rows.values.every((l) => l.isEmpty)) return SyncResult(true);
    final r = await _http.post(
      Uri.parse('${config.baseUrl}/api/sync/push'),
      headers: _headers,
      body: jsonEncode({'rows': rows}),
    );
    if (r.statusCode != 200) return SyncResult(false, error: 'HTTP ${r.statusCode}');
    return SyncResult(true);
  }
}
