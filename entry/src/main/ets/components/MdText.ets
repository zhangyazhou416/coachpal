/** 轻量 Markdown 渲染：加粗 / 行内代码 / # 标题 / --- 分割线 / GFM 表格 / 空行。
 *  覆盖模型回复的常见格式，不追求完整规范。 */

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
        } else if (b.kind === 'table') {
          Column() {
            ForEach(b.lines.filter((l: string): boolean => !this.isSepRow(l)), (row: string, ri: number) => {
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
                  .layoutWeight(1)
                  .padding(4)
                  .textAlign(TextAlign.Start)
                }, (c: string, ci: number) => `${ci}_${c}`)
              }
              .alignItems(VerticalAlign.Center)
              .width('100%')
              if (ri < b.lines.length - 1) {
                Divider().strokeWidth(0.5).color($r('app.color.divider'))
              }
            }, (row: string, ri: number) => `${ri}_${row.substring(0, 20)}`)
          }
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
          }, (line: string) => line)
        }
      }, (b: MdBlock, bi: number) => `${bi}_${b.kind}_${b.lines.join(' ').substring(0, 20)}`)
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: '100%' })
  }
}
