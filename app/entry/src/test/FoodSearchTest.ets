import { describe, it, expect } from '@ohos/hypium';
import { normName, scoreFoods, resolveFood, scaleMacros, FoodRow, FoodHit } from '../main/ets/core/domain/food_search';

function row(name: string, code: string, kcal: number | null, protein: number | null,
  fat: number | null, carbs: number | null): FoodRow {
  const r: FoodRow = {
    key: name,
    foodCode: code,
    name: name,
    nameEn: null,
    category: null,
    kcal: kcal,
    protein: protein,
    fat: fat,
    carbs: carbs,
    fiber: null,
    gi: null,
  };
  return r;
}

export default function foodSearchTest() {
  describe('foodSearchTest', () => {
    it('normName_规范名', 0, () => {
      expect(normName('米饭（蒸，代表值）')).assertEqual('米饭');
      expect(normName('＊鸡 胸*脯 肉')).assertEqual('鸡胸脯肉');
      expect(normName('面包(全麦)')).assertEqual('面包');
    });

    it('食物评分排序_关键项', 0, () => {
      const rows: FoodRow[] = [
        row('鸡蛋白', '111105', 60.0, null, null, null),
        row('鸡胸脯肉', '091112', 118.0, 24.6, 1.9, 0.6),
        row('米饭（蒸，代表值）', '012401x', 116.0, null, null, null),
      ];
      const hits = scoreFoods(rows, '鸡胸');
      expect(hits.length > 0).assertTrue();
      expect(hits[0].name).assertEqual('鸡胸脯肉');
      expect(hits[0].matchScore > 400).assertTrue();
    });

    it('resolveFood_代表值胜出与歧义', 0, () => {
      const rows: FoodRow[] = [
        row('鸡蛋（煮）', '111204', 139.0, null, null, null),
        row('鸡蛋（白皮）', '111102', 139.0, null, null, null),
        row('鸡蛋（代表值）', '111101x', 139.0, null, null, null),
      ];
      const hits = scoreFoods(rows, '鸡蛋');
      // 多个同分候选 → 代表值胜出
      const chosen = resolveFood(hits);
      expect(chosen === null || !chosen.name.includes('代表值')).assertFalse();
      const ambiguous = resolveFood(hits.slice(0, 2));
      expect(ambiguous).assertNull();
    });

    it('scaleMacros_换算', 0, () => {
      const hit: FoodHit = {
        foodCode: null,
        name: '鸡胸脯肉',
        nameEn: null,
        category: null,
        kcal: 118,
        protein: 24.6,
        fat: 1.9,
        carbs: 0.6,
        fiber: null,
        gi: null,
        matchScore: 100,
      };
      const m = scaleMacros(hit, 150);
      expect(Math.abs(m.kcal - 177.0) < 0.2).assertTrue();
      expect(Math.abs(m.protein - 36.9) < 0.2).assertTrue();
    });

    it('空查询返回空', 0, () => {
      expect(scoreFoods([], '').length).assertEqual(0);
      expect(resolveFood([])).assertNull();
    });
  });
}
