"""Generate compact bitmap fonts containing only Family watch-face glyphs."""

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "font"
OUTPUT = ROOT / "resources" / "fonts"


@dataclass(frozen=True)
class FontSpec:
    name: str
    source: str
    size: int
    characters: str


SPECS = (
    FontSpec("jersey_time", "Jersey10-Regular.ttf", 78, "0123456789:"),
    FontSpec("press_date", "press_start_2p.ttf", 12, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "),
    FontSpec("jersey_stat", "Jersey10-Regular.ttf", 40, "0123456789-"),
    FontSpec("jersey_steps", "Jersey10-Regular.ttf", 32, "0123456789"),
    FontSpec("jersey_battery", "Jersey10-Regular.ttf", 34, "0123456789%-"),
)


def make_font(spec: FontSpec) -> None:
    font = ImageFont.truetype(SOURCE / spec.source, spec.size)
    ascent, descent = font.getmetrics()
    glyphs = []
    for character in spec.characters:
        left, top, right, bottom = font.getbbox(character)
        glyph = Image.new("L", (right - left, bottom - top), 0)
        ImageDraw.Draw(glyph).text((-left, -top), character, font=font, fill=255)
        glyph = glyph.point(lambda value: 255 if value >= 128 else 0)
        glyphs.append({
            "id": ord(character), "width": glyph.width, "height": glyph.height,
            "xoffset": left, "yoffset": top, "xadvance": round(font.getlength(character)),
            "image": glyph,
        })

    padding = 2
    atlas_width = 512
    x = y = padding
    row_height = 0
    for glyph in glyphs:
        if x + glyph["width"] + padding > atlas_width:
            x = padding
            y += row_height + padding
            row_height = 0
        glyph["x"], glyph["y"] = x, y
        x += glyph["width"] + padding
        row_height = max(row_height, glyph["height"])

    atlas_height = y + row_height + padding
    atlas = Image.new("L", (atlas_width, atlas_height), 0)
    for glyph in glyphs:
        atlas.paste(glyph["image"], (glyph["x"], glyph["y"]))
    atlas.save(OUTPUT / f"{spec.name}.png", "PNG", optimize=True)

    lines = [
        f'info face="{spec.name}" size=-{spec.size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0 outline=0',
        f"common lineHeight={ascent + descent} base={ascent} scaleW={atlas_width} scaleH={atlas_height} pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="{spec.name}.png"',
        f"chars count={len(glyphs)}",
    ]
    lines.extend(
        "char id={id} x={x} y={y} width={width} height={height} xoffset={xoffset} yoffset={yoffset} xadvance={xadvance} page=0 chnl=15".format(**glyph)
        for glyph in glyphs
    )
    (OUTPUT / f"{spec.name}.fnt").write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"{spec.name}: {len(glyphs)} glyphs, {atlas_width}x{atlas_height}")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        make_font(spec)


if __name__ == "__main__":
    main()
