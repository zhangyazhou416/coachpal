import { AppServices } from '../core/services';
import { ProfileRow } from '../core/repo/Model';
import { CardContainer } from '../components/Common';
import { router } from '@kit.ArkUI';

const SEX_LABELS: Record<string, string> = {
  'male': '男',
  'female': '女',
  'other': '其他',
};
const ACTIVITY_LABELS: Record<string, string> = {
  'sedentary': '久坐',
  'light': '轻度',
  'moderate': '中等',
  'active': '活跃',
  'very_active': '非常活跃',
};
const GOAL_LABELS: Record<string, string> = {
  'cut': '减脂',
  'maintain': '维持',
  'bulk': '增肌',
};

function mapLabel(m: Record<string, string>, v: string): string {
  const r = m[v];
  return r === undefined ? v : r;
}

/// 个人档案页（纯展示）：只读显示档案；修改通过教练对话完成。
@Entry
@ComponentV2
struct ProfileEditPage {
  @Local profile: ProfileRow | null = null;
  @Local loaded: boolean = false;

  aboutToAppear(): void {
    this.init();
  }

  private async init(): Promise<void> {
    const svc = AppServices.getInstance();
    await svc.whenReady();
    if (svc.repo !== null) {
      this.profile = await svc.repo.getProfile();
    }
    this.loaded = true;
  }

  private ageFromBirth(birth: string | null): string {
    if (birth === null || birth.length < 10) {
      return '—';
    }
    const y = Number(birth.substring(0, 4));
    const m = Number(birth.substring(5, 7));
    if (Number.isNaN(y) || Number.isNaN(m)) {
      return '—';
    }
    const now = new Date();
    let age = now.getFullYear() - y;
    if (now.getMonth() + 1 < m) {
      age--;
    }
    return `${age} 岁`;
  }

  @Builder
  titleBar(title: string) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
        .onClick((): void => {
          router.back();
        })
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        this.titleBar('个人档案')

        if (this.loaded && this.profile === null) {
          CardContainer() {
            Column({ space: 10 }) {
              Text('还没有档案')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('直接跟教练说一句即可建档，例如：\n「我男，31 岁，178cm，中等活动量，目标减脂」')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        } else if (this.profile !== null) {
          CardContainer() {
            Column({ space: 4 }) {
              this.infoRow('性别', mapLabel(SEX_LABELS, this.profile.sex))
              this.infoRow('年龄', this.ageFromBirth(this.profile.birthDate))
              this.infoRow('生日', this.profile.birthDate ?? '—')
              this.infoRow('身高',
                this.profile.heightCm === null || this.profile.heightCm <= 0
                  ? '—' : `${this.profile.heightCm} cm`)
              this.infoRow('活动水平', mapLabel(ACTIVITY_LABELS, this.profile.activityLevel))
              this.infoRow('目标', mapLabel(GOAL_LABELS, this.profile.goalType))
            }
            .width('100%')
          }
          CardContainer() {
            Column({ space: 6 }) {
              Text('✏️ 修改档案')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('直接跟教练说，例如「身高改成 180」或「目标改成增肌」，我会帮你更新。')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }
      }
      .padding(16)
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
  }
}
