# FitFuel 命令参考

所有命令都可以加全局参数：

```bash
python3 -m fitfuel [--json] [--db PATH] <命令> ...
```

- `--json`：输出 `{"ok": true, ...}` 或 `{"ok": false, "error": ..., "hints": [...]}`，退出码 0/2。
- `--db PATH`：使用指定数据库；默认 `data/fitfuel.db`。
- 日期：`YYYY-MM-DD`，也支持 `today`、`yesterday`、`MM-DD`；不传默认今天。
- 单位：kg / cm / g / kcal。

## 初始化与数据导入

```bash
python3 -m fitfuel init
python3 -m fitfuel seed
python3 -m fitfuel seed --foods-dir /path/to/china-food-composition-data
python3 -m fitfuel seed --exercises-dir /path/to/free-exercise-db
python3 -m fitfuel seed --skip-foods
python3 -m fitfuel seed --skip-exercises
```

`seed` 可重复执行，按食物编码/动作 ID 更新，不会清空个人记录。

## 个人档案

```bash
python3 -m fitfuel profile show
python3 -m fitfuel profile set --sex male --birth 1995-06-15 --height 178 --activity moderate --goal cut
```

- `--sex`：`male` / `female` / `other` / `男` / `女`
- `--activity`：`sedentary` / `light` / `moderate` / `active` / `very_active`，或 `久坐` / `轻度` / `中等` / `活跃` / `非常活跃`
- `--goal`：`cut` / `maintain` / `bulk`，或 `减脂` / `维持` / `增肌`

JSON：`profile` 对象，含 `age`、`bmi`、`latest_weight_kg`。

## 体重与体成分

```bash
python3 -m fitfuel weight add 77.9
python3 -m fitfuel weight add 77.9 --body-fat 21.4 --muscle 33.4 --date 2026-11-19
python3 -m fitfuel weight list --days 90
python3 -m fitfuel weight list --days 365 --limit 50
```

同一天重复记录会合并字段（只更新本次提供的项）。JSON：`metric` 或 `metrics`。

## 围度

```bash
python3 -m fitfuel measure add --chest 100 --waist 84 --hip 95 --arm 36
python3 -m fitfuel measure add --date 2026-11-19 --set thigh=58 --set calf=38
python3 -m fitfuel measure list --days 180
python3 -m fitfuel measure list --site waist
```

标准部位：`chest` 胸围、`waist` 腰围、`hip` 臀围、`neck` 颈围、`shoulder` 肩围、`arm` 上臂围、`forearm` 前臂围、`thigh` 大腿围、`calf` 小腿围、`wrist` 腕围。`--set` 支持任意中文/英文部位名。

同一天同一部位重复记录会覆盖。

## 目标

```bash
python3 -m fitfuel goal set weight 72 --date 2027-03-01
python3 -m fitfuel goal set body_fat 15
python3 -m fitfuel goal set muscle 36
python3 -m fitfuel goal set waist 80
python3 -m fitfuel goal set bench 100
python3 -m fitfuel goal list
python3 -m fitfuel goal list --all
```

指标（`kind`）支持：

- `weight` / 体重
- `body_fat` / 体脂率
- `muscle` / 骨骼肌量
- 任意围度部位（如 `waist` / 腰围）
- 力量动作（如 `bench` / 卧推、`squat` / 深蹲、`deadlift` / 硬拉、`ohp` / 肩推）

目标创建时会记录当时的基线值；如果创建时还没有数据，第一次记录会自动补上基线。

JSON：`goal` / `goals`，含 `progress`（0-1）、`achieved`、`baseline_value`、`current_value`。

## 力量与 1RM

```bash
python3 -m fitfuel strength add bench 80 5 --rpe 8
python3 -m fitfuel strength add 深蹲 100 5
python3 -m fitfuel strength add deadlift 120 3 --date 2026-11-19
python3 -m fitfuel strength list --days 180
python3 -m fitfuel strength list --lift bench
python3 -m fitfuel strength pr
python3 -m fitfuel strength calc 80 5
python3 -m fitfuel strength percentages bench
python3 -m fitfuel strength percentages bench --step 2.5
```

动作：`bench` 卧推、`squat` 深蹲、`deadlift` 硬拉、`ohp` 肩推、`row` 划船、`pullup` 引体向上、`dip` 双杠臂屈伸、`curl` 弯举；也可以写中文或自定义动作名。

JSON：`log` 含 `estimated_1rm`、`is_pr`、`previous_best`、`high_rep_warning`；`percentages` 含 `table`。

## 食物库

```bash
python3 -m fitfuel food search 鸡胸 --limit 10
python3 -m fitfuel food search 081324
python3 -m fitfuel food show 鸡胸脯肉
```

JSON：`foods` 数组或 `food` 对象。字段：`code`、`name`、`name_en`、`category`、`kcal_per_100g`、`protein_g`、`fat_g`、`carbs_g`、`fiber_g`、`gi`、`match_score`。

匹配规则：编码/完整名称精确命中优先；否则按相似度排序。多个候选分数接近时命令会报错并列出候选，必须让用户确认。

## 动作库

```bash
python3 -m fitfuel exercise search 卧推
python3 -m fitfuel exercise search 胸 杠铃
python3 -m fitfuel exercise show 高位下拉
python3 -m fitfuel exercise show 卧推 --open     # 在浏览器打开动画 GIF
```

动作库来自 exercises-dataset（1324 个动作，`seed` 自动导入，含动画 GIF 与中文说明）。搜索支持中文名、英文名、肌群（中文/英文）、器械、难度。JSON：`exercises` 数组或 `exercise` 对象；详情含 `instructions`（英文步骤）、`steps_zh`（中文步骤）、`images`（gif/thumb，按优先级排序）。

## 饮食记录

```bash
python3 -m fitfuel meal add --type 午餐 --item "鸡胸脯肉:150" --item "米饭（蒸，代表值）:200"
python3 -m fitfuel meal add --type breakfast --item "鸡蛋（代表值）:100"
python3 -m fitfuel meal add --type 加餐 --custom "蛋白粉:30:120:24:1.5:3"
python3 -m fitfuel meal add --type 加餐 --custom "自制奶昔:300:250:20:8:25:2"
python3 -m fitfuel meal list
python3 -m fitfuel meal list --date 2026-11-18
python3 -m fitfuel meal list --days 7
python3 -m fitfuel meal delete 12
```

- 餐次：`breakfast` / `lunch` / `dinner` / `snack`，或 `早餐` / `午餐` / `晚餐` / `加餐` / `练前` / `练后`。
- `--item 名称:克数`：来自食物库，名称可写编码。
- `--custom 名称:克数:热量:蛋白:脂肪:碳水[:纤维]`：食物库没有时使用，数值按这一份的总量填写。

JSON：`meal` 含 `items`（解析后的真实食物名、克数、热量、宏量）和 `totals`。

## 每日汇总

```bash
python3 -m fitfuel day
python3 -m fitfuel day --date 2026-11-18
```

JSON：`date`、`meals`、`totals`（kcal/protein/fat/carbs/fiber）、`targets`、`remaining`、`target_note`。

## 热量与宏量目标

```bash
python3 -m fitfuel targets
```

JSON：`targets.available`、`targets.targets`、`bmr`、`tdee`、`goal_type`、`assumptions`、`method`。

## 训练记录

```bash
python3 -m fitfuel workout add --name 推日 \
  --set "卧推 80 5 @8" --set "卧推 80 5 @8" \
  --set "高位下拉 60 10 @8" --set "侧平举 10 12"
python3 -m fitfuel workout add --date 2026-11-18 --set "深蹲 100 5 @8"
python3 -m fitfuel workout list --days 30
python3 -m fitfuel workout show 3
python3 -m fitfuel workout delete 3
```

`--set` 格式：`动作 重量 次数 [@RPE]`，也接受 `动作 80kg x 5 @8`。自重动作重量写 `0`。

JSON：`workout` 含 `sets`、`exercises`、`volume_kg`、`set_count`、`exercise_count`、`warnings`。

## 状态、复盘、看板

```bash
python3 -m fitfuel status
python3 -m fitfuel report --days 7
python3 -m fitfuel report --days 30
python3 -m fitfuel dashboard
python3 -m fitfuel dashboard --days 90 --open
```

- `status`：档案、最新体重/围度、今日饮食、目标、PR、最近训练。
- `report`：周期内饮食均值、体重/围度变化、训练次数/训练量、新 PR。
- `dashboard`：生成单文件 HTML；默认输出到数据库同目录的 `dashboard.html`。

JSON：`report` 含 `period`、`nutrition_average`、`weight_change`、`measurement_changes`、`workouts`、`new_prs`、`goals`。
