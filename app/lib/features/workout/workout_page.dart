/// 训练记录：组规格解析（别名）+ 保存 + 最近训练与 PR。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/set_parser.dart';
import '../../main.dart';
import '../meal/meal_page.dart' show todayIso;

class WorkoutPage extends ConsumerStatefulWidget {
  const WorkoutPage({super.key});

  @override
  ConsumerState<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends ConsumerState<WorkoutPage> {
  final _spec = TextEditingController();
  final _name = TextEditingController();
  final _pending = <ParsedSet>[];

  @override
  void dispose() {
    _spec.dispose();
    _name.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _addSet() async {
    final parsed = parseSetSpec(_spec.text);
    if (parsed == null) {
      _snack('格式：动作名 重量 次数 [@RPE]，例如 卧推 80 5 @8');
      return;
    }
    // 别名是否能在库里解析到（提示但不阻塞；解析不到按自定义名记录）
    final repo = ref.read(repoProvider);
    final ex = await repo.resolveExercise(parsed.name);
    setState(() {
      _pending.add(parsed);
      _spec.clear();
    });
    if (ex == null) _snack('「${parsed.name}」不在动作库，按自定义动作记录');
  }

  Future<void> _save() async {
    if (_pending.isEmpty) {
      _snack('先添加训练组');
      return;
    }
    final repo = ref.read(repoProvider);
    final w = await repo.addWorkout(
      date: todayIso(),
      sets: _pending,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
    );
    final volume = w.sets.fold<double>(
        0, (a, s) => a + (s.weightKg ?? 0) * (s.reps ?? 0));
    setState(() => _pending.clear());
    _snack('已记录 ${w.sets.length} 组 · 总训练量 ${volume.toStringAsFixed(0)} kg');
  }

  @override
  Widget build(BuildContext context) {
    final workouts = ref.watch(workoutsProvider).value ?? const [];
    final prs = ref.watch(prsProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '训练名称（可选，如：推日）'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _spec,
                      decoration: const InputDecoration(
                        labelText: '组规格',
                        hintText: '卧推 80 5 @8',
                      ),
                      onSubmitted: (_) => _addSet(),
                    ),
                  ),
                  IconButton(onPressed: _addSet, icon: const Icon(Icons.add)),
                ]),
                for (final s in _pending)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.fitness_center, size: 18),
                    title: Text(
                        '${s.name} ${s.weightKg.toStringAsFixed(s.weightKg % 1 == 0 ? 0 : 1)}kg × ${s.reps}'
                        '${s.rpe == null ? '' : ' @${s.rpe}'}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _pending.remove(s)),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check),
                      label: const Text('保存训练')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (prs.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('力量 PR（估算 1RM）',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final pr in prs)
                    ListTile(
                      dense: true,
                      title: Text(pr.$1),
                      trailing: Text('${pr.$2.toStringAsFixed(1)} kg'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text('最近训练', style: Theme.of(context).textTheme.titleMedium),
        for (final w in workouts.take(10))
          Card(
            child: ListTile(
              title: Text('${w.workout.date} ${w.workout.name ?? '未命名训练'}'),
              subtitle: Text(w.sets
                  .map((s) =>
                      '${s.exerciseName} ${s.weightKg?.toStringAsFixed(0) ?? 0}×${s.reps ?? 0}')
                  .join('、')),
              trailing: Text(
                  '${w.sets.fold<double>(0, (a, s) => a + (s.weightKg ?? 0) * (s.reps ?? 0)).toStringAsFixed(0)} kg'),
            ),
          ),
        if (workouts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('还没有训练记录')),
          ),
      ],
    );
  }
}

final workoutsProvider = StreamProvider((ref) =>
    ref.read(repoProvider).watchWorkouts());

/// PR：按动作取最大估算 1RM。
final prsProvider = StreamProvider<List<(String, double)>>((ref) {
  final repo = ref.read(repoProvider);
  return repo.watchStrengthLogs().map((logs) {
    final byLift = <String, double>{};
    for (final l in logs) {
      if (l.estimated1rm > (byLift[l.lift] ?? 0)) {
        byLift[l.lift] = l.estimated1rm;
      }
    }
    final list = byLift.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return list;
  });
});
