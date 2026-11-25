/// 共享 UI 组件与展示辅助：卡片容器、Chip、餐次/部位常量、格式化。

@Builder
function emptyBuilder() {
}

/** 卡片容器：radius 12、无阴影、1px 描边（与 Flutter Card 主题一致）。 */
@ComponentV2
export struct CardContainer {
  @BuilderParam content: () => void = emptyBuilder;

  build() {
    Column() {
      Column() {
        this.content()
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius(12)
    .borderWidth(1)
    .borderColor($r('app.color.card_border'))
  }
}

/** 小节标题。 */
@ComponentV2
export struct SectionTitle {
  @Param text: string = '';

  build() {
    Text(this.text)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
  }
}

/** 可删除的输入 Chip。 */
@ComponentV2
export struct TagChip {
  @Param label: string = '';
  onDelete: () => void = (): void => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
      Text('✕')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 6 })
        .onClick((): void => this.onDelete())
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.divider'))
    .borderRadius(16)
    .margin({ right: 8, top: 4, bottom: 4 })
  }
}

// ------------------------------------------------------- 常量与标签

export const MEAL_TYPES: string[] = ['breakfast', 'lunch', 'dinner', 'snack'];
export const MEAL_TYPE_LABELS: string[] = ['早餐', '午餐', '晚餐', '加餐'];

const MEAL_LABELS: Record<string, string> = {
  'breakfast': '早餐',
  'lunch': '午餐',
  'dinner': '晚餐',
  'snack': '加餐',
};

export function mealLabel(t: string): string {
  const v = MEAL_LABELS[t];
  return v ?? t;
}

export interface SiteLabel {
  site: string;
  label: string;
}

export const SITES: SiteLabel[] = [
  { site: 'chest', label: '胸围' },
  { site: 'waist', label: '腰围' },
  { site: 'hip', label: '臀围' },
  { site: 'neck', label: '颈围' },
  { site: 'shoulder', label: '肩围' },
  { site: 'arm', label: '上臂围' },
  { site: 'forearm', label: '前臂围' },
  { site: 'thigh', label: '大腿围' },
  { site: 'calf', label: '小腿围' },
  { site: 'wrist', label: '腕围' },
];

export function siteLabel(site: string): string {
  for (const s of SITES) {
    if (s.site === site) {
      return s.label;
    }
    const zh = SITE_ZH[site];
    if (zh !== undefined) {
      return zh;
    }
  }
  return site;
}

/** measurements.site 的中文别名（服务端/CLI 侧可能有同义写法）。 */
const SITE_ZH: Record<string, string> = {
  'chest': '胸围',
  'waist': '腰围',
  'hip': '臀围',
  'neck': '颈围',
  'shoulder': '肩围',
  'arm': '上臂围',
  'forearm': '前臂围',
  'thigh': '大腿围',
  'calf': '小腿围',
  'wrist': '腕围',
};

/** 目标 kind → 展示名（measure:<site>/strength:<lift> 前缀解析）。 */
export function goalKindLabel(kind: string): string {
  if (kind.startsWith('measure:')) {
    return `围度 ${siteLabel(kind.split(':')[1])}`;
  }
  if (kind.startsWith('strength:')) {
    return `${kind.split(':')[1]} 1RM`;
  }
  const m: Record<string, string> = {
    'weight': '体重',
    'body_fat': '体脂率',
    'muscle': '骨骼肌量',
  };
  const v = m[kind];
  return v ?? kind;
}

// ------------------------------------------------------- 格式化

/** kcal 展示：null → '?'，否则取整。 */
export function fmtKcal(v: number | null): string {
  return v === null ? '?' : String(Math.round(v));
}

/** 宏量展示：null → '-'。 */
export function fmtMacro(v: number | null): string {
  return v === null ? '-' : String(v);
}

/** 重量展示：整数不带小数，带小数保留 1 位（对齐 Dart toStringAsFixed 逻辑）。 */
export function fmtKg(v: number | null): string {
  if (v === null) {
    return '0';
  }
  return v % 1 === 0 ? v.toFixed(0) : v.toFixed(1);
}

/** 宽松数字解析（空串/非法 → null，对齐 Dart double.tryParse）。 */
export function parseNum(s: string): number | null {
  const t = s.trim();
  if (t.length === 0) {
    return null;
  }
  const n = Number(t);
  return Number.isNaN(n) ? null : n;
}
