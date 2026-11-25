# CoachPal App（Flutter）

Android / iOS / Web / 鸿蒙 四端应用。架构与里程碑见 `docs/CROSS_PLATFORM_PLAN.md`。

## 首次搭建

```bash
# 0. 安装 Flutter stable（含 dart）；鸿蒙另需 OpenHarmony flutter_flutter 分支 + DevEco Studio

# 1. 从项目根导出资产（食物/动作 JSON）
python3 tools/export_app_assets.py

# 2. 生成平台工程目录（android/ios/web）
cd app
flutter create . --org com.coachpal --platforms=android,ios,web --project-name coachpal_app

# 3. Drift 代码生成
dart run build_runner build --delete-conflicting-outputs

# 4. 运行
flutter run -d chrome          # Web
flutter run -d <android设备>    # Android
```

## 鸿蒙

使用 OpenHarmony 官方 Flutter 分支：
```bash
git clone https://gitee.com/openharmony-sig/flutter_flutter.git
# 按该仓库 README 配置 ohos 工具链后：
flutter create . --platforms=ohos
flutter run -d <ohos设备>
```

## 同步

- 服务端：项目根 `server/`（FastAPI），启动后 App 内「我的」配置 baseUrl 并登录
- 协议：`docs/CROSS_PLATFORM_PLAN.md`（uuid + updated_at LWW + 墓碑）

## 状态

- [x] M2 数据层：Drift 表、资产导入、领域计算（calc.dart，与 Python 对拍）
- [ ] M3 UI：今日/趋势/我的已有骨架；记录（饮食/训练/围度/目标）、复盘页待开发
- [ ] M4 同步打通（sync_client.dart 已有协议实现，待接入 UI）
