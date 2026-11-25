# CoachPal App（鸿蒙原生 ArkTS/ArkUI）

HarmonyOS 原生应用（Stage 模型，DevEco Studio），对接项目根 `server/` 的同一套 FastAPI。
原 Flutter 客户端已删除；架构与同步协议见 `docs/CROSS_PLATFORM_PLAN.md`。

## 工程结构

```
app/
├── build.sh                       # CLI 构建/单测脚本（DevEco 自带 node/hvigor）
├── AppScope/app.json5             # bundleName com.coachpal.app
├── build-profile.json5
├── oh-package.json5
└── entry/
    ├── oh-package.json5           # devDependencies: @ohos/hypium（单测）
    └── src/
        ├── main/
        │   ├── module.json5       # INTERNET 权限、EntryAbility
        │   ├── ets/
        │   │   ├── entryability/EntryAbility.ets   # 启动 AppServices.init
        │   │   ├── pages/Index.ets                 # Tabs×4：教练/记录/趋势/我的
        │   │   ├── pages/ChatPage.ets              # Agent 对话 + 动作 GIF
        │   │   ├── pages/TrendsPage.ets            # 趋势 + 周复盘
        │   │   ├── pages/ProfilePage.ets           # 档案 + 同步 + 快捷体重
        │   │   ├── pages/record/RecordHub.ets      # 顶部三子页
        │   │   ├── pages/record/{Meal,Workout,Body}Page.ets
        │   │   ├── components/                     # Card/LineChart/对话框
        │   │   └── core/
        │   │       ├── db/        # Ddl/Db/Seed/ChangeBus（SQLite，schema 与同步协议对齐）
        │   │       ├── repo/      # Model/Repo（业务写入唯一入口）
        │   │       ├── domain/    # calc/food_search/set_parser（纯逻辑，LocalUnit 可测）
        │   │       ├── net/Http.ets
        │   │       ├── sync/SyncEngine.ets
        │   │       ├── settings/Settings.ets       # Preferences + AssetStoreKit(token)
        │   │       └── services.ets                # AppServices 单例
        │   └── resources/
        │       ├── base/element/ + dark/element/   # 明暗主题
        │       └── rawfile/{foods,exercises,meta}.json   # 种子资产
        └── test/                                   # Hypium LocalUnit（15 例）
```

## 构建

### DevEco Studio（推荐）

打开 `app/` 目录，等待 Sync 完成，连接设备/模拟器后 Run。

### 命令行

需要本机装好 DevEco Studio（含 SDK、node、hvigor、JBR），`build.sh` 按默认安装路径
（`/d/Program Files/Huawei/DevEco Studio`）引用它们，装在别处时改脚本头部两个变量：

```bash
bash app/build.sh           # assembleHap → entry/build/default/outputs/default/*.hap
bash app/build.sh test      # Hypium LocalUnit，结果见
                            # entry/.test/default/intermediates/test/coverage_data/test_result.txt
```

首次构建 hvigor 会拉 ohpm 依赖（registry `ohpm.openharmony.cn`）。构建产物未签名；
真机安装需在 DevEco `File > Project Structure > Signing Configs` 勾选自动签名
（需华为账号，证书文件不入库）。

安装运行：

```bash
hdc install entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell aa start -b com.coachpal.app -a EntryAbility
hdc hilog | grep -i coachpal
```

## 资产导出（食物/动作种子数据）

```bash
python3 tools/export_app_assets.py   # 根目录执行 → app/entry/src/main/resources/rawfile/
```

`foods.json`（约 1677 条）、`exercises.json`（约 1324 条）、`meta.json`（导出时间）。
首启由 `Seed.ets` 幂等导入 SQLite（计数为 0 才导入），`meta.exported_at` 存 Preferences
并在「我的」页展示。

## 同步

- 服务端：项目根 `server/`（FastAPI，默认端口 8321）：`uvicorn coachpal_server.main:app --host 0.0.0.0 --port 8321`
- App「我的」页：填服务器地址 + 访问密码 → 连接（token 存 AssetStoreKit）
- 「立即同步」手动双向同步；「启动自动同步」开启后每次冷启动后台同步一轮
- 协议：8 张业务表 `uuid + updated_at(UTC 秒) + deleted` 墓碑、双向 LWW，
  与服务端 `docs/CROSS_PLATFORM_PLAN.md` 定稿一致

## FAQ

- **模拟器连不上本机服务器**：地址用 PC 局域网 IP（`ipconfig` 查看），不是 `127.0.0.1`；
  Windows 防火墙需放行 8321 端口
- **LocalUnit 单测**：`bash app/build.sh test`；领域计算三文件禁止 import `@kit`，否则无法在宿主 JS 引擎运行
- **Actions GIF 加载失败**：GIF 由服务端 `/media/` 下发，确认服务器可达且已配置动作媒体
- **签名报错**：未配置签名；DevEco 自动签名生成一次即可（`*.p12/*.cer/*.p7b` 已 gitignore）
