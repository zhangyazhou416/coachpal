/// 趋势页：体重/体脂折线 + 围度迷你图 + 周复盘卡。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/connection.dart';
import '../../core/db/database.dart';
import '../../core/repo/repository.dart';
import '../../core/theme/palette.dart';
import '../../main.dart';
import '../workout/workout_page.dart' show workoutsProvider;

class TrendsPage extends ConsumerWidget {
  const TrendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(metricsListProvider).value ?? const [];
    final measurements = ref.watch(measurementsListProvider).value ?? const [];
    final weightPoints = metrics
        .where((m) => m.weightKg != null)
        .map((m) => (m.date, m.weightKg!))
        .toList();
    final fatPoints = metrics
        .where((m) => m.bodyFatPct != null)
        .map((m) => (m.date, m.bodyFatPct!))
        .toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LineCard(
            title: '体重 (kg)',
            points: weightPoints,
            color: AppPalette.series1,
            empty: '记录体重后显示趋势',
          ),
          const SizedBox(height: 12),
          _LineCard(
            title: '体脂率 (%)',
            points: fatPoints,
            color: AppPalette.series2,
            empty: '记录体脂率后显示趋势',
          ),
          const SizedBox(height: 12),
          _MeasurementChips(measurements: measurements),
          const SizedBox(height: 12),
          const _WeeklyReportCard(),
        ],
      ),
    );
  }
}

final metricsListProvider = StreamProvider<List<BodyMetric>>((ref) {
  final repo = ref.read(repoProvider);
  return repo.watchMetrics();
});

final measurementsListProvider = StreamProvider<List<Measurement>>((ref) {
  final repo = ref.read(repoProvider);
  return repo.watchMeasurements();
});

class _LineCard extends StatelessWidget {
  final String title;
  final List<(String, double)> points;
  final Color color;
  final String empty;
  const _LineCard(
      {required this.title, required this.points, required this.color, required this.empty});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: points.length < 2
                  ? Center(child: Text(empty, style: const TextStyle(color: Colors.grey)))
                  : LineChart(LineChartData(
                      gridData: FlGridData(drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval:
                                (points.length / 4).ceilToDouble().clamp(1.0, 999.0),
                            getTitlesWidget: (v, _) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= points.length) {
                                return const SizedBox();
                              }
                              final d = points[idx].$1.split('-').last;
                              return Text(d, style: const TextStyle(fontSize: 10));
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < points.length; i++)
                              FlSpot(i.toDouble(), points[i].$2),
                          ],
                          isCurved: points.length > 2,
                          barWidth: 2,
                          dotData: FlDotData(
                            show: points.length <= 30,
                            getDotPainter: (spot, _, __, ___) =>
                                FlDotCirclePainter(radius: 3, color: color),
                          ),
                          color: color,
                        ),
                      ],
                    )),
            ),
            if (points.length >= 2)
              Text(
                '${points.first.$1} ${points.first.$2.toStringAsFixed(1)} → '
                '${points.last.$1} ${points.last.$2.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _MeasurementChips extends StatefulWidget {
  final List<Measurement> measurements;
  const _MeasurementChips({required this.measurements});

  @override
  State<_MeasurementChips> createState() => _MeasurementChipsState();
}

class _MeasurementChipsState extends State<_MeasurementChips> {
  String _site = 'waist';

  static const siteLabels = <String, String>{
    'chest': '胸围', 'waist': '腰围', 'hip': '臀围', 'neck': '颈围',
    'shoulder': '肩围', 'arm': '上臂围', 'forearm': '前臂围',
    'thigh': '大腿围', 'calf': '小腿围', 'wrist': '腕围',
  };

  @override
  Widget build(BuildContext context) {
    final bySite = <String, List<(String, double)>>{};
    for (final m in widget.measurements) {
      bySite.putIfAbsent(m.site, () => []).add((m.date, m.valueCm));
    }
    final points = bySite[_site] ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final site in bySite.keys)
                  ChoiceChip(
                    label: Text(siteLabels[site] ?? site),
                    selected: site == _site,
                    onSelected: (_) => setState(() => _site = site),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _LineCard(
              title: '${siteLabels[_site] ?? _site} (cm)',
              points: points,
              color: AppPalette.series3,
              empty: '记录围度后显示趋势',
            ),
          ],
        ),
      ),
    );
  }
}

/// 周复盘卡：最近 7 天的饮食均值 / 训练量 / 体重变化。
class _WeeklyReportCard extends ConsumerWidget {
  const _WeeklyReportCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealsProvider).value ?? const [];
    final workouts = ref.watch(workoutsProvider).value ?? const [];
    final metrics = ref.watch(metricsListProvider).value ?? const [];

    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final dayTotals = <String, double>{};
    for (final entry in meals) {
      if (entry.meal.deleted) continue;
      final kcal = entry.items.fold<double>(0, (a, i) => a + i.kcal);
      dayTotals[entry.meal.date] = (dayTotals[entry.meal.date] ?? 0) + kcal;
    }
    final recent = dayTotals.entries
        .where((e) => DateTime.parse(e.key).isAfter(cutoff))
        .toList();
    final avgKcal = recent.isEmpty
        ? null
        : recent.fold<double>(0, (a, e) => a + e.value) / recent.length;

    final weekWorkouts = workouts
        .where((w) => DateTime.parse(w.workout.date).isAfter(cutoff))
        .toList();
    final weekVolume = weekWorkouts.fold<double>(
        0, (a, w) => a + w.sets.fold<double>(0, (b, s) => b + (s.weightKg ?? 0) * (s.reps ?? 0)));

    final weights = metrics.where((m) => m.weightKg != null).toList();
    String? weightLine;
    if (weights.length >= 2) {
      final delta = weights.first.weightKg! - weights.last.weightKg!;
      weightLine = '${weights.last.weightKg!.toStringAsFixed(1)} → '
          '${weights.first.weightKg!.toStringAsFixed(1)} kg（${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}）';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('近 7 天复盘', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '饮食：${recent.isEmpty ? "无记录" : "记录 ${recent.length} 天 · 日均 ${avgKcal!.toStringAsFixed(0)} kcal"}\n'
              '训练：${weekWorkouts.length} 次 · 总训练量 ${weekVolume.toStringAsFixed(0)} kg\n'
              '体重：${weightLine ?? "记录两次后显示变化"}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

final mealsProvider = StreamProvider((ref) {
  final repo = ref.read(repoProvider);
  return repo.watchAllMeals(days: 30);
});
