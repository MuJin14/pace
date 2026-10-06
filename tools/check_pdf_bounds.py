"""从 PDF 内容流抽取文本与矩形的精确坐标，判断是否超出页边距。

为什么不用图像测量：渲染出的 PNG 尺寸/缩放不透明，我在这上面反复得出
自相矛盾的结论（同一份文档量出 39.4 / 49.1 / 66.5 px/cm 三种比例）。
PDF 坐标系是确定的：1 点 = 1/72 英寸，A4 页宽 595.28pt，
左边距 2cm = 56.69pt，内容区右界 = 538.58pt。

用法：
    python check_pdf_bounds.py <file.pdf>
"""
import re
import sys
import zlib

PT_CM = 72 / 2.54
PAGE_W = 21.0 * PT_CM
MARGIN = 2.0 * PT_CM
RIGHT = PAGE_W - MARGIN


def iter_streams(raw):
    for m in re.finditer(rb"stream\r?\n", raw):
        start = m.end()
        end = raw.find(b"endstream", start)
        if end < 0:
            continue
        chunk = raw[start:end].rstrip(b"\r\n")
        try:
            yield zlib.decompress(chunk)
        except Exception:
            yield chunk


def numbers(s):
    return [float(x) for x in re.findall(r"-?\d+\.?\d*", s)]


def main(path):
    raw = open(path, "rb").read()
    print("page width %.2f pt | content right limit %.2f pt"
          % (PAGE_W, RIGHT))

    max_text = 0.0
    max_rect = 0.0
    n_txt = 0
    n_rec = 0
    for st in iter_streams(raw):
        txt = st.decode("latin-1", "replace")

        last_x = None
        for tok in re.finditer(
            r"([-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+) Tm"
            r"|([-\d.]+ [-\d.]+) T[dD]"
            r"|(TJ|Tj)",
            txt,
        ):
            if tok.group(1):
                last_x = numbers(tok.group(1))[4]
            elif tok.group(2):
                nums = numbers(tok.group(2))
                last_x = (last_x or 0.0) + nums[0]
            else:
                n_txt += 1
                if last_x is not None:
                    max_text = max(max_text, last_x)

        for m in re.finditer(r"([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) re", txt):
            x, _y, w, _h = (float(g) for g in m.groups())
            if w <= 0 or w > PAGE_W:
                continue
            n_rec += 1
            max_rect = max(max_rect, x + w)

    print("parsed: %d text blocks, %d rects" % (n_txt, n_rec))
    print()
    print("rightmost text start = %8.2f pt (%6.2f cm)  %s"
          % (max_text, max_text / PT_CM,
             "OK" if max_text <= RIGHT + 1 else "OVERFLOW"))
    print("rightmost rect right = %8.2f pt (%6.2f cm)  %s"
          % (max_rect, max_rect / PT_CM,
             "OK" if max_rect <= RIGHT + 1 else "OVERFLOW"))
    print()
    print("content right limit  = %8.2f pt (%6.2f cm)" % (RIGHT, RIGHT / PT_CM))
    return 0 if (max_text <= RIGHT + 1 and max_rect <= RIGHT + 1) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
