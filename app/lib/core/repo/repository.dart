/// 仓库层：UI 与 Drift/领域计算之间的桥。所有业务写入都走这里（保证 uuid/时间戳/联动正确）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/connection.dart';
import '../db/database.dart';
import '../domain/calc.dart';
import '../domain/food_search.dart';
import '../domain/set_parser.dart';

class MealEntry {
  final Meal meal;
  final List<MealItem> items;
  const MealEntry(this.meal, this.items);
}

class WorkoutEntry {
  final Workout workout;
  final List<WorkoutSet> sets;
  const WorkoutEntry(this.workout, this.sets);
}

class Repo {
  final AppDatabase db;
  Repo(this.db);

  String _now() => DateTime.now().toUtc().toIso8601String().split('.').first;

  String _uuid() => DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  // ------------------------------------------------------- profile

  Future<ProfileData?> watchOnceProfile() =>
      (db.select(db.profile)..where((p) => p.id.equals(1))).getSingleOrNull();

  Stream<ProfileData?> watchProfile() => (db.select(db.profile)
        ..where((p) => p.id.equals(1)))
      .watchSingleOrNull();

  Future<void> saveProfile({
    required String sex,
    double? heightCm,
    required String activityLevel,
    required String goalType,
  }) async {
    final now = _now();
    await db.into(db.profile).insertOnConflictUpdate(
          ProfileCompanion.insert(
            id: Value(1),
            sex: Value(sex),
            heightCm: Value(heightCm),
            activityLevel: Value(activityLevel),
            goalType: Value(goalType),
            updatedAt: now,
          ),
        );
  }

  // ------------------------------------------------------- 体重

  Stream<List<BodyMetric>> watchMetrics() => (db.select(db.bodyMetrics)
        ..where((m) => m.deleted.equals(false))
        ..orderBy([(m) => OrderingTerm.desc(m.date)]))
      .watch();

  Future<void> addWeight(double kg, double? bodyFat, {String? date}) async {
    final now = _now();
    final d = date ?? DateTime.now().toLocal().toIso8601String().split(' ').first;
    await db.into(db.bodyMetrics).insertOnConflictUpdate(
          BodyMetricsCompanion.insert(
            uuid: _uuid(),
            date: d,
            weightKg: Value(kg),
            bodyFatPct: Value(bodyFat),
            updatedAt: now,
          ),
        );
  }

  // ------------------------------------------------------- 围度

  Future<void> addMeasurements(String date, Map<String, double> values) async {
    final now = _now();
    for (final entry in values.entries) {
      await db.into(db.measurements).insertOnConflictUpdate(
            MeasurementsCompanion.insert(
              uuid: _uuid(),
              date: date,
              site: entry.key,
              valueCm: entry.value,
              updatedAt: now,
            ),
          );
    }
  }

  Stream<List<Measurement>> watchMeasurements() => (db.select(db.measurements)
        ..where((m) => m.deleted.equals(false))
        ..orderBy([(m) => OrderingTerm.asc(m.date)]))
      .watch();

  // ------------------------------------------------------- 目标

  Stream<List<Goal>> watchGoals() => (db.select(db.goals)
        ..where((g) => g.deleted.equals(false))
        ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
      .watch();

  Future<void> addGoal(String kind, double target, {String? date}) async {
    final now = _now();
    final unit = kind == 'weight' || kind == 'muscle'
        ? 'kg'
        : kind == 'body_fat'
            ? '%'
            : 'cm';
    await db.into(db.goals).insert(GoalsCompanion.insert(
          uuid: _uuid(),
          kind: kind,
          targetValue: target,
          unit: Value(unit),
          targetDate: Value(date),
          baselineValue: Value(await _currentValueForKind(kind)),
          createdAt: now,
          updatedAt: now,
        ));
  }

  Future<double?> _currentValueForKind(String kind) async {
    if (kind == 'weight') {
      final row = await (db.select(db.bodyMetrics)
            ..where((m) => m.deleted.equals(false) & m.weightKg.isNull().not())
            ..orderBy([(m) => OrderingTerm.desc(m.date)]))
          .getSingleOrNull();
      return row?.weightKg;
    }
    if (kind == 'body_fat') {
      final row = await (db.select(db.bodyMetrics)
            ..where((m) => m.deleted.equals(false) & m.bodyFatPct.isNull().not())
            ..orderBy([(m) => OrderingTerm.desc(m.date)]))
          .getSingleOrNull();
      return row?.bodyFatPct;
    }
    if (kind == 'muscle') {
      final row = await (db.select(db.bodyMetrics)
            ..where((m) =>
                m.deleted.equals(false) & m.skeletalMuscleKg.isNull().not())
            ..orderBy([(m) => OrderingTerm.desc(m.date)]))
          .getSingleOrNull();
      return row?.skeletalMuscleKg;
    }
    if (kind.startsWith('measure:')) {
      final site = kind.split(':')[1];
      final row = await (db.select(db.measurements)
            ..where((m) => m.site.equals(site) & m.deleted.equals(false))
            ..orderBy([(m) => OrderingTerm.desc(m.date)]))
          .getSingleOrNull();
      return row?.valueCm;
    }
    if (kind.startsWith('strength:')) {
      final lift = kind.split(':')[1];
      final row = await (db.select(db.strengthLogs)
            ..where((l) => l.lift.equals(lift) & l.deleted.equals(false))
            ..orderBy([(l) => OrderingTerm.desc(l.estimated1rm)]))
          .getSingleOrNull();
      return row?.estimated1rm;
    }
    return null;
  }

  // ------------------------------------------------------- 力量

  Stream<List<StrengthLog>> watchStrengthLogs() => (db.select(db.strengthLogs)
        ..where((l) => l.deleted.equals(false))
        ..orderBy([(l) => OrderingTerm.desc(l.date)]))
      .watch();

  Future<({double estimated1rm, bool isPr})> addStrength(
      String lift, double weight, int reps,
      {double? rpe, String? date}) async {
    final now = _now();
    final d = date ?? DateTime.now().toLocal().toIso8601String().split(' ').first;
    final estimated = estimate1rm(weight, reps);
    final prev = await (db.select(db.strengthLogs)
          ..where((l) => l.lift.equals(lift) & l.deleted.equals(false))
          ..orderBy([(l) => OrderingTerm.desc(l.estimated1rm)]))
        .getSingleOrNull();
    final isPr = prev == null || estimated > prev.estimated1rm;
    await db.into(db.strengthLogs).insert(StrengthLogsCompanion.insert(
          uuid: _uuid(),
          date: d,
          lift: lift,
          weightKg: weight,
          reps: reps,
          rpe: Value(rpe),
          estimated1rm: estimated,
          note: const Value(null),
          updatedAt: now,
        ));
    return (estimated1rm: estimated, isPr: isPr);
  }

  /// 每个动作按日期取当日最佳估算 1RM（与 Python progress_series 一致）。
  Future<List<({String lift, List<(String, double)> points})>>
      strengthSeries() async {
    final rows = await (db.select(db.strengthLogs)
          ..where((l) => l.deleted.equals(false))
          ..orderBy([(l) => OrderingTerm.asc(l.date)]))
        .get();
    final byLift = <String, Map<String, double>>{};
    for (final r in rows) {
      final day = byLift.putIfAbsent(r.lift, () => {});
      final cur = day[r.date];
      if (cur == null || r.estimated1rm > cur) day[r.date] = r.estimated1rm;
    }
    return byLift.entries
        .map((e) => (
              lift: e.key,
              points: e.value.entries.map((x) => (x.key, x.value)).toList()
            ))
        .toList();
  }

  // ------------------------------------------------------- 食物 / 饮食

  List<Map<String, Object?>>? _foodsCache;

  Future<List<Map<String, Object?>>> _allFoods() async {
    final cached = _foodsCache;
    if (cached != null) return cached;
    final rows = await db.select(db.foods).get();
    final mapped = rows
        .map((r) => <String, Object?>{
              'key': r.name,
              'foodCode': r.code,
              'name': r.name,
              'nameEn': r.nameEn,
              'category': r.category,
              'kcal': r.kcal,
              'protein': r.protein,
              'fat': r.fat,
              'carbs': r.carbs,
              'fiber': r.fiber,
              'gi': r.gi,
            })
        .toList();
    _foodsCache = mapped;
    return mapped;
  }

  Future<List<FoodHit>> searchFoods(String query) async =>
      scoreFoods(await _allFoods(), query);

  Future<MealEntry> addMeal({
    required String mealType,
    required String date,
    required List<(FoodHit, double)> dbItems,
    required List<Map<String, Object?>> customItems,
    String? note,
  }) async {
    final now = _now();
    final mealUuid = _uuid();
    await db.into(db.meals).insert(MealsCompanion.insert(
          uuid: mealUuid,
          date: date,
          mealType: mealType,
          note: Value(note),
          createdAt: now,
          updatedAt: now,
        ));
    for (final (food, grams) in dbItems) {
      final m = scaleMacros(food, grams);
      await db.into(db.mealItems).insert(MealItemsCompanion.insert(
            uuid: _uuid(),
            mealUuid: mealUuid,
            foodName: food.name,
            grams: grams,
            kcal: m['kcal']!,
            protein: m['protein']!,
            fat: m['fat']!,
            carbs: m['carbs']!,
            fiber: Value(m['fiber']),
            source: const Value('db'),
            updatedAt: now,
          ));
    }
    for (final c in customItems) {
      await db.into(db.mealItems).insert(MealItemsCompanion.insert(
            uuid: _uuid(),
            mealUuid: mealUuid,
            foodName: c['name'] as String,
            grams: c['grams'] as double,
            kcal: c['kcal'] as double,
            protein: c['protein'] as double,
            fat: c['fat'] as double,
            carbs: c['carbs'] as double,
            fiber: Value((c['fiber'] ?? 0.0) as double),
            source: const Value('manual'),
            updatedAt: now,
          ));
    }
    final items = await (db.select(db.mealItems)
          ..where((i) => i.mealUuid.equals(mealUuid)))
        .get();
    return MealEntry(
      Meal(
        uuid: mealUuid,
        date: date,
        mealType: mealType,
        note: note,
        createdAt: now,
        updatedAt: now,
        deleted: false,
      ),
      items,
    );
  }

  Future<void> deleteMeal(String mealUuid) async {
    final now = _now();
    await (db.update(db.meals)..where((m) => m.uuid.equals(mealUuid))).write(
        MealsCompanion(
            deleted: const Value(true), updatedAt: Value(now)));
    await (db.update(db.mealItems)..where((i) => i.mealUuid.equals(mealUuid)))
        .write(MealItemsCompanion(
            deleted: const Value(true), updatedAt: Value(now)));
  }

  Stream<List<MealEntry>> watchMeals(String date) {
    final query = (db.select(db.meals)
          ..where((m) => m.date.equals(date) & m.deleted.equals(false))
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .watch();
    return query.asyncMap((meals) async {
      final entries = <MealEntry>[];
      for (final m in meals) {
        final items = await (db.select(db.mealItems)
              ..where(
                  (i) => i.mealUuid.equals(m.uuid) & i.deleted.equals(false)))
            .get();
        entries.add(MealEntry(m, items));
      }
      return entries;
    });
  }

  /// 近 N 天全部餐次（复盘用）。
  Stream<List<MealEntry>> watchAllMeals({int days = 30}) {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .split('T')
        .first;
    return (db.select(db.meals)
          ..where((m) =>
              m.deleted.equals(false) & m.date.isBiggerOrEqualValue(cutoff))
          ..orderBy([(m) => OrderingTerm.asc(m.date)]))
        .watch()
        .asyncMap((meals) async {
      final entries = <MealEntry>[];
      for (final m in meals) {
        final items = await (db.select(db.mealItems)
              ..where(
                  (i) => i.mealUuid.equals(m.uuid) & i.deleted.equals(false)))
            .get();
        entries.add(MealEntry(m, items));
      }
      return entries;
    });
  }

  // ------------------------------------------------------- 训练

  Future<List<Exercise>> allExercises() => db.select(db.exercises).get();

  /// 动作解析：中文别名关键词 → 英文子串匹配 → 最长名优先。
  Future<Exercise?> resolveExercise(String query) async {
    final all = await allExercises();
    final ql = query.trim().toLowerCase();
    for (final e in all) {
      if (e.id.toLowerCase() == ql || e.name.toLowerCase() == ql) return e;
    }
    final keywords = zhAliases[query] ?? zhAliases[query.toLowerCase()];
    if (keywords != null) {
      for (final kw in keywords) {
        final k = kw.toLowerCase();
        final hits =
            all.where((e) => e.name.toLowerCase().contains(k)).toList()
              ..sort((a, b) => a.name.length.compareTo(b.name.length));
        if (hits.isNotEmpty) return hits.first;
      }
    }
    final contains =
        all.where((e) => e.name.toLowerCase().contains(ql)).toList()
          ..sort((a, b) => a.name.length.compareTo(b.name.length));
    if (contains.isNotEmpty) return contains.first;
    return null;
  }

  Future<WorkoutEntry> addWorkout({
    required String date,
    required List<ParsedSet> sets,
    String? name,
    String? note,
  }) async {
    final now = _now();
    final workoutUuid = _uuid();
    await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          uuid: workoutUuid,
          date: date,
          name: Value(name),
          note: Value(note),
          createdAt: now,
          updatedAt: now,
        ));
    final counters = <String, int>{};
    for (final s in sets) {
      final ex = await resolveExercise(s.name);
      counters[s.name] = (counters[s.name] ?? 0) + 1;
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
            uuid: _uuid(),
            workoutUuid: workoutUuid,
            exerciseName: ex?.name ?? s.name,
            setNo: Value(counters[s.name]),
            weightKg: Value(s.weightKg),
            reps: Value(s.reps),
            rpe: Value(s.rpe),
            updatedAt: now,
          ));
    }
    return _loadWorkout(workoutUuid);
  }

  Future<WorkoutEntry> _loadWorkout(String workoutUuid) async {
    final w = await (db.select(db.workouts)
          ..where((x) => x.uuid.equals(workoutUuid)))
        .getSingle();
    final sets = await (db.select(db.workoutSets)
          ..where((s) => s.workoutUuid.equals(workoutUuid) & s.deleted.equals(false)))
        .get();
    return WorkoutEntry(w, sets);
  }

  Stream<List<WorkoutEntry>> watchWorkouts({int days = 365}) {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .split('T')
        .first;
    return (db.select(db.workouts)
          ..where((w) =>
              w.deleted.equals(false) & w.date.isBiggerOrEqualValue(cutoff))
          ..orderBy([(w) => OrderingTerm.desc(w.date)]))
        .watch()
        .asyncMap((workouts) async {
      final out = <WorkoutEntry>[];
      for (final w in workouts) {
        final sets = await (db.select(db.workoutSets)
              ..where((s) =>
                  s.workoutUuid.equals(w.uuid) & s.deleted.equals(false)))
            .get();
        out.add(WorkoutEntry(w, sets));
      }
      return out;
    });
  }
}

/// JSON 辅助（stepsZh 等列的解码）。
List<String> decodeList(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    return (jsonDecode(json) as List).cast<String>();
  } catch (_) {
    return const [];
  }
}
