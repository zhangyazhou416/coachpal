<div align="center">

<img src="AppScope/resources/base/media/app_icon.png" width="120" alt="CoachPal"/>

# 练伴 CoachPal

**说话就能记录的健身与饮食助手**<br/>
*Just talk to log your training and meals.*

鸿蒙原生 · HarmonyOS Native · ArkTS / ArkUI · 本地优先 Local-first

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-Native-2A78D6?logo=harmonyos&logoColor=white)](#)
[![ArkTS](https://img.shields.io/badge/ArkTS-ArkUI-EB6834)](#)
[![License](https://img.shields.io/badge/Data-Personal%20Use%20Only-informational)](#-数据来源与许可--data--license)
[![Repo](https://img.shields.io/badge/GitHub-zhangyazhou416%2Fcoachpal-181717?logo=github&logoColor=white)](https://github.com/zhangyazhou416/coachpal)

[功能特性](#-功能特性--features) · [界面预览](#-界面预览--screenshots) · [快速开始](#-快速开始--quick-start) · [架构](#-架构--architecture) · [数据与许可](#-数据来源与许可--data--license)

</div>

---

## ✨ 功能特性 · Features

<table>
<tr><td width="50%" valign="top">

**🇨🇳 中文**

- **对话即记录**：说「今天体重 77.9，体脂 21.4」自动落库，无需表单
- **每日摄入目标**：按档案与体重算出热量 + 蛋白/脂肪/碳水/纤维（Mifflin-St Jeor → TDEE → 减脂 -15% / 增肌 +10%）
- **今日对比**：已吃 vs 目标，剩余热量与三大营养素余量、供能占比与合理性分析
- **目标与方案**：设目标体重/体脂，教练基于现状给出训练方案与进阶节奏
- **1677 条食物**：按《中国食物成分表（第 6 版）》自动算热量与宏量
- **1324 个动作**：内置动画 GIF + 中文分步要领，问「卧推怎么做」直接出示范
- **1RM 估算**、力量 PR、围度趋势、周复盘、明暗主题

</td><td width="50%" valign="top">

**🇬🇧 English**

- **Log by talking**: "Weighed 77.9 today, 21.4% body fat" — parsed and saved, no forms
- **Daily targets**: kcal + protein / fat / carbs / fiber computed from your profile & weight (Mifflin-St Jeor → TDEE → cut −15% / bulk +10%)
- **Today vs target**: remaining calories and macros, energy split and diet-quality feedback
- **Goals & plans**: set a target weight or body fat, get a training plan grounded in your history
- **1,677 foods** from the *China Food Composition Tables (6th ed.)*, macros computed automatically
- **1,324 exercises** with animated GIFs and step-by-step cues — ask "how do I bench press?"
- **1RM estimation**, strength PRs, measurement trends, weekly review, light/dark themes

</td></tr>
</table>

---

## 📱 界面预览 · Screenshots

<table>
<tr>
<td align="center"><img src="docs/screenshots/chat-qa.jpeg?v=2" width="240"/><br/><sub><b>教练问答 · Coach chat</b></sub></td>
<td align="center"><img src="docs/screenshots/chat.jpeg?v=2" width="240"/><br/><sub><b>欢迎卡 · Welcome</b></sub></td>
<td align="center"><img src="docs/screenshots/overview.jpeg?v=2" width="240"/><br/><sub><b>概览 · Overview</b></sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/trends.jpeg?v=2" width="240"/><br/><sub><b>趋势 · Trends</b></sub></td>
<td align="center"><img src="docs/screenshots/profile.jpeg?v=2" width="240"/><br/><sub><b>我的 · Profile</b></sub></td>
<td align="center"><img src="docs/screenshots/ai-config.jpeg?v=2" width="240"/><br/><sub><b>AI 服务 · AI setup</b></sub></td>
</tr>
</table>

---

## 🚀 快速开始 · Quick Start

**DevEco Studio（推荐 / recommended）** — 打开仓库根目录，等待 Sync 完成，连接设备或模拟器后 Run。
*Open the repo root in DevEco Studio, wait for Sync, then Run on a device or emulator.*

**命令行 / CLI**

```bash
bash build.sh               # 构建 HAP → entry/build/default/outputs/default/*.hap
                            # build HAP
bash build.sh test          # Hypium 单元测试 / unit tests

hdc install entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell aa start -b com.coachpal.app -a EntryAbility
```

> 需要本机安装 DevEco Studio。构建产物未签名，真机安装需在 DevEco 里配置自动签名。
> *Requires DevEco Studio. Builds are unsigned; configure automatic signing in DevEco for on-device installs.*

详细说明 / Details → [docs/HARMONYOS.md](docs/HARMONYOS.md)

---

## 🧠 架构 · Architecture

```text
仓库根目录即 DevEco 工程 / repo root IS the DevEco project
├── AppScope/                 应用配置与图标 / app manifest & icon
├── entry/src/main/ets/
│   ├── entryability/         入口 / ability
│   ├── pages/                Index · ChatPage · OverviewPage · TrendsPage · ProfilePage
│   │                         · AiConfigPage · ProfileEditPage
│   ├── components/           Card · LineChart · MdText(Markdown) · Dialogs
│   └── core/
│       ├── db/               SQLite DDL / Db / Seed / ChangeBus
│       ├── repo/             Repo —— 业务写入唯一入口 / single write path
│       ├── domain/           calc · food_search · set_parser（纯逻辑，可单测 / pure logic）
│       ├── coach/            CoachTools · ExerciseSkill（AI 工具层 / tool layer）
│       ├── net/              HTTP
│       └── settings/         Preferences + AssetStoreKit（API Key 加密）
└── tools/gen_icon.py         图标生成 / icon generator
```

**设计要点 / Design notes**

- **本地优先**：所有数据存本机 SQLite，不上传。Local-first — all data lives in on-device SQLite.
- **计算在代码里，模型只负责解读**：热量/宏量/1RM 由 `core/domain` 确定性计算，AI 不参与算术。
  *Math lives in code; the model only interprets — never computes.*
- **AI 双通道**：华为端侧模型（离线）或自定义 OpenAI/Anthropic 兼容接口，App 直连，不经服务器。
  *Dual AI backends: on-device model or any OpenAI/Anthropic-compatible endpoint, called directly from the app.*

---

## 📦 数据说明 · Data

- **食物 / Foods** — `foods.json`（1,677 条），`exercises.json`（1,324 个）内置
  `entry/src/main/resources/rawfile/`，首启由 `Seed.ets` 幂等导入 SQLite。
- **动作 GIF / Exercise media** — 约 123MB，位于 `rawfile/{videos,images}/`，**不入库**
  （`.gitignore`）。换机器时从上游 [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)
  重新拷贝。*~123MB of GIFs, not tracked by git; copy from the upstream dataset.*

---

## ⚖️ 数据来源与许可 · Data & License

| 数据 / Data | 来源 / Source | 许可 / License |
| --- | --- | --- |
| 食物营养 / Food nutrition | [Sanotsu/china-food-composition-data](https://github.com/Sanotsu/china-food-composition-data) | 原书为出版物，仅限个人使用 / personal use only |
| 动作库与动画 / Exercises & GIFs | [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset) | MIT（代码/数据），媒体 © [Gym visual](https://gymvisual.com/) |

> ⚠️ 食物成分数据整理自《中国食物成分表标准版（第 6 版）》，原书为出版物，上游未附开源许可。
> 动作动画媒体版权归 Gym visual 所有。**以上数据仅限本机个人使用，请勿再分发或公开发布。**
>
> *The food data derives from a published reference book and the exercise media is © Gym visual.
> Both are bundled for **personal, local use only — do not redistribute**.*

---

<div align="center">
<sub>

用 ArkTS / ArkUI 为 HarmonyOS 打造 · Built with ArkTS / ArkUI for HarmonyOS

[开源地址 / Repository](https://github.com/zhangyazhou416/coachpal)

</sub>
</div>
