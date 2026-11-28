/** 轻量 Markdown 渲染：加粗 / 行内代码 / # 标题 / --- 分割线 / GFM 表格 / 空行。
 *  覆盖模型回复的常见格式，不追求完整规范。 */
import { MeasureText } from '@kit.ArkUI';

interface MdSeg {
  text: string;
  bold: boolean;
  mono: boolean;
}

interface MdBlock {
  kind: string; // 'blank' | 'hr' | 'h' | 'p' | 'table'
  lines: string[];
}

const INLINE_RE: RegExp = /(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`)/g;
const HEADING_RE: RegExp = /^#{1,6}\s+/;
const HR_RE: RegExp = /^-{3,}\s*$/;
const TABLE_SEP_RE: RegExp = /^:?-{3,}:?$/;

@ComponentV2
export struct MdText {
  @Param content: string = '';
  @Param fontSize: number = 14;

  private blocks(): MdBlock[] {
    const src: string[] = this.content.split('\n');
    const out: MdBlock[] = [];
    let i: number = 0;
    while (i < src.length) {
      const l: string = src[i];
      if (l.trim().length === 0) {
        out.push({ kind: 'blank', lines: [] });
        i++;
        continue;
      }
      if (HR_RE.test(l)) {
        out.push({ kind: 'hr', lines: [] });
        i++;
        continue;
      }
      if (l.trim().charAt(0) === '|') {
        const tbl: string[] = [];
        while (i < src.length && src[i].trim().charAt(0) === '|') {
          tbl.push(src[i].trim());
          i++;
        }
        out.push({ kind: 'table', lines: tbl });
        continue;
      }
      if (HEADING_RE.test(l)) {
        out.push({ kind: 'h', lines: [l] });
        i++;
        continue;
      }
      const para: string[] = [];
      while (i < src.length && src[i].trim().length > 0
        && !HR_RE.test(src[i]) && !HEADING_RE.test(src[i])
        && src[i].trim().charAt(0) !== '|') {
        para.push(src[i]);
        i++;
      }
      out.push({ kind: 'p', lines: para });
    }
    return out;
  }

  private segs(line: string): MdSeg[] {
    const out: MdSeg[] = [];
    const work: string = line.replace(HEADING_RE, '');
    let last: number = 0;
    let m: RegExpExecArray | null = INLINE_RE.exec(work);
    while (m !== null) {
      if (m.index > last) {
        out.push({ text: work.substring(last, m.index), bold: false, mono: false });
      }
      const t: string = m[0];
      if (t.charAt(0) === '`') {
        out.push({ text: t.substring(1, t.length - 1), bold: false, mono: true });
      } else {
        out.push({ text: t.replace(/\*\*/g, '').replace(/__/g, ''), bold: true, mono: false });
      }
      last = m.index + t.length;
      m = INLINE_RE.exec(work);
    }
    if (last < work.length) {
      out.push({ text: work.substring(last), bold: false, mono: false });
    }
    if (out.length === 0) {
      out.push({ text: ' ', bold: false, mono: false });
    }
    INLINE_RE.lastIndex = 0;
    return out;
  }

  private cells(row: string): string[] {
    let r: string = row;
    if (r.charAt(0) === '|') {
      r = r.substring(1);
    }
    if (r.charAt(r.length - 1) === '|') {
      r = r.substring(0, r.length - 1);
    }
    const parts: string[] = r.split('|');
    return parts.map((p: string): string => p.trim());
  }

  private isSepRow(row: string): boolean {
    const cs: string[] = this.cells(row);
    let ok: boolean = cs.length > 0;
    for (const c of cs) {
      if (!TABLE_SEP_RE.test(c)) {
        ok = false;
      }
    }
    return ok;
  }

  private tableRows(lines: string[]): string[] {
    return lines.filter((l: string): boolean => !this.isSepRow(l));
  }

  /** 单元格按行内样式分段实测总宽（vp）：加粗/等宽各按真实渲染样式测量，避免粗体折行。 */
  private cellTextWidth(cell: string, fs: number, boldAll: boolean): number {
    const parts: MdSeg[] = this.segs(cell);
    let wpx: number = 0;
    for (const s of parts) {
      wpx += MeasureText.measureText({
        textContent: s.text,
        fontSize: fs,
        fontWeight: boldAll || s.bold ? FontWeight.Bold : FontWeight.Normal,
        fontFamily: s.mono ? 'monospace' : 'HarmonyOS Sans'
      });
    }
    return px2vp(wpx);
  }

  /** 表格每列宽度 = 该列最大单元格内容实测宽度（夹取上限防止单格超长），配合横向滚动避免撑爆气泡。 */
  private colWidths(lines: string[]): number[] {
    const rows: string[] = this.tableRows(lines);
    let cols: number = 1;
    for (const r of rows) {
      cols = Math.max(cols, this.cells(r).length);
    }
    const fs: number = this.fontSize - 1;
    const w: number[] = [];
    for (let ci = 0; ci < cols; ci++) {
      let max: number = 0;
      for (const r of rows) {
        const cs: string[] = this.cells(r);
        if (ci < cs.length) {
          max = Math.max(max, this.cellTextWidth(cs[ci], fs, r === rows[0]));
        }
      }
      w.push(Math.min(Math.max(max, 24) + 8, 220));
    }
    return w;
  }

  private cellWidth(lines: string[], ci: number): number {
    const w: number[] = this.colWidths(lines);
    return ci >= 0 && ci < w.length ? w[ci] : 64;
  }

  /** 表格总宽（vp）= 各列宽之和，用于把表格容器钉在内容宽度上，避免被拉满气泡。 */
  private tableWidth(lines: string[]): number {
    const w: number[] = this.colWidths(lines);
    let sum: number = 0;
    for (const c of w) {
      sum += c;
    }
    return sum;
  }

  build() {
    Column({ space: 4 }) {
      ForEach(this.blocks(), (b: MdBlock, bi: number) => {
        if (b.kind === 'blank') {
          Text(' ').fontSize(6)
        } else if (b.kind === 'hr') {
          Divider().strokeWidth(1).color($r('app.color.divider')).margin({ top: 2, bottom: 2 })
        } else if (b.kind === 'h') {
          Text() {
            ForEach(this.segs(b.lines[0]), (s: MdSeg) => {
              Span(s.text).fontWeight(FontWeight.Bold)
            }, (s: MdSeg, si: number) => `${si}_${s.text}`)
          }
          .fontSize(this.fontSize + 3)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 4 })
          .wordBreak(WordBreak.BREAK_ALL)
        } else if (b.kind === 'table') {
          Scroll() {
            Column() {
              ForEach(this.tableRows(b.lines), (row: string, ri: number) => {
                Row() {
                  ForEach(this.cells(row), (c: string, ci: number) => {
                    Text() {
                      ForEach(this.segs(c), (s: MdSeg) => {
                        Span(s.text)
                          .fontWeight(ri === 0 || s.bold ? FontWeight.Bold : FontWeight.Normal)
                          .fontFamily(s.mono ? 'monospace' : 'HarmonyOS Sans')
                          .fontSize(this.fontSize - 1)
                          .fontColor($r('app.color.text_primary'))
                      }, (s: MdSeg, si: number) => `${si}_${s.text}`)
                    }
                    .width(this.cellWidth(b.lines, ci))
                    .padding({ left: 4, right: 4, top: 3, bottom: 3 })
                    .textAlign(TextAlign.Start)
                    .wordBreak(WordBreak.BREAK_ALL)
                  }, (c: string, ci: number) => `${ci}_${c}`)
                }
                .alignItems(VerticalAlign.Top)
                if (ri === 0) {
                  Divider().strokeWidth(0.5).color($r('app.color.divider'))
                }
              }, (row: string, ri: number) => `${ri}_${row.substring(0, 20)}`)
            }
            .width(this.tableWidth(b.lines))
            .backgroundColor($r('app.color.table_bg'))
            .borderRadius(8)
            .border({ width: 1, color: $r('app.color.card_border') })
            .clip(true)
            .alignItems(HorizontalAlign.Start)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Auto)
          .margin({ top: 2, bottom: 2 })
        } else {
          ForEach(b.lines, (line: string) => {
            Text() {
              ForEach(this.segs(line), (s: MdSeg) => {
                Span(s.text)
                  .fontWeight(s.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontFamily(s.mono ? 'monospace' : 'HarmonyOS Sans')
                  .fontSize(this.fontSize)
                  .fontColor($r('app.color.text_primary'))
              }, (s: MdSeg, si: number) => `${si}_${s.text}`)
            }
            .fontSize(this.fontSize)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
            .wordBreak(WordBreak.BREAK_ALL)
          }, (line: string) => line)
        }
      }, (b: MdBlock, bi: number) => `${bi}_${b.kind}_${b.lines.join(' ').substring(0, 20)}`)
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: '100%' })
  }
}
