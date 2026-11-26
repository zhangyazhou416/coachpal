# CoachPal App（鸿蒙原生 ArkTS/ArkUI）

HarmonyOS 原生应用（Stage 模型，DevEco Studio），**工程就在仓库根目录**（DevEco 直接打开仓库根）。
无服务端依赖：数据全部本地（SQLite + rawfile），AI 由 App 直连模型接口。

## 工程结构

```
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
        │   │   ├── pages/AiConfigPage.ets          # AI 来源配置（华为端侧 / 自定义接口）
        │   │   ├── pages/ProfileEditPage.ets       # 档案编辑
        │   │   ├── pages/TrendsPage.ets            # 趋势 + 周复盘
        │   │   ├── pages/ProfilePage.ets           # 档案 + 快捷体重
        │   │   ├── pages/record/RecordHub.ets      # 顶部三子页
        │   │   ├── pages/record/{Meal,Workout,Body}Page.ets
        │   │   ├── components/                     # Card/LineChart/对话框
        │   │   └── core/
        │   │       ├── db/        # Ddl/Db/Seed/ChangeBus（SQLite，12 表）
        │   │       ├── repo/      # Model/Repo（业务写入唯一入口）
        │   │       ├── domain/    # calc/food_search/set_parser（纯逻辑，LocalUnit 可测）
        │   │       ├── net/Http.ets
        │   │       ├── settings/Settings.ets       # Preferences + AssetStoreKit(token)
        │   │       └── services.ets                # AppServices 单例
        │   └── resources/
        │       ├── base/element/ + dark/element/   # 明暗主题
        │       └── rawfile/{foods,exercises,meta}.json   # 种子资产（1677 食物 / 1324 动作）
        └── test/                                   # Hypium LocalUnit（15 例）
```

## 构建

### DevEco Studio（推荐）

打开仓库根目录，等待 Sync 完成，连接设备/模拟器后 Run。

### 命令行

需要本机装好 DevEco Studio（含 SDK、node、hvigor、JBR），`build.sh` 按默认安装路径
（`/d/Program Files/Huawei/DevEco Studio`）引用它们，装在别处时改脚本头部两个变量：

```bash
bash build.sh               # assembleHap → entry/build/default/outputs/default/*.hap
bash build.sh test          # Hypium LocalUnit，结果见
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

## 资产数据（食物/动作种子）

`foods.json`（1677 条）、`exercises.json`（1324 个）内置 `entry/src/main/resources/rawfile/`，
首启由 `Seed.ets` 幂等导入 SQLite（计数为 0 才导入）。
动画 GIF（`rawfile/videos/` + `rawfile/images/`，约 123MB）同样在 rawfile 下，**不入库**，
换机器时从上游 exercises-dataset 仓库拷贝。

## AI 配置

App「AI 配置」页（AiConfigPage）选择模型来源，App 直连接口、不经服务器：

- **华为端侧模型**：设备端推理（需设备支持）
- **自定义接口**：OpenAI 兼容网关（网关地址 / API Key / 模型名），如 `https://uni-api.cstcloud.cn` + `qwen3.5`

教练页（ChatPage）把用户意图本地解析（`core/coach/`：动作查询、记体重、记训练等工具），
再调 LLM 生成回复；动作示范 GIF 从本地 rawfile 播放。

## FAQ

- **LocalUnit 单测**：`bash build.sh test`；领域计算三文件禁止 import `@kit`，否则无法在宿主 JS 引擎运行
- **动作 GIF 加载失败**：GIF 在本地 `rawfile/videos/`，确认目录存在且已装含资源的 HAP
- **AI 对话报错**：检查「AI 配置」页的网关地址 / API Key / 模型名；自定义接口需为 OpenAI 兼容
- **签名报错**：未配置签名；DevEco 自动签名生成一次即可（`*.p12/*.cer/*.p7b` 已 gitignore）
