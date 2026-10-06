"""生成「行迹」App 图标（Android mipmap 全套 + 自适应图标）。

设计
----
「行迹」= 走过的路线。图形是**一条向上行进的轨迹**。

- 底：#FF8C42 → #F0653A 对角渐变（与 App 主题 primaryGradient 一致）
- 图：白色圆头笔画，从左下走到右上；起点半透明 = 出发，终点实心 = 现在
- 圆角方形；自适应图标另出一份前景（内容缩进到中间 66% 安全区）

⚠️ 踩坑记录（画这个图标改了四次，都是真实发生的问题）
--------------------------------------------------
1. `gradient()` 用 Python 双重循环逐像素写 1024² 太慢 → 改成小图放大插值
   （此版本已用 numpy，见下）。

2. 想做「渐变描边」，于是画 260 段**半透明**线段，透明度递增。
   失败：alpha 混合是 a + b(1-a)，重叠处不断累积，
   线条出现一圈圈鳞片状纹理。

3. 改成「实心线 + 沿首尾连线的线性渐变遮罩」。
   仍有纹理。原因：等值线垂直于首尾连线，而路径是弯的，
   等值线与笔画斜交 → 横向条纹。

4. 改成「逐段画、宽度渐细、全不透明」。**还是毛毛虫。**
   真正原因：`joint='curve'` 只在**一次多点的 line() 调用**里生效。
   逐段调用时每段都是**平头**（方形端帽），粗细又不同，
   相邻段的平头互相错开 → 看起来就是一圈圈鳞片。

最终版：**一次 line() 画完整条折线**（恒定宽度 + joint='curve'）
+ 两端补圆头。一笔画完，没有任何接缝。
"""
import io
import os

import numpy as np
from scipy.ndimage import distance_transform_edt
from PIL import Image, ImageDraw

OUT = r'C:\Users\沐瑾\Desktop\project\campus-run-app\android\app\src\main\res'
MASTER = 1024

GRAD_TOP = (255, 140, 66)     # #FF8C42
GRAD_BOTTOM = (240, 101, 58)  # #F0653A


def gradient(size: int) -> Image.Image:
    """对角渐变。用 numpy 向量化，1024² 是毫秒级。"""
    y, x = np.mgrid[0:size, 0:size]
    t = (x + y) / (2.0 * (size - 1))
    top = np.array(GRAD_TOP, dtype=np.float64).reshape(1, 1, 3)
    bot = np.array(GRAD_BOTTOM, dtype=np.float64).reshape(1, 1, 3)
    arr = top + (bot - top) * t[:, :, None]
    return Image.fromarray(arr.round().astype(np.uint8), 'RGB')


def path_points(size: int, samples: int = 200):
    """三次贝塞尔：从左下上行到右上，像一条真实走过的轨迹。"""
    p0, p1, p2, p3 = (0.245, 0.775), (0.335, 0.470), (0.640, 0.775), (0.760, 0.330)
    pts = []
    for i in range(samples + 1):
        t = i / samples
        u = 1 - t
        x = (u ** 3) * p0[0] + 3 * (u ** 2) * t * p1[0] + 3 * u * (t ** 2) * p2[0] + (t ** 3) * p3[0]
        y = (u ** 3) * p0[1] + 3 * (u ** 2) * t * p1[1] + 3 * u * (t ** 2) * p2[1] + (t ** 3) * p3[1]
        pts.append((x * size, y * size))
    return pts


def draw_glyph(img: Image.Image, size: int) -> Image.Image:
    """把轨迹画上去。

    ⚠️ 这里改了五次，前四次的失败原因都不同，值得记下来：

    1. 260 段**半透明**线段做渐变 → alpha 混合累积（a+b(1-a)），鳞片纹理。
    2. 实心线 + 沿首尾连线的线性渐变遮罩 → 等值线垂直于直线而路径是弯的，
       与笔画斜交 → 横向条纹。
    3. 逐段画、宽度渐细、全不透明 → `joint='curve'` 只在**一次多点调用**里
       生效；逐段调用得到方头端帽，错开就是毛毛虫。
    4. 一次 line() 画完整条 + joint='curve' → **仍然有纹理**。
       真正原因：200 个采样点在 4× 超采样下每段只有约 6px，
       而线宽有 107px，相邻段重叠极多；Pillow 对每段都做边缘抗锯齿，
       重叠处被反复混合 → 每 6px 一道纹。
       （"一次调用就没有接缝"这个假设是错的：joint='curve' 补的是
        拐角几何，补不了抗锯齿叠加。）

    最终版：**先画细骨架线，再用距离变换"膨胀"成笔画**。
      这样笔画边缘只由一次阈值化决定，与采样密度完全无关，
      也不依赖 Pillow 的线宽渲染，从根本上没有条纹。
    """
    ss = 4
    big = size * ss

    pts = path_points(big, samples=400)

    # ① 细骨架（1px）。采样密一点没关系，它只决定"中心线在哪"。
    skel = Image.new('L', (big, big), 0)
    ImageDraw.Draw(skel).line(pts, fill=255, width=1, joint='curve')

    # ② 距离变换 → 到骨架的距离场
    dist = distance_transform_edt(np.asarray(skel) == 0)

    # ③ 阈值化成笔画。半径用"沿路径渐细"：起点细、终点粗。
    #    直接用首尾连线做参数即可 —— 只影响宽度，不再有可见条纹。
    y, x = np.mgrid[0:big, 0:big]
    x0, y0 = pts[0]
    x1, y1 = pts[-1]
    vx, vy = x1 - x0, y1 - y0
    denom = vx * vx + vy * vy or 1.0
    t = ((x - x0) * vx + (y - y0) * vy) / denom
    t = np.clip(t, 0.0, 1.0)

    r_min = big * 0.045
    r_max = big * 0.056
    radius = r_min + (r_max - r_min) * t

    alpha = np.where(dist <= radius, 255.0, 0.0)

    # 边缘 1px 过渡，避免锯齿（距离场的天然产物，不会产生周期纹理）
    edge = np.clip(radius + 1.0 - dist, 0.0, 1.0)
    alpha = np.where(dist <= radius, 255.0, 255.0 * edge)
    alpha = np.clip(alpha, 0, 255).astype(np.uint8)

    # ④ 起点半透明（出发地），终点实心不处理（保持 255）
    start_r = r_min * 1.15
    d0 = np.hypot(x - x0, y - y0)
    fade = np.where(d0 <= start_r, 0.72, 1.0)
    alpha = np.clip(alpha.astype(np.float64) * fade, 0, 255).astype(np.uint8)

    layer = Image.new('RGBA', (big, big), (255, 255, 255, 0))
    layer.putalpha(Image.fromarray(alpha, 'L'))
    layer = layer.resize((size, size), Image.LANCZOS)
    return Image.alpha_composite(img.convert('RGBA'), layer)


def rounded(img: Image.Image, size: int, radius_ratio: float = 0.235) -> Image.Image:
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    base = draw_glyph(gradient(MASTER), MASTER)
    master = rounded(base, MASTER)

    # ① legacy mipmap：API 26 以下 / 部分启动器只读这个，
    #    两套都做对，否则会出现「新手机好看、旧手机一张糊图」。
    for dpi, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96,
                    'xxhdpi': 144, 'xxxhdpi': 192}.items():
        d = os.path.join(OUT, f'mipmap-{dpi}')
        os.makedirs(d, exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(d, 'ic_launcher.png'), 'PNG', optimize=True)
    print('  legacy mipmap: 48/72/96/144/192')

    # ② 自适应图标前景：系统会裁成各种形状，内容必须缩进到中间安全区，
    #    否则圆形图标下会把轨迹两端切掉。
    glyph = draw_glyph(Image.new('RGBA', (MASTER, MASTER), (0, 0, 0, 0)), MASTER)
    safe_ratio = 0.64
    inner = int(MASTER * safe_ratio)
    off = (MASTER - inner) // 2
    fg = Image.new('RGBA', (MASTER, MASTER), (0, 0, 0, 0))
    fg.paste(glyph.crop((off, off, off + inner, off + inner)), (off, off))
    for dpi, px in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216,
                    'xxhdpi': 324, 'xxxhdpi': 432}.items():
        d = os.path.join(OUT, f'mipmap-{dpi}')
        os.makedirs(d, exist_ok=True)
        fg.resize((px, px), Image.LANCZOS).save(
            os.path.join(d, 'ic_launcher_foreground.png'), 'PNG', optimize=True)
    print('  adaptive foreground: 108/162/216/324/432')

    # ③ 自适应图标背景色
    values = os.path.join(OUT, 'values')
    os.makedirs(values, exist_ok=True)
    with io.open(os.path.join(values, 'ic_launcher_background.xml'), 'w',
                 encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <color name="ic_launcher_background">#FF8C42</color>\n'
                '</resources>\n')
    print('  values/ic_launcher_background.xml')

    # ④ 预览图
    preview = os.path.join(os.environ['TEMP'], 'icon_preview.png')
    sheet = Image.new('RGB', (760, 300), (245, 245, 247))
    x = 30
    for px in (192, 144, 96, 48):
        thumb = master.resize((px, px), Image.LANCZOS)
        sheet.paste(thumb, (x, 50 + (192 - px) // 2), thumb)
        x += px + 32
    sheet.save(preview)
    print(f'  预览: {preview}')

    root = os.path.abspath(os.path.join(OUT, '..', '..', '..', '..'))
    master.save(os.path.join(root, 'icon_master_1024.png'))
    print(f'  主图: {os.path.join(root, "icon_master_1024.png")}')


if __name__ == '__main__':
    main()
