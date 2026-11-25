import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

AppDatabase openDatabase() {
  return AppDatabase(LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'coachpal.sqlite'));
    return NativeDatabase.createInBackground(file);
  }));
}
