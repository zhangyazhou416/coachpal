import { AppServices } from '../core/services';
import { CardContainer } from '../components/Common';
import { AiSource } from '../core/settings/Settings';
import { router } from '@kit.ArkUI';

/// 我的页：用户信息卡（AI 状态）+ 设置菜单（个人档案 / AI 服务）。
@ComponentV2
export struct ProfilePage {
  @Param hubVersion: number = 0;
  @Local aiOk: boolean = false;
  @Local aiLabel: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  @Monitor('hubVersion')
  onHubVersionChange(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const svc = AppServices.getInstance();
    await svc.whenReady();
    const source = await svc.settings.getAiSource();
    if (source === AiSource.CUSTOM) {
      this.aiOk = await svc.settings.isAiConfigured();
      this.aiLabel = this.aiOk ? 'AI：自定义模型' : 'AI：自定义模型待配置';
    } else {
      this.aiOk = true;
      this.aiLabel = 'AI：华为端侧模型';
    }
  }

  @Builder
  menuRow(icon: Resource, title: string, sub: string, onTap: () => void) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([$r('app.color.accent')])
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor('rgba(235,104,52,0.12)')
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Text(sub)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(60)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 用户信息
        Column({ space: 12 }) {
          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
                .fontSize(28)
                .fontColor([$r('app.color.accent')])
            }
            .width(54)
            .height(54)
            .borderRadius(27)
            .backgroundColor(Color.White)
            .justifyContent(FlexAlign.Center)
            .shadow({ radius: 6, color: 'rgba(0,0,0,0.18)', offsetY: 2 })

            Column({ space: 2 }) {
              Text('CoachPal')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text(this.aiLabel)
                .fontSize(12)
                .fontColor('#E6FFFFFF')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text(this.aiOk ? '✓' : '!')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor(this.aiOk ? $r('app.color.status_good') : $r('app.color.status_warn'))
          }
          .width('100%')
        }
        .padding(18)
        .borderRadius(16)
        .linearGradient({
          angle: 135,
          colors: [[$r('app.color.primary'), 0], [$r('app.color.accent'), 1]],
        })
        .shadow({ radius: 10, color: 'rgba(235,104,52,0.30)', offsetY: 3 })

        // 设置菜单
        CardContainer() {
          Column() {
            this.menuRow($r('sys.symbol.person_fill'), '个人档案',
              '性别 · 身高 · 活动水平 · 目标', (): void => {
                router.pushUrl({ url: 'pages/ProfileEditPage' });
              })
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 62 })
            this.menuRow($r('sys.symbol.bolt'), 'AI 服务',
              '端侧模型 · 自定义模型', (): void => {
                router.pushUrl({ url: 'pages/AiConfigPage' });
              })
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
