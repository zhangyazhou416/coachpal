# CoachPal 跨平台架构方案（定稿）

> 2026-11-22 确立。目标：Web + Android + iOS + 鸿蒙（HarmonyOS）四端，
> Flutter 框架，本地优先 + 自建同步服务，全功能对齐现有 CLI 后上线。

## 总体架构

```text
┌─────────────────────────────────────────────┐
│                Flutter App（一套代码）          │
│  Android / iOS / Web / 鸿蒙(OHOS 分支)        │
│  ┌────────────┐  ┌──────────────────────┐   │
│  │ Drift 本地库 │  │ 领域计算（Dart 移植）    │   │
│  │ 离线可用     │  │ 1RM/BMR/宏量/搜索评分    │   │
│  └─────┬──────┘  └──────────┬───────────┘   │
│        │     ┌──────────────┘               │
│        ▼     ▼                              │
│   ┌──────────────┐   资产：食物1677/动作1324   │
│   │  同步客户端    │   JSON 内置，GIF 按需缓存   │
└───┴──────┬───────┴──────────────────────────┘
           │ HTTPS (token)
┌──────────▼──────────────────────────────────┐
│      server/ · FastAPI 同步服务（个人自部署）      │
│  复用 coachpal Python 包的全部领域计算             │
│  SQLite + uuid/updated_at/墓碑，LWW 合并        │
└─────────────────────────────────────────────┘
```

## 决策记录

| 决策 | 结论 | 理由 |
|---|---|---|
| 跨端框架 | Flutter | 四端中三端官方支持；鸿蒙走华为官方 flutter_flutter OHOS 分支；参考项目 free-fitness 即 Flutter |
| 数据架构 | 本地优先 + 同步 | 无网可用（延续现有体验）；自部署轻服务实现多端同步；健康数据不出自控服务器 |
| 节奏 | 全功能对齐再上端 | 先把 CLI 全部功能搬进 Flutter，再打平台包 |
| 现有 CLI/Skill | 保留 | CLI + Skill 继续可用；其逻辑成为 server 的领域层 |

## 里程碑

- **M0 架构与骨架**（本仓库已建）：monorepo 布局、同步协议定稿、server 骨架、app 数据层骨架
- **M1 同步服务完整**：server/ 全部领域 API + 同步 pull/push + 测试（复用 coachpal 包计算）
- **M2 App 数据层**：Drift 表结构、资产导入（食物/动作/缩略图）、Dart 领域计算全量移植 + 单测
- **M3 App 全功能 UI**：今日/体重体脂/围度/目标/饮食/训练/趋势/复盘 8 组页面，对齐 CLI 功能
- **M4 同步打通**：登录、pull/push、冲突 LWW、GIF 按需缓存
- **M5 四端打包**：Android APK、iOS、Web（`flutter run -d chrome`）、鸿蒙（OHOS 分支构建）

## 目录布局（monorepo）

```text
coachpal/
├── coachpal/          # Python 领域核心（现状保留；server 复用其计算）
├── server/           # FastAPI 同步服务（M1）
│   ├── coachpal_server/
│   │   ├── main.py       # FastAPI 入口 + 静态媒体路由（动作 GIF/缩略图）
│   │   ├── config.py     # 数据目录/端口/密码引导
│   │   ├── db.py         # 服务端库：coachpal schema + 同步列（uuid/updated_at/deleted）
│   │   ├── auth.py       # 密码 → token（个人自部署，单主用户）
│   │   ├── stamp.py      # uuid/updated_at 盖章 + 墓碑
│   │   └── routers/      # auth/profile/body/goals/strength/foods/meals/workouts/reports/sync/exercises
│   └── tests/
├── app/              # Flutter（M2–M5）
│   ├── pubspec.yaml
│   ├── assets/data/      # 导出的食物/动作 JSON + 缩略图清单（tools/export_app_assets.py 生成）
│   └── lib/
│       ├── core/db/      # Drift 表 + DAO
│       ├── core/domain/  # Dart 移植的计算（与 coachpal.py 对拍单测）
│       ├── core/theme/   # 与网页看板一致的配色
│       ├── features/     # today/weight/measure/goal/meal/workout/trends/report/profile
│       └── sync/         # 同步客户端
├── skill/            # Claude Code skill（现状保留）
└── docs/             # 本文档
```

## 同步协议（定稿）

- **标识**：每行 `uuid`（客户端生成 UUIDv4），`updated_at`（UTC ISO），`deleted`（墓碑 0/1）
- **拉取**：`POST /api/sync/pull {"since": "2026-01-01T00:00:00", "tables": [...]}` →
  各表 changed rows（含墓碑）+ 服务端当前时间；客户端按 `updated_at` 应用
- **推送**：`POST /api/sync/push {"body_metrics": [rows...]}` → 服务端逐行 LWW
  （仅当远端 `updated_at` 更新才覆盖），返回每行接受结果
- **冲突**：Last-Write-Wins（毫秒级同刻时服务端赢）；记录型数据（体重/饮食）无合并需求
- **删除**：客户端软删（deleted=1 + updated_at）后推送；服务端硬删并记墓碑表；
  拉取方收到墓碑后本地硬删
- **参考数据**（食物/动作/GI）：不参与同步。版本号 `/api/meta` 下发，App 资产版本低时提示更新
- **媒体**：动作 GIF/缩略图由服务端 `/media/` 提供（App 内置缩略图，GIF 按需拉取并缓存）

## 平台注意

- **鸿蒙**：使用 OpenHarmony 官方 Flutter 分支（`flutter_flutter` ohos 分支）+ DevEco Studio；
  业务代码不写平台分支，平台差异收敛在依赖插件层
- **Web**：Drift 用 wasm/sql.js 实现；GIF 与图表无障碍；CORS 在 server 配置
- **iOS**：TestFlight 分发；健康数据不上 iCloud，仅自建同步
- **安全**：全站 HTTPS（自部署用 Caddy 反代）；token 存安全存储（flutter_secure_storage）
