import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import 'database.dart';

/// Web 平台：drift wasm，引擎文件与应用同源自托管（web/sqlite3.wasm + web/drift_worker.js），
/// 避免 CDN 的 CORS 问题，也支持完全离线使用。
AppDatabase openDatabase() {
  return AppDatabase(LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'fitfuel',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  }));
}
