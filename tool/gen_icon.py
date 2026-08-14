#!/usr/bin/env python3
"""TikiTaka 런처 아이콘 생성 — 틸 그라데이션 + 패싱볼(공 두 개) 모티프."""
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 2  # supersample
W = SIZE * SS


def rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def lerp(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def main():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 배경: 틸 세로 그라데이션
    top = (38, 166, 154)    # #26A69A teal 400
    bottom = (0, 105, 92)   # #00695C teal 800
    for y in range(W):
        t = y / (W - 1)
        d.line([(0, y), (W, y)], fill=lerp(top, bottom, t) + (255,))

    # 모티프 그리기 (전경 재사용을 위해 별도 함수)
    def draw_motif(draw, scale=1.0):
        cx, cy = 0.5 * W, 0.5 * W
        # 패싱볼 1: 큰 속이 빈 공 (왼쪽 위)
        r1 = 0.155 * W * scale
        draw.ellipse(
            [cx - 0.30 * W - r1, cy - 0.30 * W - r1,
             cx - 0.30 * W + r1, cy - 0.30 * W + r1],
            outline=(255, 255, 255, 255), width=int(0.045 * W * scale),
        )
        # 패싱볼 2: 작은 찬 공 (오른쪽 아래)
        r2 = 0.12 * W * scale
        draw.ellipse(
            [cx + 0.30 * W - r2, cy + 0.30 * W - r2,
             cx + 0.30 * W + r2, cy + 0.30 * W + r2],
            fill=(255, 255, 255, 255),
        )
        # 연결: 2차 베지어 곡선 위 점선 (패싱 동작)
        def bezier(p0, p1, p2, t):
            return tuple(
                (1 - t) ** 2 * a + 2 * (1 - t) * t * b + t ** 2 * c
                for a, b, c in zip(p0, p1, p2)
            )

        p0 = (cx - 0.30 * W, cy - 0.30 * W)
        p2 = (cx + 0.30 * W, cy + 0.30 * W)
        p1 = (cx + 0.05 * W, cy - 0.25 * W)  # 제어점 (위로 살짝 솟는 호)
        thickness = 0.04 * W * scale
        steps = 6
        for i in range(steps):
            t0 = i / steps
            t1 = (i + 0.75) / steps
            prev = None
            for j in range(24):
                t = t0 + (t1 - t0) * j / 23
                pt = bezier(p0, p1, p2, t)
                if prev:
                    draw.line([prev, pt], fill=(255, 255, 255, 255),
                              width=int(thickness))
                prev = pt

    draw_motif(d)

    # 둥근 모서리 마스킹 + 다운샘플 (풀 아이콘)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.putalpha(rounded_rect_mask(SIZE, int(0.18 * SIZE)))

    import os
    os.makedirs("example/assets/icon", exist_ok=True)
    img.save("example/assets/icon/icon.png")
    print("OK: example/assets/icon/icon.png")

    # 전경(적응형 아이콘용): 모티프만, 배경 없음, 모서리 마스킹 없음
    fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fg)
    draw_motif(fd, scale=0.9)  # 안전 여백
    fg = fg.resize((SIZE, SIZE), Image.LANCZOS)
    fg.save("example/assets/icon/icon_foreground.png")
    print("OK: example/assets/icon/icon_foreground.png")


if __name__ == "__main__":
    main()
