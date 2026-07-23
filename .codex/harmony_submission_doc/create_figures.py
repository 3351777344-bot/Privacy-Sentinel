from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUT = Path(r"E:\GuardianHub\.codex\harmony_submission_doc\figures")
OUT.mkdir(parents=True, exist_ok=True)

FONT_REGULAR = r"C:\Windows\Fonts\msyh.ttc"
FONT_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"

NAVY = "#13233E"
BLUE = "#2764E7"
CYAN = "#16A6C9"
GREEN = "#2E9F6B"
ORANGE = "#E98B2A"
RED = "#D94C4C"
INK = "#1C2738"
MUTED = "#617089"
PAPER = "#F5F8FC"
WHITE = "#FFFFFF"
LINE = "#DCE4F0"


def font(size: int, bold: bool = False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size=size)


def rounded_box(draw, xy, fill, outline=LINE, radius=24, width=3):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def centered_text(draw, box, text, fill=INK, size=36, bold=False, spacing=8):
    x0, y0, x1, y1 = box
    f = font(size, bold)
    lines = text.split("\n")
    heights = [draw.textbbox((0, 0), line, font=f)[3] for line in lines]
    total = sum(heights) + spacing * (len(lines) - 1)
    y = y0 + (y1 - y0 - total) / 2
    for line, h in zip(lines, heights):
        bbox = draw.textbbox((0, 0), line, font=f)
        w = bbox[2] - bbox[0]
        draw.text((x0 + (x1 - x0 - w) / 2, y), line, font=f, fill=fill)
        y += h + spacing


def arrow(draw, start, end, color=BLUE, width=8, head=18):
    draw.line([start, end], fill=color, width=width)
    x2, y2 = end
    x1, y1 = start
    dx, dy = x2 - x1, y2 - y1
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    p1 = (x2 - head * ux + head * 0.65 * px, y2 - head * uy + head * 0.65 * py)
    p2 = (x2 - head * ux - head * 0.65 * px, y2 - head * uy - head * 0.65 * py)
    draw.polygon([end, p1, p2], fill=color)


def title(draw, text, subtitle, width):
    draw.text((80, 54), text, font=font(52, True), fill=NAVY)
    draw.text((80, 122), subtitle, font=font(26), fill=MUTED)
    draw.line([(80, 174), (width - 80, 174)], fill=LINE, width=3)


def create_user_flow():
    w, h = 1800, 1080
    img = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(img)
    title(d, "GuardianHub 用户流程", "把风险检查前置到分享、提交、点击与上传之前", w)

    labels = [
        ("分享图片前", "Privacy Sentinel\n选图 → 识别 → 脱敏", RED),
        ("提交代码前", "Code Guardian\n选 ZIP → 扫描 → 修复建议", ORANGE),
        ("点击链接前", "Link Guard\n输入/二维码 → 静态体检", BLUE),
        ("上传材料前", "Doc Shield\n多选文件 → 完整性检查", GREEN),
    ]
    start_x, gap, card_w, card_h = 80, 30, 387, 210
    y = 230
    centers = []
    for i, (tag, body, color) in enumerate(labels):
        x = start_x + i * (card_w + gap)
        rounded_box(d, (x, y, x + card_w, y + card_h), WHITE, outline=color)
        d.rounded_rectangle((x + 22, y + 20, x + 155, y + 62), radius=16, fill=color)
        centered_text(d, (x + 22, y + 20, x + 155, y + 62), tag, fill=WHITE, size=20, bold=True)
        centered_text(d, (x + 22, y + 72, x + card_w - 22, y + card_h - 14), body, size=26, bold=True)
        centers.append((x + card_w / 2, y + card_h))

    hub = (520, 570, 1280, 735)
    rounded_box(d, hub, NAVY, outline=NAVY, radius=30)
    centered_text(d, hub, "统一安全决策中心\n风险等级 · 0–100 评分 · 命中证据 · 处置建议", fill=WHITE, size=34, bold=True)
    for cx, cy in centers:
        arrow(d, (cx, cy + 10), (900, 560), color="#8EA7CF", width=5, head=14)

    outcomes = [
        ("理解风险", "可解释报告"),
        ("完成处置", "脱敏 / 修改 / 放弃"),
        ("继续操作", "安全分享、提交或访问"),
        ("沉淀记录", "ArkData 本地历史"),
    ]
    oy, ow, oh, ogap = 855, 345, 116, 70
    total = len(outcomes) * ow + (len(outcomes) - 1) * ogap
    ox = (w - total) / 2
    for i, (a, b) in enumerate(outcomes):
        x = ox + i * (ow + ogap)
        rounded_box(d, (x, oy, x + ow, oy + oh), WHITE, outline=BLUE, radius=22)
        centered_text(d, (x, oy, x + ow, oy + oh), f"{a}\n{b}", size=24, bold=True)
        arrow(d, (900, 745), (x + ow / 2, oy - 10), color="#8EA7CF", width=4, head=12)

    img.save(OUT / "guardianhub_user_flow.png", quality=95)


def create_architecture():
    w, h = 1800, 1180
    img = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(img)
    title(d, "GuardianHub 技术架构与鸿蒙能力映射", "HarmonyOS 原生入口 + 私有检测服务 + 本地优先、联网可选", w)

    lanes = [
        (210, 465, "HarmonyOS 6\nArkTS Stage\n客户端", NAVY),
        (505, 760, "安全检测\n与统一接口层", BLUE),
        (800, 1055, "算法、存储\n与可选增强", GREEN),
    ]
    for y0, y1, label, color in lanes:
        d.rounded_rectangle((60, y0, 1740, y1), radius=28, fill=WHITE, outline=LINE, width=3)
        d.rounded_rectangle((60, y0, 360, y1), radius=28, fill=color, outline=color)
        centered_text(d, (80, y0 + 15, 340, y1 - 15), label, fill=WHITE, size=25, bold=True)

    client_cards = [
        ("Media Library Kit", "系统选图 / 保存图库"),
        ("Core File Kit", "ZIP 与材料多选"),
        ("Share Kit", "安全图片系统分享"),
        ("ArkData", "本地历史与统计"),
        ("Network Kit", "四模块 API 调用"),
    ]
    x, y, cw, ch, gap = 385, 260, 245, 150, 22
    for i, (a, b) in enumerate(client_cards):
        cx = x + i * (cw + gap)
        rounded_box(d, (cx, y, cx + cw, y + ch), "#F3F7FF", outline="#AFC6F5", radius=20)
        centered_text(d, (cx + 10, y + 10, cx + cw - 10, y + ch - 10), f"{a}\n{b}", size=22, bold=True)

    middle_cards = [
        ("Privacy Sentinel", "/api/detect\n/api/privacy/process"),
        ("Code Guardian", "/api/code/analyze"),
        ("Link Guard", "/api/link/check\n/api/link/qr/decode"),
        ("Doc Shield", "/api/doc/check"),
    ]
    x, y, cw, ch, gap = 385, 555, 290, 150, 40
    for i, (a, b) in enumerate(middle_cards):
        cx = x + i * (cw + gap)
        rounded_box(d, (cx, y, cx + cw, y + ch), "#F4F8FF", outline=BLUE, radius=22)
        centered_text(d, (cx + 8, y + 10, cx + cw - 8, y + ch - 10), f"{a}\n{b}", size=22, bold=True)

    bottom_cards = [
        ("RapidOCR / OpenCV", "文字、二维码与图像区域"),
        ("规则引擎", "代码、URL、材料风险"),
        ("Pillow", "黑条 / 模糊 / 马赛克"),
        ("SQLite / 文件存储", "检测记录与处理结果"),
        ("可选模型增强", "DeepSeek / Qwen VL"),
    ]
    x, y, cw, ch, gap = 380, 850, 250, 155, 22
    for i, (a, b) in enumerate(bottom_cards):
        cx = x + i * (cw + gap)
        rounded_box(d, (cx, y, cx + cw, y + ch), "#F2FBF6", outline="#8AC9AA", radius=20)
        centered_text(d, (cx + 8, y + 8, cx + cw - 8, y + ch - 8), f"{a}\n{b}", size=22, bold=True)

    arrow(d, (1020, 465), (1020, 505), color=BLUE, width=8, head=18)
    arrow(d, (1020, 760), (1020, 800), color=GREEN, width=8, head=18)

    d.text((380, 1090), "安全边界：ZIP 仅内存只读扫描、不执行代码；Link Guard 不访问目标网址；联网模型仅在用户主动开启后使用。",
           font=font(23), fill=MUTED)
    img.save(OUT / "guardianhub_architecture.png", quality=95)


def fit_image(source: Image.Image, box):
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    scale = min(bw / source.width, bh / source.height)
    resized = source.resize((int(source.width * scale), int(source.height * scale)), Image.Resampling.LANCZOS)
    x = x0 + (bw - resized.width) // 2
    y = y0 + (bh - resized.height) // 2
    return resized, (x, y)


def create_privacy_example():
    original_path = Path(r"E:\GuardianHub\platform\backend\static\samples\privacy_sentinel_demo_qr.png")
    processed_path = Path(r"E:\GuardianHub\platform\backend\static\processed\img_eb0bd285ac16_safe.png")
    original = Image.open(original_path).convert("RGB")
    processed = Image.open(processed_path).convert("RGB")

    w, h = 1800, 1040
    img = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(img)
    title(d, "Privacy Sentinel 脱敏闭环示例", "虚构测试数据：识别敏感区域后生成真实安全副本", w)
    boxes = [(80, 250, 850, 840), (950, 250, 1720, 840)]
    labels = [("处理前", original, RED), ("处理后", processed, GREEN)]
    for box, (label, src, color) in zip(boxes, labels):
        x0, y0, x1, y1 = box
        rounded_box(d, box, WHITE, outline=color, radius=24)
        d.rounded_rectangle((x0 + 24, y0 + 20, x0 + 160, y0 + 66), radius=16, fill=color)
        centered_text(d, (x0 + 24, y0 + 20, x0 + 160, y0 + 66), label, fill=WHITE, size=23, bold=True)
        fitted, pos = fit_image(src, (x0 + 30, y0 + 90, x1 - 30, y1 - 30))
        img.paste(fitted, pos)
    arrow(d, (865, 545), (935, 545), color=BLUE, width=10, head=22)
    centered_text(
        d,
        (210, 880, 1590, 995),
        "系统相册选择 → OCR / 二维码 / 隐私规则识别 → 黑条、模糊或马赛克 → 保存图库 → Share Kit 分享",
        size=27,
        bold=True,
    )
    img.save(OUT / "guardianhub_privacy_example.png", quality=95)


if __name__ == "__main__":
    create_user_flow()
    create_architecture()
    create_privacy_example()
