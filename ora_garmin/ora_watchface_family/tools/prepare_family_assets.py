"""Create device-sized, nearest-neighbor resources for the Family watch face."""

from pathlib import Path
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets"
READY = ROOT / "assets_ready"
DRAWABLES = ROOT / "resources" / "drawables"

# The source artwork uses a 1254 px transparent canvas. Cropping panels before
# resizing keeps their compiled memory use low while preserving the artist's
# original pixels and transparency.
SPECS = {
    "family_wf_bg_main.png": (SOURCE / "background" / "family_wf_bg_main.png", None, (360, 360)),
    "family_wf_panel_time.png": (SOURCE / "panels" / "family_wf_panel_time.png", "crop", (230, 109)),
    "family_wf_panel_heartrate.png": (SOURCE / "panels" / "family_wf_panel_heartrate.png", "crop", (86, 93)),
    "family_wf_panel_steps.png": (SOURCE / "panels" / "family_wf_panel_steps.png", "crop", (86, 93)),
    "family_wf_panel_battery.png": (SOURCE / "panels" / "family_wf_panel_battery.png", "crop", (166, 47)),
}


def crop_to_visible(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    # The exported canvases carry a nearly transparent anti-aliasing residue
    # over the whole artboard. Ignore it when finding the actual panel.
    bounds = alpha.point(lambda value: 255 if value > 16 else 0).getbbox()
    if bounds is None:
        raise ValueError("Asset has no visible pixels")
    # Keep a small transparent rim so outlines and drop shadows are never cut.
    left = max(0, bounds[0] - 4)
    top = max(0, bounds[1] - 4)
    right = min(image.width, bounds[2] + 4)
    bottom = min(image.height, bounds[3] + 4)
    return image.crop((left, top, right, bottom))


def main() -> None:
    READY.mkdir(exist_ok=True)
    DRAWABLES.mkdir(parents=True, exist_ok=True)
    for filename, (source, operation, size) in SPECS.items():
        with Image.open(source) as original:
            image = original.convert("RGBA")
            if operation == "crop":
                image = crop_to_visible(image)
            source_size = image.size
            image = image.resize(size, Image.Resampling.NEAREST)
            ready_path = READY / filename
            image.save(ready_path, "PNG", optimize=True)
            shutil.copy2(ready_path, DRAWABLES / filename)
        print(f"{filename}: {source_size[0]}x{source_size[1]} -> {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
