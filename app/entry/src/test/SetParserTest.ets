import { describe, it, expect } from '@ohos/hypium';
import { parseSetSpec, ZH_ALIASES } from '../main/ets/core/domain/set_parser';

export default function setParserTest() {
  describe('setParserTest', () => {
    it('解析rpe变体', 0, () => {
      const a = parseSetSpec('卧推 80 5 @8');
      expect(a === null).assertFalse();
      if (a !== null) {
        expect(a.name).assertEqual('卧推');
        expect(a.weightKg).assertEqual(80.0);
        expect(a.reps).assertEqual(5);
        expect(a.rpe).assertEqual(8.0);
      }
    });

    it('解析kgx变体', 0, () => {
      const b = parseSetSpec('Barbell Squat 100kg x 3');
      expect(b === null).assertFalse();
      if (b !== null) {
        expect(b.weightKg).assertEqual(100.0);
        expect(b.reps).assertEqual(3);
        expect(b.rpe).assertNull();
      }
    });

    it('解析自重变体与失败', 0, () => {
      const c = parseSetSpec('引体向上 0 10');
      expect(c === null).assertFalse();
      if (c !== null) {
        expect(c.weightKg).assertEqual(0.0);
      }
      expect(parseSetSpec('不完整的输入')).assertNull();
    });

    it('中文别名表存在', 0, () => {
      const kw = ZH_ALIASES['卧推'];
      expect(kw === undefined).assertFalse();
      if (kw !== undefined) {
        expect(kw.length > 0).assertTrue();
        expect(kw[0]).assertEqual('barbell bench press');
      }
    });
  });
}
