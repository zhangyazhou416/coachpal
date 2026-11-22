#!/usr/bin/env python3
"""批量生成卡通风格的训练动作示意图，替代 free-exercise-db 的照片。

数据源：vendor/exercises.json（876 个动作，含名称/器械/肌群/步骤）
输出：vendor/exercises_cartoon/<动作ID>/0.jpg（起始姿势）、1.jpg（发力姿势）

用法（项目根目录）：
  tools/.venv-sd/bin/python tools/gen_cartoon_images.py --limit 4   # 试跑 4 个动作
  tools/.venv-sd/bin/python tools/gen_cartoon_images.py             # 全量
  tools/.venv-sd/bin/python tools/gen_cartoon_images.py --ids Barbell_Squat,Pushups

特性：
- 断点续跑：两张图都已存在的动作自动跳过，中断后重跑即可
- 固定随机种子 + 统一风格后缀，保证 1752 张图风格一致
- 首次运行会从 HuggingFace 下载模型（约 4GB，默认走 hf-mirror 镜像）
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")  # 国内镜像

ROOT = Path(__file__).resolve().parent.parent
EXERCISES_JSON = ROOT / "vendor" / "exercises.json"
OUT_DIR = ROOT / "vendor" / "exercises_cartoon"

DEFAULT_MODEL = "stable-diffusion-v1-5/stable-diffusion-v1-5"
LOCAL_MODEL_DIR = ROOT / "vendor" / "sd-models" / "stable-diffusion-v1-5"
SEED = 20261119

# 统一风格：同一个人物形象 + 纯白背景 + 扁平插画，保证整套图一致
STYLE = (
    "flat cartoon illustration, fitness exercise demonstration guide, "
    "one athletic person in black tank top and blue shorts, thick clean outlines, "
    "simple vector art style, pure white background, full body visible, side view, "
    "clear exercise posture, instructional fitness poster"
)
NEGATIVE = (
    "photorealistic, photo, photograph, realistic skin, text, watermark, logo, "
    "signature, blurry, deformed hands, extra limbs, missing limbs, cropped body, "
    "dark background, cluttered background, multiple people"
)


def sentences(text: str) -> list[str]:
    return re.split(r"(?<=[.!?])\s+", (text or "").strip())


def clip(text: str, limit: int = 220) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    return text[:limit].rsplit(" ", 1)[0] if len(text) > limit else text


def build_prompts(item: dict) -> tuple[str, str]:
    """一个动作两个姿势的提示词：0 = 起始姿势，1 = 发力/顶峰姿势。"""
    equipment = (item.get("equipment") or "bodyweight").replace("body only", "bodyweight")
    muscles = ", ".join((item.get("primaryMuscles") or [])[:2]) or "full body"
    force = {"push": "pushing", "pull": "pulling"}.get(item.get("force"), "performing")
    base = (
        f"{STYLE} A person {force} the {item['name'].lower()} "
        f"using {equipment}, targeting {muscles}."
    )
    steps = [s for s in sentences(" ".join(item.get("instructions") or [])) if len(s) > 30]
    start_detail = clip(steps[0]) if steps else "starting position of the exercise"
    peak_detail = clip(steps[len(steps) // 2] if len(steps) > 2 else (steps[-1] if steps else ""))
    prompt0 = f"{base} Starting position: {start_detail}"
    prompt1 = f"{base} Contracted/peak position: {peak_detail}" if peak_detail else base
    return prompt0, prompt1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default_model = (
        str(LOCAL_MODEL_DIR)
        if (LOCAL_MODEL_DIR / "model_index.json").exists()
        else DEFAULT_MODEL
    )
    parser.add_argument("--model", default=default_model)
    parser.add_argument("--ids", help="仅生成这些动作 ID（逗号分隔）")
    parser.add_argument("--limit", type=int, help="最多处理多少个动作（试跑用）")
    parser.add_argument("--steps", type=int, default=24, help="采样步数")
    parser.add_argument("--guidance", type=float, default=7.0)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=640)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--overwrite", action="store_true", help="重新生成已存在的图片")
    args = parser.parse_args()

    if not EXERCISES_JSON.exists():
        print(f"找不到 {EXERCISES_JSON}", file=sys.stderr)
        return 2
    data = json.loads(EXERCISES_JSON.read_text(encoding="utf-8"))
    only_ids = set(filter(None, (args.ids or "").split(",")))
    if only_ids:
        data = [x for x in data if x["id"] in only_ids]
        missing = only_ids - {x["id"] for x in data}
        if missing:
            print(f"警告：未找到动作 ID：{', '.join(sorted(missing))}")
    todo = []
    for item in data:
        out = OUT_DIR / item["id"]
        if args.overwrite or not (out / "0.jpg").exists() or not (out / "1.jpg").exists():
            todo.append(item)
    if args.limit:
        todo = todo[: args.limit]
    total_images = sum(2 if args.overwrite else (2 - sum((OUT_DIR / x["id"] / f"{i}.jpg").exists() for i in (0, 1))) for x in todo)
    print(f"待生成：{len(todo)} 个动作 / {total_images} 张图（总库 {len(data)} 个动作）")
    if not todo:
        print("全部已生成，无需操作。")
        return 0

    import torch
    from diffusers import StableDiffusionPipeline

    if not torch.cuda.is_available():
        print("警告：CUDA 不可用，将用 CPU 生成（非常慢）", file=sys.stderr)
    use_fp16_variant = (Path(args.model) / "unet" / "diffusion_pytorch_model.fp16.safetensors").exists()
    pipe = StableDiffusionPipeline.from_pretrained(
        args.model,
        variant="fp16" if use_fp16_variant else None,
        torch_dtype=torch.float16,
        safety_checker=None,
        requires_safety_checker=False,
    )
    for enable in (
        lambda: pipe.enable_attention_slicing(),
        lambda: pipe.enable_vae_slicing(),
        lambda: pipe.vae.enable_slicing(),
        lambda: pipe.vae.enable_tiling(),
    ):
        try:
            enable()
        except Exception:
            pass  # 不同 diffusers 版本 API 位置不同，尽力开启省显存选项
    pipe.to("cuda" if torch.cuda.is_available() else "cpu")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    generator = torch.Generator(device).manual_seed(args.seed)

    started = time.time()
    done = skipped = 0
    try:
        for idx, item in enumerate(todo, 1):
            out = OUT_DIR / item["id"]
            out.mkdir(parents=True, exist_ok=True)
            prompts = build_prompts(item)
            for slot, prompt in enumerate(prompts):
                target = out / f"{slot}.jpg"
                if target.exists() and not args.overwrite:
                    skipped += 1
                    continue
                image = pipe(
                    prompt=prompt,
                    negative_prompt=NEGATIVE,
                    width=args.width,
                    height=args.height,
                    num_inference_steps=args.steps,
                    guidance_scale=args.guidance,
                    generator=generator,
                ).images[0]
                image.convert("RGB").save(target, "JPEG", quality=90)
                done += 1
            if idx % 10 == 0 or idx == len(todo):
                rate = done / max(time.time() - started, 1)
                remain = (total_images - done - skipped) / max(rate, 0.01)
                print(
                    f"[{idx}/{len(todo)}] {item['id']} 完成 · 已出图 {done} · "
                    f"{rate:.1f} 张/秒 · 预计剩余 {remain / 60:.0f} 分钟",
                    flush=True,
                )
    except KeyboardInterrupt:
        print("\n已中断。重新运行同一命令可从断点继续。")
    elapsed = time.time() - started
    print(f"结束：新生成 {done} 张，跳过 {skipped} 张，用时 {elapsed / 60:.1f} 分钟")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
