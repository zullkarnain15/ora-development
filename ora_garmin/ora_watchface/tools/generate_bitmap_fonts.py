"""Create minimal BMFont-compatible bitmap fonts for the ORA watch face.

Connect IQ font resources use a BMFont .fnt descriptor and a grayscale PNG
atlas. This script turns the supplied TTF sources into only the glyphs used by
the 360x360 watch-face layout.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT / "assets_ready" / "font"
OUTPUT_ROOT = PROJECT_ROOT / "resources" / "fonts"


@dataclass(frozen=True)
class FontSpec:
    output_name: str
    source_name: str
    size: int
    characters: str


FONT_SPECS = (
    FontSpec("jersey_time", "Jersey10-Regular.ttf", 82, "0123456789:"),
    FontSpec("jersey_steps", "Jersey10-Regular.ttf", 23, "0123456789-"),
    FontSpec("jersey_recovery", "Jersey10-Regular.ttf", 19, "0123456789 H-"),
    FontSpec("jersey_battery", "Jersey10-Regular.ttf", 20, "0123456789%-"),
    FontSpec("jersey_date", "Jersey10-Regular.ttf", 20, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "),
)


def make_font(spec: FontSpec) -> None:
    font = ImageFont.truetype(SOURCE_ROOT / spec.source_name, spec.size)
    ascent, descent = font.getmetrics()
    line_height = ascent + descent
    glyphs: list[dict[str, int | Image.Image]] = []

    for character in spec.characters:
        bbox = font.getbbox(character)
        advance = round(font.getlength(character))
        if bbox is None:
            glyphs.append({"id": ord(character), "width": 0, "height": 0, "xoffset": 0, "yoffset": 0, "xadvance": advance})
            continue

        left, top, right, bottom = bbox
        glyph = Image.new("L", (right - left, bottom - top), 0)
        ImageDraw.Draw(glyph).text((-left, -top), character, font=font, fill=255)
        # Pixel-art fonts remain crisp in the compiled 1-bit Connect IQ resource.
        glyph = glyph.point(lambda value: 255 if value >= 128 else 0)
        glyphs.append(
            {
                "id": ord(character),
                "width": glyph.width,
                "height": glyph.height,
                "xoffset": left,
                "yoffset": top,
                "xadvance": advance,
                "image": glyph,
            }
        )

    padding = 2
    atlas_width = 512
    x = padding
    y = padding
    row_height = 0
    for glyph in glyphs:
        width = glyph["width"]
        height = glyph["height"]
        if x + width + padding > atlas_width:
            x = padding
            y += row_height + padding
            row_height = 0
        glyph["x"] = x
        glyph["y"] = y
        x += width + padding
        row_height = max(row_height, height)

    atlas_height = max(1, y + row_height + padding)
    atlas = Image.new("L", (atlas_width, atlas_height), 0)
    for glyph in glyphs:
        if "image" in glyph:
            atlas.paste(glyph["image"], (glyph["x"], glyph["y"]))

    png_name = f"{spec.output_name}.png"
    fnt_name = f"{spec.output_name}.fnt"
    atlas.save(OUTPUT_ROOT / png_name, format="PNG", optimize=True)

    lines = [
        f'info face="{spec.output_name}" size=-{spec.size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0 outline=0',
        f"common lineHeight={line_height} base={ascent} scaleW={atlas_width} scaleH={atlas_height} pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="{png_name}"',
        f"chars count={len(glyphs)}",
    ]
    for glyph in glyphs:
        lines.append(
            "char id={id} x={x} y={y} width={width} height={height} xoffset={xoffset} yoffset={yoffset} xadvance={xadvance} page=0 chnl=15".format(**glyph)
        )
    (OUTPUT_ROOT / fnt_name).write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"{fnt_name}: {len(glyphs)} glyphs, {atlas_width}x{atlas_height}")


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    for spec in FONT_SPECS:
        make_font(spec)


if __name__ == "__main__":
    main()
