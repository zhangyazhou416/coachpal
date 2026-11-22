/// 食物搜索评分：与 fitfuel.nutrition.search_foods 对齐。
///
/// 相似度用 LCS 比近似 difflib ratio（排序效果一致，非逐字符等价）。
library;

String normName(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll('*', '').replaceAll('＊', '');
  t = t.replaceAll(RegExp(r'[（(［\[].*?[）)］\]]'), '');
  t = t.replaceAll(RegExp(r'[\s·,，、]+'), '');
  return t;
}

/// 2*LCS/(len1+len2)，近似 Python difflib.SequenceMatcher.ratio。
double similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final m = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      m[i][j] = a[i - 1] == b[j - 1]
          ? m[i - 1][j - 1] + 1
          : (m[i - 1][j] > m[i][j - 1] ? m[i - 1][j] : m[i][j - 1]);
    }
  }
  return 2 * m[a.length][b.length] / (a.length + b.length);
}

class FoodHit {
  final int? code;            // 数据库行 id
  final String? foodCode;     // 成分表编码
  final String name;
  final String? nameEn;
  final String? category;
  final double? kcal, protein, fat, carbs, fiber, gi;
  final double matchScore;
  const FoodHit({
    required this.code,
    this.foodCode,
    required this.name,
    this.nameEn,
    this.category,
    this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.fiber,
    this.gi,
    required this.matchScore,
  });
}

/// rows: 本地 foods 表全量（一次载入缓存后复用）。
List<FoodHit> scoreFoods(List<Map<String, Object?>> rows, String query,
    {int limit = 15}) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final ql = q.toLowerCase();
  final qn = normName(q);
  final scored = <(double, FoodHit)>[];
  for (final r in rows) {
    final name = (r['name'] as String?) ?? '';
    final nn = normName(name);
    final nameEn = ((r['nameEn'] as String?) ?? '').toLowerCase();
    final category = ((r['category'] as String?) ?? '').toLowerCase();
    final code = ((r['foodCode'] as String?) ?? '').toLowerCase();
    var score = 0.0;
    if (ql == code && code.isNotEmpty) {
      score = 1000;
    } else if (ql == name.toLowerCase()) {
      score = 900;
    } else if (qn.isNotEmpty && qn == nn) {
      score = 880;
    } else if (qn.isNotEmpty && nn.startsWith(qn)) {
      score = 760 - (nn.length - qn.length).clamp(0, 80) * 0.5;
    } else if (qn.isNotEmpty && nn.contains(qn)) {
      score = 680 - (nn.length - qn.length).clamp(0, 80) * 0.5;
    } else {
      score = similarity(qn, nn) * 520;
    }
    if (nameEn.isNotEmpty && nameEn.contains(ql)) {
      score = score > 600 ? score : 600;
    }
    if (category.contains(ql)) {
      score = score > 320 ? score : 320;
    }
    if (score < 300) continue;
    scored.add((
      score,
      FoodHit(
        code: r['id'] as int?,
        foodCode: r['foodCode'] as String?,
        name: name,
        nameEn: r['nameEn'] as String?,
        category: r['category'] as String?,
        kcal: r['kcal'] as double?,
        protein: r['protein'] as double?,
        fat: r['fat'] as double?,
        carbs: r['carbs'] as double?,
        fiber: r['fiber'] as double?,
        gi: r['gi'] as double?,
        matchScore: double.parse(score.toStringAsFixed(1)),
      ),
    ));
  }
  scored.sort((a, b) {
    final c = b.$1.compareTo(a.$1);
    if (c != 0) return c;
    return (a.$2.name.length).compareTo(b.$2.name.length);
  });
  return scored.take(limit).map((e) => e.$2).toList();
}

/// 与 Python resolve_food 一致的歧义策略。
/// 返回 null 表示歧义（candidates 给 UI 弹选择）。
FoodHit? resolveFood(List<FoodHit> matches) {
  if (matches.isEmpty) return null;
  final top = matches.first;
  final second = matches.length > 1 ? matches[1] : null;
  final margin = top.matchScore - (second?.matchScore ?? 0);
  if (top.matchScore >= 850 && (second == null || margin >= 15)) return top;
  if (top.matchScore >= 700 && (second == null || margin >= 40)) return top;
  final near = matches.where((m) => top.matchScore - m.matchScore <= 2).toList();
  final rep = near.where((m) => m.name.contains('代表值')).toList();
  if (rep.length == 1) return rep.first;
  return null;
}

/// 每 100g → 指定克数换算（与 Python _scale 一致；热量缺失用 4/9/4 估算）。
Map<String, double> scaleMacros(FoodHit food, double grams) {
  final protein = food.protein ?? 0;
  final fat = food.fat ?? 0;
  final carbs = food.carbs ?? 0;
  final fiber = food.fiber ?? 0;
  final kcal = food.kcal ?? protein * 4 + fat * 9 + carbs * 4;
  final f = grams / 100.0;
  return {
    'kcal': double.parse((kcal * f).toStringAsFixed(1)),
    'protein': double.parse((protein * f).toStringAsFixed(1)),
    'fat': double.parse((fat * f).toStringAsFixed(1)),
    'carbs': double.parse((carbs * f).toStringAsFixed(1)),
    'fiber': double.parse((fiber * f).toStringAsFixed(1)),
  };
}
