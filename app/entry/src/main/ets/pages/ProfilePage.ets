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
          .fontColor([$r('app.color.primary')])
      }
      .width(34)
      .height(34)
      .borderRadius(8)
      .backgroundColor($r('app.color.divider'))
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
        CardContainer() {
          Column({ space: 12 }) {
            Row({ space: 14 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
                  .fontSize(26)
                  .fontColor([Color.White])
              }
              .width(52)
              .height(52)
              .borderRadius(26)
              .backgroundColor($r('app.color.primary'))
              .justifyContent(FlexAlign.Center)

              Column({ space: 2 }) {
                Text('CoachPal')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(this.aiLabel)
                  .fontSize(12)
                  .fontColor(this.aiOk ? $r('app.color.status_good') : $r('app.color.text_secondary'))
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
        }

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
