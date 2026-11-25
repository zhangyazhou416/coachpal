import { describe, it, expect } from '@ohos/hypium';
import { estimate1rm, percentageTable, computeTargets, roundPy, calcBmi } from '../main/ets/core/domain/calc';

export default function calcTest() {
  describe('calcTest', () => {
    it('estimate1rm_与Python一致', 0, () => {
      expect(estimate1rm(100, 1)).assertEqual(100.0);
      expect(estimate1rm(80, 5)).assertEqual(91.7);
      expect(estimate1rm(120, 3)).assertEqual(129.5);
      expect(estimate1rm(60, 15) > 60).assertTrue();
    });

    it('roundPy_银行家舍入', 0, () => {
      expect(roundPy(0.5)).assertEqual(0.0);
      expect(roundPy(2.5)).assertEqual(2.0);
      expect(roundPy(-2.5)).assertEqual(-2.0);
      expect(roundPy(1.5)).assertEqual(2.0);
      expect(roundPy(1741.5)).assertEqual(1742.0);
    });

    it('percentageTable_与Python一致', 0, () => {
      const table = percentageTable(100, 2.5);
      let w100 = -1;
      let w75 = -1;
      let w90 = -1;
      let allGuide = true;
      for (const r of table) {
        if (r.pct === 100) {
          w100 = r.weight;
        }
        if (r.pct === 75) {
          w75 = r.weight;
        }
        if (r.pct === 90) {
          w90 = r.weight;
        }
        if (r.repsGuide < 1) {
          allGuide = false;
        }
      }
      expect(w100).assertEqual(100.0);
      expect(w75).assertEqual(75.0);
      expect(w90).assertEqual(90.0);
      expect(allGuide).assertTrue();
    });

    it('computeTargets_减脂目标', 0, () => {
      const t = computeTargets('male', 31, 178, 77.9, 'moderate', 'cut');
      expect(t === null).assertFalse();
      if (t !== null) {
        // Python: BMR 1742 / TDEE 2699 / kcal 2290 / 蛋白 156 / 脂 64 / 碳 272 / 纤维 32
        expect(t.bmr).assertEqual(1742.0);
        expect(t.tdee).assertEqual(2699.0);
        expect(t.kcal).assertEqual(2290.0);
        expect(t.protein).assertEqual(156.0);
        expect(t.fat).assertEqual(64.0);
        expect(t.carbs).assertEqual(272.0);
        expect(t.fiber).assertEqual(32.0);
        expect(t.clamped).assertFalse();
      }
    });

    it('computeTargets_下限钳制', 0, () => {
      const t = computeTargets('female', 60, 150, 40, 'sedentary', 'cut');
      expect(t === null).assertFalse();
      if (t !== null) {
        expect(t.clamped).assertTrue();
        expect(t.kcal).assertEqual(1200.0);
      }
    });

    it('calcBmi', 0, () => {
      expect(calcBmi(77.9, 178)).assertEqual(24.6);
      expect(calcBmi(null, 178)).assertNull();
    });
  });
}
