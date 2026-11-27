#!/usr/bin/env python3
"""生成「练伴 CoachPal」应用图标：蓝橙渐变底 + 白色教练剪影。

造型：前展双肱二头肌（Front Double Biceps）——上臂抬高外展、二头肌隆起、
前臂垂直握拳。几何刻意简化：桌面图标尺寸小，靠大块面而非细节保证可读。

用法：python3 tools/gen_icon.py
输出：AppScope 与 entry 两处 app_icon.png（512x512）。
"""
from PIL import Image, ImageDraw

S = 512
C1 = (42, 120, 214)   # primary 蓝
C2 = (235, 104, 52)   # accent 橙
W = (255, 255, 255, 255)

# ---------------------------------------------------------------- 渐变底
img = Image.new('RGBA', (S, S))
d = ImageDraw.Draw(img)
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        d.point((x, y), fill=(
            int(C1[0] + (C2[0] - C1[0]) * t),
            int(C1[1] + (C2[1] - C1[1]) * t),
            int(C1[2] + (C2[2] - C1[2]) * t),
        ))

ov = Image.new('RGBA', (S, S), (0, 0, 0, 0))
o = ImageDraw.Draw(ov)
MX = 256

# ---------------------------------------------------------------- 头 / 脖
o.ellipse([MX - 35, 66, MX + 35, 140], fill=W)
o.rectangle([MX - 19, 130, MX + 19, 200], fill=W)

# ---------------------------------------------------------------- 躯干：宽肩收腰
o.polygon([(MX - 104, 194), (MX + 104, 194),
           (MX + 76, 318), (MX - 76, 318)], fill=W)
# 肩头圆角（与上臂融合，形成腋窝）
o.ellipse([MX - 128, 166, MX - 80, 218], fill=W)
o.ellipse([MX + 80, 166, MX + 128, 218], fill=W)

# ---------------------------------------------------------------- 双臂
ARM_Y = 180          # 上臂中心线（高于躯干顶 196，腋窝自然形成）
for side in (-1, 1):
    sx = MX + side * 96      # 肩
    ex = MX + side * 174     # 肘
    # 上臂：水平外展，粗
    o.line([(sx, ARM_Y), (ex, ARM_Y)], fill=W, width=54)
    # 肱二头肌峰：肘内侧上方隆起
    bx = MX + side * 142
    o.ellipse([bx - 40, 136, bx + 40, 212], fill=W)
    # 前臂：垂直向上
    o.line([(ex, ARM_Y), (ex, 94)], fill=W, width=44)
    # 拳
    o.ellipse([ex - 26, 48, ex + 26, 100], fill=W)

# ---------------------------------------------------------------- 腿
o.line([(MX - 38, 310), (MX - 62, 404)], fill=W, width=62)
o.line([(MX + 38, 310), (MX + 62, 404)], fill=W, width=62)
# 脚
o.rounded_rectangle([MX - 104, 392, MX - 18, 428], radius=15, fill=W)
o.rounded_rectangle([MX + 18, 392, MX + 104, 428], radius=15, fill=W)

img = Image.alpha_composite(img, ov).convert('RGB')
img.save('AppScope/resources/base/media/app_icon.png')
img.save('entry/src/main/resources/base/media/app_icon.png')
print('icon ok ->', S, 'x', S)
