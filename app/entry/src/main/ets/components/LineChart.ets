/// 自绘折线图（无三方库）：4 条横网格 + y 标签 + 4 等分 x 标签，
/// >2 点走二次中点平滑（对齐 fl_chart isCurved），≤30 点画 r3 圆点。
import { SeriesPoint } from '../core/repo/Model';

/** 与 Flutter AppPalette 一致的序列色（明暗主题不变）。 */
export const SERIES1: string = '#2A78D6';
export const SERIES2: string = '#EB6834';
export const SERIES3: string = '#1BAF7A';

const GRID_COLOR: string = '#26808080';
const LABEL_COLOR: string = '#99808080';
const LEFT_AXIS: number = 44;
const BOTTOM_AXIS: number = 20;
const TOP_PAD: number = 8;
const RIGHT_PAD: number = 8;

@ComponentV2
export struct LineChart {
  @Param points: SeriesPoint[] = [];
  @Param color: string = SERIES1;
  @Param emptyText: string = '记录后显示趋势';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @Monitor('points')
  onPointsChange(): void {
    this.draw();
  }

  private draw(): void {
    const ctx = this.ctx;
    const pts = this.points;
    const n = pts.length;
    if (n < 2) {
      return;
    }
    const w = ctx.width;
    const h = ctx.height;
    const plotL = LEFT_AXIS;
    const plotR = w - RIGHT_PAD;
    const plotT = TOP_PAD;
    const plotB = h - BOTTOM_AXIS;
    const plotW = plotR - plotL;
    const plotH = plotB - plotT;
    let min = pts[0].value;
    let max = pts[0].value;
    for (const p of pts) {
      if (p.value < min) {
        min = p.value;
      }
      if (p.value > max) {
        max = p.value;
      }
    }
    const range = max - min;
    const pad = range * 0.05;
    const lo = range <= 0 ? min - 1 : min - pad;
    const hi = range <= 0 ? max + 1 : max + pad;
    const xOf = (i: number): number => plotL + i * plotW / (n - 1);
    const yOf = (v: number): number => plotB - (v - lo) / (hi - lo) * plotH;

    // 横网格 4 条 + y 标签
    ctx.font = '10px sans-serif';
    ctx.lineWidth = 1;
    ctx.strokeStyle = GRID_COLOR;
    ctx.fillStyle = LABEL_COLOR;
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    for (let k = 0; k < 4; k++) {
      const v = lo + (hi - lo) * k / 3;
      const y = yOf(v);
      ctx.beginPath();
      ctx.moveTo(plotL, y);
      ctx.lineTo(plotR, y);
      ctx.stroke();
      ctx.fillText(v.toFixed(1), plotL - 6, y);
    }

    // x 标签：4 等分取点（MM-DD），避免小样本下索引重复
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    let lastI = -1;
    for (let k = 0; k < 4; k++) {
      const i = Math.round(k * (n - 1) / 3);
      if (i === lastI) {
        continue;
      }
      lastI = i;
      ctx.fillText(pts[i].date.slice(5), xOf(i), h - 4);
    }

    // 折线：>2 点二次中点平滑
    ctx.strokeStyle = this.color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(xOf(0), yOf(pts[0].value));
    if (n === 2) {
      ctx.lineTo(xOf(1), yOf(pts[1].value));
    } else {
      for (let i = 1; i < n - 1; i++) {
        const cx = (xOf(i) + xOf(i + 1)) / 2;
        const cy = (yOf(pts[i].value) + yOf(pts[i + 1].value)) / 2;
        ctx.quadraticCurveTo(xOf(i), yOf(pts[i].value), cx, cy);
      }
      ctx.lineTo(xOf(n - 1), yOf(pts[n - 1].value));
    }
    ctx.stroke();

    // 圆点
    if (n <= 30) {
      ctx.fillStyle = this.color;
      for (let i = 0; i < n; i++) {
        ctx.beginPath();
        ctx.arc(xOf(i), yOf(pts[i].value), 3, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  build() {
    if (this.points.length < 2) {
      Text(this.emptyText)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .height(200)
        .textAlign(TextAlign.Center)
    } else {
      Canvas(this.ctx)
        .width('100%')
        .height(200)
        .onReady((): void => {
          this.draw();
        })
        .onAreaChange((_o: Area, _n: Area): void => {
          this.draw();
        })
    }
  }
}
