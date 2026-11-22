import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import 'database.dart';

/// Web 平台：drift wasm（官方 CDN 托管 worker；生产可自托管到应用同源）。
AppDatabase openDatabase() {
  return AppDatabase(LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'fitfuel',
      sqlite3Uri: Uri.parse('https://drift.simonbinder.eu/sqlite3.wasm'),
      driftWorkerUri: Uri.parse('https://drift.simonbinder.eu/drift_worker.js'),
    );
    return result.resolvedExecutor;
  }));
}
