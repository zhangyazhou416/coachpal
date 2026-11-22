/// Drift 本地库：与 server schema 同构（uuid/updated_at/deleted 支持同步）。
///
/// 代码生成：`dart run build_runner build --delete-conflicting-outputs`
library;

import 'package:drift/drift.dart';

part 'database.g.dart';

class Profile extends Table {
  IntColumn get id => integer()();
  TextColumn get sex => text().withDefault(const Constant('male'))();
  TextColumn get birthDate => text().nullable()();
  RealColumn get heightCm => real().nullable()();
  TextColumn get activityLevel => text().withDefault(const Constant('moderate'))();
  TextColumn get goalType => text().withDefault(const Constant('maintain'))();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class BodyMetrics extends Table {
  TextColumn get uuid => text()();            // 同步主键
  TextColumn get date => text().unique()();   // YYYY-MM-DD
  RealColumn get weightKg => real().nullable()();
  RealColumn get bodyFatPct => real().nullable()();
  RealColumn get skeletalMuscleKg => real().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class Measurements extends Table {
  TextColumn get uuid => text()();
  TextColumn get date => text()();
  TextColumn get site => text()();            // chest/waist/...
  RealColumn get valueCm => real()();
  TextColumn get note => text().nullable()();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
  @override
  List<Set<Column>> get uniqueKeys => [{date, site}];
}

class Goals extends Table {
  TextColumn get uuid => text()();
  TextColumn get kind => text()();            // weight/body_fat/muscle/measure:x/strength:x
  RealColumn get targetValue => real()();
  TextColumn get unit => text().nullable()();
  RealColumn get baselineValue => real().nullable()();
  TextColumn get targetDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class StrengthLogs extends Table {
  TextColumn get uuid => text()();
  TextColumn get date => text()();
  TextColumn get lift => text()();
  RealColumn get weightKg => real()();
  IntColumn get reps => integer()();
  RealColumn get rpe => real().nullable()();
  RealColumn get estimated1rm => real()();
  TextColumn get note => text().nullable()();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class Meals extends Table {
  TextColumn get uuid => text()();
  TextColumn get date => text()();
  TextColumn get mealType => text()();        // breakfast/lunch/dinner/snack
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class MealItems extends Table {
  TextColumn get uuid => text()();
  TextColumn get mealUuid => text()();        // 引用 Meals.uuid
  IntColumn get foodId => integer().nullable()();
  TextColumn get foodName => text()();
  RealColumn get grams => real()();
  RealColumn get kcal => real()();
  RealColumn get protein => real()();
  RealColumn get fat => real()();
  RealColumn get carbs => real()();
  RealColumn get fiber => real().nullable()();
  TextColumn get source => text().withDefault(const Constant('db'))();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class Workouts extends Table {
  TextColumn get uuid => text()();
  TextColumn get date => text()();
  TextColumn get name => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class WorkoutSets extends Table {
  TextColumn get uuid => text()();
  TextColumn get workoutUuid => text()();     // 引用 Workouts.uuid
  IntColumn get exerciseId => integer().nullable()();
  TextColumn get exerciseName => text()();
  IntColumn get setNo => integer().nullable()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();
  RealColumn get rpe => real().nullable()();
  TextColumn get updatedAt => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

/// 参考数据（不同步）：食物库
class Foods extends Table {
  TextColumn get code => text().nullable()();
  TextColumn get name => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get category => text().nullable()();
  RealColumn get kcal => real().nullable()();
  RealColumn get protein => real().nullable()();
  RealColumn get fat => real().nullable()();
  RealColumn get carbs => real().nullable()();
  RealColumn get fiber => real().nullable()();
  RealColumn get gi => real().nullable()();

  @override
  Set<Column> get primaryKey => {name};
}

/// 参考数据（不同步）：动作库
class Exercises extends Table {
  TextColumn get id => text()();              // gd_XXXX
  TextColumn get name => text()();
  TextColumn get cat => text().nullable()();
  TextColumn get equip => text().nullable()();
  TextColumn get target => text().nullable()();
  TextColumn get secondary => text().nullable()();  // JSON 数组
  TextColumn get stepsEn => text().nullable()();    // JSON 数组
  TextColumn get stepsZh => text().nullable()();    // JSON 数组
  TextColumn get gifPath => text().nullable()();    // 服务器相对路径 videos/xxx.gif
  TextColumn get thumbPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 同步游标
class SyncState extends Table {
  TextColumn get table_ => text()();
  TextColumn get lastPull => text()();

  @override
  Set<Column> get primaryKey => {table_};
}

@DriftDatabase(
  tables: [
    Profile,
    BodyMetrics,
    Measurements,
    Goals,
    StrengthLogs,
    Meals,
    MealItems,
    Workouts,
    WorkoutSets,
    Foods,
    Exercises,
    SyncState,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.connection);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) => m.createAll());
}
