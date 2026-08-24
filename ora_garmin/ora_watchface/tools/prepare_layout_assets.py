"""Create nearest-neighbor display variants required by layout_spec.json."""

from __future__ import annotations

from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT / "assets_ready"
OUTPUT_ROOT = PROJECT_ROOT / "resources" / "drawables"

ASSET_SPECS = {
    "ora_wf_logo_header_layout.png": (SOURCE_ROOT / "logo" / "ora_wf_logo_header.png", (232, 81)),
    "ora_wf_mascot_awan_idle_01_layout.png": (SOURCE_ROOT / "mascot" / "ora_wf_mascot_awan_idle_01.png", (148, 153)),
    "ora_wf_panel_steps_layout.png": (SOURCE_ROOT / "panels" / "ora_wf_panel_steps.png", (74, 111)),
    "ora_wf_panel_recovery_01_layout.png": (SOURCE_ROOT / "panels" / "ora_wf_panel_recovery_01.png", (74, 111)),
    "ora_wf_panel_status_bottom_layout.png": (SOURCE_ROOT / "panels" / "ora_wf_panel_status_bottom.png", (261, 55)),
}


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    for output_name, (source_path, size) in ASSET_SPECS.items():
        with Image.open(source_path) as source:
            source.load()
            source_size = source.size
            resized = source.resize(size, Image.Resampling.NEAREST)
            output_path = OUTPUT_ROOT / output_name
            resized.save(output_path, format="PNG")
        print(f"{output_name}: {source_size[0]}x{source_size[1]} -> {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
