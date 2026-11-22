# 数据来源与许可

本目录内嵌了 fitfuel 运行所需的 minimal 数据子集，`fitfuel seed` 会优先从这里读取。

## foods/ —— 中国食物成分数据

- 来源：[Sanotsu/china-food-composition-data](https://github.com/Sanotsu/china-food-composition-data)
  的 `json_data_v3_20260825_qwen38max_kimi_k3_fixed_en` 目录（能量已矫正版 + 英文名增强版）
- 内容：`merged_*.json` 60 个分类文件，共 1677 条食物；GI 表来自同仓库
  `json_gi_of_foods/glycemic_index_of_foods.json`
- 原始数据整理自《中国食物成分表标准版（第 6 版）》（北京大学出版社）
- **许可注意**：原书为出版物，该仓库未附开源许可。此处复制仅用于本机个人使用；
  请勿将本目录数据再分发或商用。

## exercises-dataset/ —— 动作库（动画 GIF + 多语言说明）

- 来源：[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)
  整仓复制（1324 个动作：卡通动画 GIF 126 MB + 180×180 缩略图 12 MB + 10 语言分步说明，中文全覆盖）
- 许可：代码与数据 MIT；**动画媒体 © Gym visual**（详见其 LICENSE/NOTICE），仅限本机个人使用，勿再分发媒体文件
- `seed` 由此导入整个动作库；`exercise show` 返回动画 GIF 路径与中文步骤。
- 历史注记：早期版本曾使用 free-exercise-db（公有领域，876 个动作 + 实拍图）作为动作库，
  已被本数据集取代并移除。
