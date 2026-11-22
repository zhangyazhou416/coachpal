/// 饮食记录：食物搜索（歧义弹窗）+ 自定义条目 + 今日餐次列表。
library;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/connection.dart';
import '../../core/db/database.dart';
import '../../core/domain/food_search.dart';
import '../../core/repo/repository.dart';
import '../../main.dart';

String todayIso() => DateFormat('yyyy-MM-dd').format(DateTime.now());

class MealPage extends ConsumerStatefulWidget {
  const MealPage({super.key});

  @override
  ConsumerState<MealPage> createState() => _MealPageState();
}

class _MealPageState extends ConsumerState<MealPage> {
  final _search = TextEditingController();
  final _grams = TextEditingController(text: '100');
  String _type = 'lunch';
  final _pending = <(FoodHit, double)>[];
  final _pendingCustom = <Map<String, Object?>>[];
  List<FoodHit>? _results;

  @override
  void dispose() {
    _search.dispose();
    _grams.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final repo = ref.read(repoProvider);
    final hits = await repo.searchFoods(_search.text);
    setState(() => _results = hits);
    if (hits.isEmpty) {
      _snack('食物库里找不到「${_search.text}」，可换通用名或用自定义条目');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _pickFood(FoodHit hit) async {
    final grams = double.tryParse(_grams.text) ?? 100;
    final resolved = resolveFood([hit]);
    if (resolved != null) {
      setState(() => _pending.add((resolved, grams)));
      return;
    }
    // 歧义：弹候选框（resolveFood 只拿了单个候选，需要全列表）
    final matches = await ref.read(repoProvider).searchFoods(hit.name);
    if (!mounted) return;
    final candidates = matches.take(5).toList();
    final picked = await showModalBottomSheet<FoodHit>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('匹配到多个食物，请选择：'),
            ),
            for (final c in candidates)
              ListTile(
                title: Text(c.name),
                subtitle: Text(
                    '${c.foodCode ?? '-'} · ${c.kcal?.toStringAsFixed(0) ?? '?'} kcal/100g'),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _pending.add((picked, grams)));
  }

  Future<void> _addCustom() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义条目'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, decoration: const InputDecoration(
                labelText: '格式：名称:克数:热量:蛋白:脂肪:碳水')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok != true) return;
    final parts = controller.text.split(':');
    if (parts.length < 6) {
      _snack('格式：名称:克数:热量:蛋白:脂肪:碳水');
      return;
    }
    final nums = parts.skip(1).map((e) => double.tryParse(e) ?? 0).toList();
    setState(() => _pendingCustom.add({
          'name': parts[0],
          'grams': nums[0],
          'kcal': nums[1],
          'protein': nums[2],
          'fat': nums[3],
          'carbs': nums[4],
        }));
  }

  Future<void> _save() async {
    if (_pending.isEmpty && _pendingCustom.isEmpty) {
      _snack('先添加食物');
      return;
    }
    final repo = ref.read(repoProvider);
    await repo.addMeal(
      mealType: _type,
      date: todayIso(),
      dbItems: _pending,
      customItems: _pendingCustom,
    );
    setState(() {
      _pending.clear();
      _pendingCustom.clear();
    });
    _snack('已记录');
  }

  @override
  Widget build(BuildContext context) {
    final meals = ref.watch(mealTodayProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: '餐次'),
                      items: const [
                        DropdownMenuItem(value: 'breakfast', child: Text('早餐')),
                        DropdownMenuItem(value: 'lunch', child: Text('午餐')),
                        DropdownMenuItem(value: 'dinner', child: Text('晚餐')),
                        DropdownMenuItem(value: 'snack', child: Text('加餐')),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'lunch'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                          labelText: '搜索食物（如：鸡胸肉、米饭）'),
                      onSubmitted: (_) => _doSearch(),
                    ),
                  ),
                  IconButton(onPressed: _doSearch, icon: const Icon(Icons.search)),
                ]),
                const SizedBox(height: 8),
                if (_results != null)
                  for (final hit in _results!.take(5))
                    ListTile(
                      dense: true,
                      title: Text(hit.name),
                      subtitle: Text(
                          '${hit.kcal?.toStringAsFixed(0) ?? '?'} kcal/100g · P${hit.protein ?? '-'} F${hit.fat ?? '-'} C${hit.carbs ?? '-'}'),
                      trailing: SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _grams,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '克'),
                        ),
                      ),
                      onTap: () => _pickFood(hit),
                    ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (hit, g) in _pending)
                      InputChip(
                        label: Text('${hit.name} ${g}g'),
                        onDeleted: () =>
                            setState(() => _pending.remove((hit, g))),
                      ),
                    for (final c in _pendingCustom)
                      InputChip(
                        label: Text('${c['name']} ${c['grams']}g'),
                        onDeleted: () =>
                            setState(() => _pendingCustom.remove(c)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton.icon(
                      onPressed: _addCustom,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('自定义')),
                  const Spacer(),
                  FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check),
                      label: const Text('记录这一餐')),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('今天已记录', style: Theme.of(context).textTheme.titleMedium),
        for (final entry in meals)
          Card(
            child: ListTile(
              title: Text('${_mealLabel(entry.meal.mealType)} · '
                  '${entry.items.fold<double>(0, (a, i) => a + i.kcal).toStringAsFixed(0)} kcal'),
              subtitle: Text(entry.items
                  .map((i) => '${i.foodName} ${i.grams.toStringAsFixed(0)}g')
                  .join('、')),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await ref.read(repoProvider).deleteMeal(entry.meal.uuid);
                },
              ),
            ),
          ),
        if (meals.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('今天还没有饮食记录')),
          ),
      ],
    );
  }

  String _mealLabel(String t) =>
      {'breakfast': '早餐', 'lunch': '午餐', 'dinner': '晚餐', 'snack': '加餐'}[t] ?? t;
}

final mealTodayProvider = StreamProvider<List<MealEntry>>((ref) {
  final repo = ref.read(repoProvider);
  return repo.watchMeals(todayIso());
});
