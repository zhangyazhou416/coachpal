# CoachPal

健身与饮食记录工具：**鸿蒙原生 App**（仓库根目录即 DevEco 工程）+ FastAPI 服务端（同步 / AI 教练）+ 本地 CLI + 自包含网页看板。

- 记录身高、体重、体脂率、骨骼肌量、围度
- 记录力量训练（自动估算 1RM）和每次训练的动作/组数/重量/次数
- 记录每日饮食，按《中国食物成分表（第 6 版）》自动计算热量与宏量
- 管理减脂/增肌/围度/力量目标，并跟踪进度
- 生成可离线打开的 HTML 看板（深浅色、悬浮提示、数据表、时间范围切换）
- 数据全部保存在本机，不上传

## 快速开始

```bash
cd /home/zhangyazhou/Desktop/fitness/coachpal

# 1. 初始化并导入食物库、动作库（默认读取同级的两个数据仓库）
python3 -m coachpal init
python3 -m coachpal seed

# 2. 建档
python3 -m coachpal profile set --sex male --height 178 --birth 1995-06-15 --activity moderate --goal cut

# 3. 记录
python3 -m coachpal weight add 77.9 --body-fat 21.4 --muscle 33.4
python3 -m coachpal measure add --chest 100 --waist 84 --hip 95 --arm 36
python3 -m coachpal goal set weight 72 --date 2027-03-01
python3 -m coachpal meal add --type 午餐 --item "鸡胸脯肉:150" --item "米饭（蒸，代表值）:200"
python3 -m coachpal strength add bench 80 5 --rpe 8
python3 -m coachpal workout add --name 推日 --set "卧推 80 5 @8" --set "高位下拉 60 10 @8"

# 4. 查看
python3 -m coachpal day
python3 -m coachpal status
python3 -m coachpal report --days 7
python3 -m coachpal dashboard --days 90
```

看板生成在 `data/dashboard.html`，直接双击即可打开。

## 作为 Claude Code Skill 使用

Skill 源文件在 `skill/coachpal/`。安装到项目或用户目录：

```bash
./install_skill.sh                 # 项目级：./.claude/skills/coachpal
./install_skill.sh ~/.claude/skills # 用户级：所有项目可用
```

如果当前环境不允许写入 `.claude/`，请手动执行上面的命令，或把 `skill/coachpal/` 目录复制到 `.claude/skills/coachpal`。

安装后在项目里启动 Claude Code，可以直接说：

- "记一下，今天体重 77.9，体脂 21.4%"
- "午饭吃了 150g 鸡胸肉和 200g 米饭"
- "卧推 80kg 做了 5 次，RPE 8"
- "这周复盘一下"
- "帮我看看今天的热量和蛋白质还差多少"

Skill 会调用 `python3 -m coachpal --json ...`，把结果整理后回复。所有数据仍在本地。

## 数据来源与致谢

本项目使用了以下两个开源仓库的数据，特此说明与致谢：

1. **[Sanotsu/china-food-composition-data](https://github.com/Sanotsu/china-food-composition-data)**
   —— 中国食物成分数据，整理自《中国食物成分表标准版（第 6 版）》。
   本项目取其 1677 条食物结构化数据与 GI（血糖指数）表，内嵌于 [`vendor/foods/`](vendor/foods/)。
2. **[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)**
   —— 动作库数据集，共 **1324 个动作**，每个带卡通动画 GIF、缩略图和 10 语言分步说明（中文全覆盖）。
   整仓内嵌于 [`vendor/exercises-dataset/`](vendor/exercises-dataset/)。

数据已内嵌在 [vendor/](vendor/)，`coachpal seed` 优先从这里读取，项目自包含。

> **⚠️ 许可提示**：食物成分数据原书为出版物，上游仓库未附开源许可；exercises-dataset 的
> 代码与数据文件为 MIT，但动画媒体 © [Gym visual](https://gymvisual.com/)。
> 因此 `vendor/` 内数据**仅限本机个人使用，请勿再分发或公开发布**。详见 [vendor/SOURCES.md](vendor/SOURCES.md)。

动作库以 exercises-dataset 为唯一来源：`seed` 导入全部 1324 个动作（含 GIF 路径与中文步骤），
并自动清理旧版 free-exercise-db 的遗留动作行（训练历史的动作名文本保留）。
`exercise show <动作>` 返回动画路径与中文步骤，`--open` 可在浏览器播放。

数据集在别处或想用更新版本时，可显式指定：

```bash
python3 -m coachpal seed --foods-dir /path/to/china-food-composition-data \
                        --exercises-dir /path/to/exercises-dataset
```

## 常用命令

```bash
python3 -m coachpal --help
python3 -m coachpal <命令> --help
```

完整命令与 JSON 字段见 `.claude/skills/coachpal/references/commands.md`。

## 项目结构

```text
coachpal/
├── build.sh            # 鸿蒙 HAP 构建/单测（仓库根即 DevEco 工程）
├── AppScope/ + entry/  # HarmonyOS 原生应用（ArkTS/ArkUI，见 docs/HARMONYOS.md）
├── server/             # FastAPI 服务端：账号登录、数据同步、AI 教练
├── coachpal/           # Python CLI
│   ├── cli.py          # 命令行入口
│   ├── db.py           # SQLite 表结构
│   ├── body.py         # 档案、体重体成分、围度、目标
│   ├── nutrition.py    # 食物库导入、检索、饮食记录、热量目标
│   ├── exercises.py    # 动作库导入、中文别名、检索
│   ├── strength.py     # 1RM 估算与力量记录
│   ├── workouts.py     # 训练记录与训练量
│   ├── report.py       # 状态、周报、看板数据
│   ├── dashboard.py    # 自包含 HTML 看板
│   └── paths.py        # 数据路径（vendor/ 优先）
├── vendor/             # 内嵌数据：食物成分 + GI + 动作库（见 SOURCES.md）
├── skill/coachpal/      # Claude Code skill 源（./install_skill.sh 安装）
├── tests/
└── data/               # 运行时生成（已 gitignore）
```

## 算法与边界

- BMR：Mifflin-St Jeor；TDEE：活动系数；减脂 -15%，增肌 +10%
- 蛋白质：减脂 2.0 g/kg，维持 1.6 g/kg，增肌 1.8 g/kg
- 1RM：Epley 与 Brzycki 平均（≤12 次），高次数只用 Epley，误差更大
- 热量目标有安全下限（男 1500 / 女 1200 kcal），低于时自动抬高并提示
- 估算值仅供训练与饮食参考，不构成医疗或营养处方

## 测试

```bash
python3 -m pytest -q
```
