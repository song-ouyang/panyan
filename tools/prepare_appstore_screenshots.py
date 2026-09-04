#!/usr/bin/env python3
"""Prepare opaque, metadata-free iPhone screenshots for App Store Connect."""

from pathlib import Path

from PIL import Image, ImageOps


TARGET_SIZE = (1284, 2778)
FALLBACK_SIZE = (1242, 2688)

SCREENSHOTS = (
    (
        Path(
            "/Users/guoba/Documents/Simulator Screenshot - App Store iPhone 14 Plus - 2026-08-31 at 23.15.22.png"
        ),
        "01-launch.png",
    ),
    (
        Path(
            "/Users/guoba/Desktop/Simulator Screenshot - App Store iPhone 14 Plus - 2026-08-31 at 23.20.29.png"
        ),
        "02-gym.png",
    ),
    (
        Path(
            "/Users/guoba/Desktop/Simulator Screenshot - App Store iPhone 14 Plus - 2026-08-31 at 23.21.05.png"
        ),
        "03-login.png",
    ),
)


def main() -> None:
    output_dir = Path("/Users/guoba/Desktop/App Store 截图-6.5英寸-可上传")
    fallback_dir = Path(
        "/Users/guoba/Desktop/AppStore-6.5inch-JPEG-1242x2688"
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    fallback_dir.mkdir(parents=True, exist_ok=True)

    for source, output_name in SCREENSHOTS:
        with Image.open(source) as screenshot:
            if screenshot.size != TARGET_SIZE:
                raise ValueError(
                    f"{source.name}: expected {TARGET_SIZE}, got {screenshot.size}"
                )

            opaque = Image.new("RGB", screenshot.size, "white")
            if "A" in screenshot.getbands():
                opaque.paste(screenshot, mask=screenshot.getchannel("A"))
            else:
                opaque.paste(screenshot.convert("RGB"))

            opaque.save(output_dir / output_name, format="PNG", optimize=True)

            fallback = ImageOps.fit(
                opaque,
                FALLBACK_SIZE,
                method=Image.Resampling.LANCZOS,
                centering=(0.5, 0.5),
            )
            fallback.save(
                fallback_dir / output_name.replace(".png", ".jpg"),
                format="JPEG",
                quality=95,
                subsampling=0,
                optimize=True,
                progressive=False,
                dpi=(72, 72),
            )


if __name__ == "__main__":
    main()
