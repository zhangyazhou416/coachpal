---
name: coachpal
description: 本地健身与饮食记录助手。当用户要记录或查询体重、体脂、骨骼肌、围度、1RM/力量训练、每日饮食与热量、训练计划，或做周复盘时使用；也用于按中国食物成分表查营养、按目标计算热量与宏量、生成本地网页看板。触发词：coachpal、记录体重、围度、吃了什么、热量、蛋白质、1RM、卧推、深蹲、硬拉、训练记录、减脂、增肌、复盘、饮食计划。
---

# CoachPal · 健身与饮食记录

CoachPal 是一个本地优先的个人健身/饮食数据库。数据在项目根目录的 `data/coachpal.db`（SQLite），食物营养来自《中国食物成分表（第 6 版）》，动作来自 free-exercise-db。所有记录都通过 `coachpal` CLI 写入，**不要直接改数据库**。

## 工作方式

在项目根目录运行命令，并始终加 `--json` 便于可靠解析：

```bash
python3 -m coachpal --json <命令>
```

如果已执行过 `pip install -e .`，也可以用 `coachpal --json ...`。命令输出是 `{"ok": true, ...}`；失败时 `{"ok": false, "error": "...", "hints": [...]}`，退出码 2。

**每次会话第一次操作前**，先运行：

```bash
python3 -m coachpal --json status
```

如果 food/exercise 库为空，运行一次：

```bash
python3 -m coachpal seed
```

## 必须遵守

1. **不要编造营养数据。** 食物必须来自食物库（`food search` / `meal add --item`）或用户明确给出的自定义值（`meal add --custom`）。查不到就告诉用户，并询问是否用包装上的营养表手动录入。
2. **食物匹配有歧义时必须让用户确认。** 例如 `鸡胸肉` 可能匹配到 `鸡胸脯肉`、火鸡胸脯肉；命令会返回候选与编码。把候选列给用户，确认后用完整名称或编码重试。不要默认选第一个。
3. **单位固定：** 体重/负重 kg，围度 cm，食物克数 g，热量 kcal，宏量 g。
4. **体重/围度是敏感数据。** 不复述给无关的人，不写入外部服务；只在本机使用。
5. **医疗边界：** 不做疾病诊断、不设计伤病康复、不给药物/激素/极端节食方案。出现胸痛、晕厥、持续加重的疼痛、麻木无力、进食障碍迹象时，停止给训练/热量建议并建议就医或找注册营养师。减脂目标低于 1200/1500 kcal 时提示风险（工具也会自动限制下限）。
6. **写操作前确认关键数字。** 用户口述含糊时（"吃了点米饭"）先问克数或给出常见份量假设，并明确标注是估算。

## 常见意图 → 命令

### 建档与目标

```bash
# 身高/性别/生日/活动水平/目标（减脂 cut、维持 maintain、增肌 bulk）
python3 -m coachpal --json profile set --sex male --birth 1995-06-15 --height 178 --activity moderate --goal cut
python3 -m coachpal --json profile show

# 体重 + 体脂率 + 骨骼肌量（同一天可一次写）
python3 -m coachpal --json weight add 77.9 --body-fat 21.4 --muscle 33.4 --date 2026-11-19
python3 -m coachpal --json weight list --days 90

# 围度（可只写部分部位；--set 可写任意部位）
python3 -m coachpal --json measure add --chest 100 --waist 84 --hip 95 --arm 36 --set thigh=58
python3 -m coachpal --json measure list --days 180

# 目标：weight / body_fat / muscle / 围度部位 / 力量动作
python3 -m coachpal --json goal set weight 72 --date 2027-03-01
python3 -m coachpal --json goal set waist 80
python3 -m coachpal --json goal set bench 100
python3 -m coachpal --json goal list
```

### 食物与饮食

```bash
python3 -m coachpal --json food search 鸡胸 --limit 10
python3 -m coachpal --json food show 鸡胸脯肉

# 一餐可多个条目；食物名可用编码代替
python3 -m coachpal --json meal add --type 午餐 \
  --item "鸡胸脯肉:150" --item "米饭（蒸，代表值）:200" --item "西兰花:100"

# 食物库没有时，用包装营养表手动录入：
# 名称:克数:热量:蛋白:脂肪:碳水[:纤维]
python3 -m coachpal --json meal add --type 加餐 --custom "蛋白粉:30:120:24:1.5:3"

python3 -m coachpal --json day                 # 今日汇总 + 目标 + 剩余
python3 -m coachpal --json day --date 2026-11-18
python3 -m coachpal --json meal list --days 7
python3 -m coachpal --json meal delete 12
```

`meal add` 返回解析后的**真实食物名**和这一餐的 totals。把食物名复述给用户，避免"我记的是鸡胸肉，实际记成了火鸡胸脯肉"。

### 力量与训练

```bash
# 记录一组，自动估算 1RM（Epley + Brzycki）
python3 -m coachpal --json strength add bench 80 5 --rpe 8
python3 -m coachpal --json strength add squat 100 5 --rpe 8
python3 -m coachpal --json strength pr
python3 -m coachpal --json strength percentages bench   # 按 1RM 生成 50%-100% 重量表
python3 -m coachpal --json strength calc 80 5           # 只算不存

# 一次训练多组；格式：动作 重量 次数 [@RPE]
python3 -m coachpal --json workout add --name 推日 \
  --set "卧推 80 5 @8" --set "卧推 80 5 @8" \
  --set "高位下拉 60 10 @8" --set "侧平举 10 12"
python3 -m coachpal --json workout list --days 30
python3 -m coachpal --json workout show 3
```

动作名支持中文别名（卧推/深蹲/硬拉/肩推/划船/引体向上/高位下拉/腿举/侧平举等），也支持英文名或动作 ID。动作库没有的名称会按自定义动作记录并返回 `warnings`，转告用户。

### 复盘与看板

```bash
python3 -m coachpal --json report --days 7      # 周复盘：饮食均值、体重/围度变化、训练量、新 PR
python3 -m coachpal --json report --days 30
python3 -m coachpal --json targets              # 热量与宏量目标
python3 -m coachpal --json dashboard --days 90  # 生成 data/dashboard.html
```

看板是单文件 HTML，可离线打开，支持 30/90/365/全部范围切换、深色模式、悬浮提示和数据表。

## 回答风格

- 默认中文，先给结论/数字，再给依据。
- 饮食：列出解析后的食物名、克数、热量与三大宏量；给出今日 totals、目标、剩余。
- 训练：给出动作、组数、次数、重量、总训练量；有新 PR 时明确祝贺但别夸张。
- 复盘：只讲 1-2 个最重要的信号（如热量缺口不足、蛋白质偏低、训练量下降、体重趋势），再给一个下周可执行动作。
- 不要一次抛 20 条建议；不要制造焦虑；不要用"你必须"。
- 用户只问知识（如"西兰花有什么营养"）时可以直接用食物库查，不必写记录。

## 失败时的处理

- `ok: false`：把 `error` 原样告诉用户，从 `hints` 里挑一条可执行的下一步。
- 食物/动作歧义：展示前 3-5 个候选（名称 + 编码/英文名 + 热量或器械），等用户选。
- 缺少身高/体重导致目标无法计算：先补 `profile set` 和 `weight add`。
- 命令不存在：运行 `python3 -m coachpal --help` 或读 `references/commands.md`。

## 深入参考

- `references/commands.md` — 全部命令、参数与 JSON 字段
- `references/calculations.md` — BMR/TDEE、宏量、1RM 公式与假设
- `references/workflows.md` — 首次建档、饮食记录、周复盘、减脂/增肌的完整流程
