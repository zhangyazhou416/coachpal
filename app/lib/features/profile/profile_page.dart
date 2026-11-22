/// 我的：个人档案（身高/性别/生日/活动水平/目标）+ 体重快捷记录。
library;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/connection.dart';
import '../../core/db/database.dart';
import '../../main.dart';

final profileProvider = StreamProvider<ProfileData>((ref) {
  final db = ref.read(databaseProvider);
  return (db.select(db.profile)..where((p) => p.id.equals(1)))
      .watchSingle();
});

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _bodyFat = TextEditingController();
  String _sex = 'male';
  String _activity = 'moderate';
  String _goal = 'cut';
  bool _loaded = false;

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final db = ref.read(databaseProvider);
    await (db.update(db.profile)..where((p) => p.id.equals(1))).write(
      ProfileCompanion(
        sex: Value(_sex),
        heightCm: Value(double.tryParse(_height.text)),
        activityLevel: Value(_activity),
        goalType: Value(_goal),
        updatedAt: Value(
            DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(DateTime.now().toUtc())),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('档案已保存')),
      );
    }
  }

  Future<void> _addWeight() async {
    final w = double.tryParse(_weight.text);
    if (w == null || w < 20 || w > 400) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now().toUtc();
    final date = DateFormat('yyyy-MM-dd').format(now);
    await db.into(db.bodyMetrics).insertOnConflictUpdate(
          BodyMetricsCompanion.insert(
            uuid: _uuid(),
            date: date,
            weightKg: Value(w),
            bodyFatPct: Value(double.tryParse(_bodyFat.text)),
            updatedAt: DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(now),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记录 $date 体重 $w kg')),
      );
      _weight.clear();
      _bodyFat.clear();
    }
  }

  String _uuid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
      (DateTime.now().millisecondsSinceEpoch % 99991).toRadixString(16);

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (profile != null && !_loaded) {
      _loaded = true;
      _sex = profile.sex;
      _activity = profile.activityLevel;
      _goal = profile.goalType;
      if (profile.heightCm != null) _height.text = profile.heightCm.toString();
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('个人档案', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _sex,
                    decoration: const InputDecoration(labelText: '性别'),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('男')),
                      DropdownMenuItem(value: 'female', child: Text('女')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) => setState(() => _sex = v ?? 'male'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '身高 (cm)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _activity,
                    decoration: const InputDecoration(labelText: '活动水平'),
                    items: const [
                      DropdownMenuItem(value: 'sedentary', child: Text('久坐')),
                      DropdownMenuItem(value: 'light', child: Text('轻度')),
                      DropdownMenuItem(value: 'moderate', child: Text('中等')),
                      DropdownMenuItem(value: 'active', child: Text('活跃')),
                      DropdownMenuItem(value: 'very_active', child: Text('非常活跃')),
                    ],
                    onChanged: (v) => setState(() => _activity = v ?? 'moderate'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _goal,
                    decoration: const InputDecoration(labelText: '目标'),
                    items: const [
                      DropdownMenuItem(value: 'cut', child: Text('减脂')),
                      DropdownMenuItem(value: 'maintain', child: Text('维持')),
                      DropdownMenuItem(value: 'bulk', child: Text('增肌')),
                    ],
                    onChanged: (v) => setState(() => _goal = v ?? 'maintain'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saveProfile,
                    child: const Text('保存档案'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('记一笔体重', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '体重 (kg)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bodyFat,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '体脂率 %（可选）'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: _addWeight,
                    child: const Text('记录体重'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
