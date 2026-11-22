/// 今日页：体重 hero 卡 + 每日目标卡。
library;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/connection.dart';
import '../../core/domain/calc.dart';
import '../../core/theme/palette.dart';
import '../../main.dart';

final todayStream = StreamProvider((ref) {
  final db = ref.read(databaseProvider);
  return (db.select(db.bodyMetrics)
        ..where((m) => m.deleted.equals(false))
        ..orderBy([(m) => OrderingTerm.desc(m.date)]))
      .watch();
});

final profileStream = StreamProvider((ref) {
  final db = ref.read(databaseProvider);
  return (db.select(db.profile)..where((p) => p.id.equals(1)))
      .watchSingleOrNull();
});

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(todayStream).value ?? const [];
    final profile = ref.watch(profileStream).value;
    final latest = metrics.isEmpty ? null : metrics.first;
    final targets = computeTargets(
      sex: profile?.sex,
      age: null,
      heightCm: profile?.heightCm,
      weightKg: latest?.weightKg,
      activityLevel: profile?.activityLevel ?? 'moderate',
      goalType: profile?.goalType ?? 'maintain',
    );
    final bmi = calcBmi(latest?.weightKg, profile?.heightCm);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WeightHeroCard(latest: latest, bmi: bmi),
          const SizedBox(height: 12),
          if (targets != null)
            _MacroCard(targets: targets)
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('在「我的」里完善身高后，这里会显示每日热量与宏量目标'),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeightHeroCard extends StatelessWidget {
  final dynamic latest;
  final double? bmi;
  const _WeightHeroCard({this.latest, this.bmi});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWeight = latest?.weightKg != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前体重', style: theme.textTheme.bodySmall),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hasWeight
                      ? latest!.weightKg!.toStringAsFixed(1)
                      : '—',
                  style: theme.textTheme.displayMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('kg', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            Text(
              !hasWeight
                  ? '在「记录 → 身体」里记录第一次体重'
                  : '记录于 ${latest!.date} · BMI ${bmi?.toStringAsFixed(1) ?? '—'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroCard extends StatelessWidget {
  final Targets targets;
  const _MacroCard({required this.targets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      ('热量', targets.kcal, 'kcal', 0),
      ('蛋白质', targets.protein, 'g', 1),
      ('碳水', targets.carbs, 'g', 1),
      ('脂肪', targets.fat, 'g', 1),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('每日目标（BMR ${targets.bmr.toStringAsFixed(0)} · TDEE ${targets.tdee.toStringAsFixed(0)}）',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                        width: 56,
                        child: Text(r.$1, style: theme.textTheme.bodySmall)),
                    Expanded(
                      child: Text(
                        '${r.$2.toStringAsFixed(r.$4)} ${r.$3}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            if (targets.clamped)
              Text('已达安全下限，不建议再降',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppPalette.statusBad)),
          ],
        ),
      ),
    );
  }
}
