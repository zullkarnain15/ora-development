"""Prepare lightweight, nearest-neighbor PNG assets for the Garmin 360x360 target."""

from __future__ import annotations

from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parent
SOURCE_ROOT = PROJECT_ROOT / "assets"
OUTPUT_ROOT = PROJECT_ROOT / "assets_ready"

# Paths are relative to assets/. Keep source file names unchanged in assets_ready/.
TARGET_SIZES: dict[Path, tuple[int, int]] = {
    Path("background/ora_wf_bg_main.png"): (360, 360),
    Path("logo/ora_wf_logo_header.png"): (240, 80),
    Path("mascot/ora_wf_mascot_awan_idle_01.png"): (170, 170),
    Path("panels/ora_wf_panel_time.png"): (300, 100),
    Path("panels/ora_wf_panel_date.png"): (190, 63),
    Path("panels/ora_wf_panel_steps.png"): (82, 123),
    Path("panels/ora_wf_panel_recovery_01.png"): (82, 123),
    Path("panels/ora_wf_panel_status_bottom.png"): (280, 93),
}


def main() -> None:
    source_files = sorted(SOURCE_ROOT.rglob("*.png"))
    expected_files = {SOURCE_ROOT / relative_path for relative_path in TARGET_SIZES}

    missing = sorted(path.relative_to(SOURCE_ROOT) for path in expected_files if not path.is_file())
    if missing:
        raise FileNotFoundError("Missing required source asset(s): " + ", ".join(map(str, missing)))

    unexpected = [path.relative_to(SOURCE_ROOT) for path in source_files if path not in expected_files]
    if unexpected:
        raise ValueError("No target size configured for source PNG(s): " + ", ".join(map(str, unexpected)))

    if len(source_files) != len(TARGET_SIZES):
        raise RuntimeError("Source PNG list does not match the configured asset list.")

    for source_path in source_files:
        relative_path = source_path.relative_to(SOURCE_ROOT)
        target_size = TARGET_SIZES[relative_path]
        output_path = OUTPUT_ROOT / relative_path
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # Pillow retains image mode and PNG transparency metadata during resize/save.
        with Image.open(source_path) as image:
            image.load()  # Force decoding so damaged files fail here.
            source_size = image.size
            resized = image.resize(target_size, Image.Resampling.NEAREST)
            resized.save(output_path, format="PNG")

        output_size_bytes = output_path.stat().st_size
        print(
            f"{relative_path}: {source_size[0]}x{source_size[1]} -> "
            f"{target_size[0]}x{target_size[1]}, {output_size_bytes} bytes"
        )


if __name__ == "__main__":
    main()
