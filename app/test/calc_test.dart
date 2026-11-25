/// 领域计算单测：期望值与 Python 侧 tests/ 对齐（跨语言对拍）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:coachpal_app/core/domain/calc.dart';
import 'package:coachpal_app/core/domain/food_search.dart';
import 'package:coachpal_app/core/domain/set_parser.dart';

void main() {
  test('estimate1rm 与 Python 一致', () {
    expect(estimate1rm(100, 1), 100.0);
    expect(estimate1rm(80, 5), 91.7);
    expect(estimate1rm(120, 3), 129.5);
    expect(estimate1rm(60, 15) > 60, isTrue);
  });

  test('percentageTable 与 Python 一致', () {
    final table = percentageTable(100, step: 2.5);
    final byPct = {for (final r in table) r.pct: r};
    expect(byPct[100]!.weight, 100.0);
    expect(byPct[75]!.weight, 75.0);
    expect(byPct[90]!.weight, 90.0);
    expect(table.every((r) => r.repsGuide >= 1), isTrue);
  });

  test('computeTargets 减脂目标', () {
    final t = computeTargets(
      sex: 'male', age: 31, heightCm: 178, weightKg: 77.9,
      activityLevel: 'moderate', goalType: 'cut',
    )!;
    // Python: BMR 1742 / TDEE 2699 / kcal 2290 / 蛋白 156 / 脂 64 / 碳 272
    expect(t.bmr, 1742.0);
    expect(t.tdee, 2699.0);
    expect(t.kcal, 2290.0);
    expect(t.protein, 156.0);
    expect(t.fat, 64.0);
    expect(t.carbs, 272.0);
  });

  test('parseSetSpec 变体', () {
    final a = parseSetSpec('卧推 80 5 @8')!;
    expect(a.name, '卧推');
    expect(a.weightKg, 80.0);
    expect(a.reps, 5);
    expect(a.rpe, 8.0);
    final b = parseSetSpec('Barbell Squat 100kg x 3')!;
    expect(b.weightKg, 100.0);
    expect(b.reps, 3);
    expect(b.rpe, isNull);
    final c = parseSetSpec('引体向上 0 10')!;
    expect(c.weightKg, 0.0);
    expect(parseSetSpec('不完整的输入'), isNull);
  });

  test('食物评分排序（关键项）', () {
    final rows = [
      {'id': 1, 'foodCode': '111105', 'name': '鸡蛋白', 'kcal': 60.0},
      {'id': 2, 'foodCode': '091112', 'name': '鸡胸脯肉', 'kcal': 118.0,
       'protein': 24.6, 'fat': 1.9, 'carbs': 0.6},
      {'id': 3, 'foodCode': '012401x', 'name': '米饭（蒸，代表值）', 'kcal': 116.0},
    ];
    final hits = scoreFoods(rows, '鸡胸');
    expect(hits.first.name, '鸡胸脯肉');
    expect(hits.first.matchScore, greaterThan(400));
  });

  test('resolveFood 歧义策略', () {
    final rows = [
      {'id': 1, 'foodCode': '111204', 'name': '鸡蛋（煮）', 'kcal': 139.0},
      {'id': 2, 'foodCode': '111102', 'name': '鸡蛋（白皮）', 'kcal': 139.0},
      {'id': 3, 'foodCode': '111101x', 'name': '鸡蛋（代表值）', 'kcal': 139.0},
    ];
    final hits = scoreFoods(rows, '鸡蛋');
    // 多个同分候选 → 代表值胜出
    expect(resolveFood(hits)?.name, contains('代表值'));
    expect(resolveFood(hits.sublist(0, 2))?.name, isNull); // 仍歧义
  });

  test('scaleMacros 换算', () {
    final hit = FoodHit(
      code: 1, name: '鸡胸脯肉', kcal: 118, protein: 24.6, fat: 1.9, carbs: 0.6,
      matchScore: 100,
    );
    final m = scaleMacros(hit, 150);
    expect(m['kcal']!, closeTo(177.0, 0.2));
    expect(m['protein']!, closeTo(36.9, 0.2));
  });
}
