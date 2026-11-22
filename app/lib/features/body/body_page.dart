/// 身体页：体重快捷记录、围度表单、目标管理。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/repo/repository.dart';
import '../../main.dart';
import '../meal/meal_page.dart' show todayIso;

class BodyPage extends ConsumerStatefulWidget {
  const BodyPage({super.key});

  @override
  ConsumerState<BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends ConsumerState<BodyPage> {
  final _weight = TextEditingController();
  final _bodyFat = TextEditingController();
  final _muscle = TextEditingController();
  final _siteControllers = <String, TextEditingController>{};
  String _goalKind = 'weight';
  final _goalTarget = TextEditingController();

  static const sites = <(String, String)>[
    ('chest', '胸围'), ('waist', '腰围'), ('hip', '臀围'), ('neck', '颈围'),
    ('shoulder', '肩围'), ('arm', '上臂围'), ('forearm', '前臂围'),
    ('thigh', '大腿围'), ('calf', '小腿围'), ('wrist', '腕围'),
  ];

  @override
  void dispose() {
    for (final c in [_weight, _bodyFat, _muscle, _goalTarget]) {
      c.dispose();
    }
    for (final c in _siteControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _saveWeight() async {
    final w = double.tryParse(_weight.text);
    if (w == null || w < 20 || w > 400) {
      _snack('体重不合理（20-400 kg）');
      return;
    }
    await ref.read(repoProvider).addWeight(
          w,
          double.tryParse(_bodyFat.text),
        );
    _snack('已记录 $w kg');
    _weight.clear();
    _bodyFat.clear();
    _muscle.clear();
  }

  Future<void> _saveMeasurements() async {
    final values = <String, double>{};
    for (final (site, label) in sites) {
      final v = double.tryParse(_siteControllers[site]?.text ?? '');
      if (v != null) values[site] = v;
    }
    if (values.isEmpty) {
      _snack('至少填一个围度');
      return;
    }
    await ref.read(repoProvider).addMeasurements(todayIso(), values);
    for (final c in _siteControllers.values) {
      c.clear();
    }
    _snack('已记录 ${values.length} 项围度');
  }

  Future<void> _addGoal() async {
    final t = double.tryParse(_goalTarget.text);
    if (t == null) {
      _snack('目标值必须是数字');
      return;
    }
    final kind = _goalKind == 'weight' ||
            _goalKind == 'body_fat' ||
            _goalKind == 'muscle'
        ? _goalKind
        : 'measure:$_goalKind';
    await ref.read(repoProvider).addGoal(kind, t);
    _goalTarget.clear();
    _snack('目标已添加');
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalsProvider).value ?? const [];
    String label(String kind) => kind.startsWith('measure:')
        ? '围度 ${kind.split(':')[1]}'
        : kind.startsWith('strength:')
            ? '${kind.split(':')[1]} 1RM'
            : {'weight': '体重', 'body_fat': '体脂率', 'muscle': '骨骼肌量'}[kind] ?? kind;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('体重 / 体成分', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '体重 kg'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _bodyFat,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '体脂率 %'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _muscle,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '骨骼肌 kg'),
                  )),
                ]),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: _saveWeight, child: const Text('记录')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('今日围度 (cm)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (site, label) in sites)
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _siteControllers.putIfAbsent(
                              site, () => TextEditingController()),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: label),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: _saveMeasurements, child: const Text('记录围度')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('目标', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _goalKind,
                      items: [
                        const DropdownMenuItem(value: 'weight', child: Text('体重 kg')),
                        const DropdownMenuItem(value: 'body_fat', child: Text('体脂率 %')),
                        const DropdownMenuItem(value: 'muscle', child: Text('骨骼肌 kg')),
                        for (final (site, label) in sites)
                          DropdownMenuItem(value: site, child: Text('$label cm')),
                      ],
                      onChanged: (v) => setState(() => _goalKind = v ?? 'weight'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _goalTarget,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '目标值'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: _addGoal,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('添加目标')),
                ),
                for (final g in goals)
                  ListTile(
                    dense: true,
                    title: Text(label(g.kind)),
                    trailing: Text('目标 ${g.targetValue} ${g.unit ?? ''}'),
                  ),
                if (goals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('还没有目标', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final goalsProvider = StreamProvider((ref) => ref.read(repoProvider).watchGoals());
