"""Put a deck panel firmware image into the firmware updater's built-in catalog (#686).

The image is an input file, built elsewhere (the panel's own PlatformIO build, or a release); this step never
builds or flashes anything. It copies the image to <catalog>/panel/ and lists it in <catalog>/catalog.json with
its version and the build SHA the panel prints at boot. Commit the catalog.json change with the release; the
images themselves stay out of git (see .gitignore), so a build from the repo carries none.

    python3 -I Packages/FirmwareUpdaterKit/scripts/add_panel_image.py --image firmware.bin --version 1.0.0 --sha 1d0683f
"""
import argparse
import json
import pathlib
import shutil
import sys

DEFAULT_CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Sources/FirmwareCatalog/Resources"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--catalog", type=pathlib.Path, default=DEFAULT_CATALOG)
    parser.add_argument("--image", type=pathlib.Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha", required=True)
    args = parser.parse_args(argv)

    name = f"panel/deck-panel-{args.version}-{args.sha}.bin"
    (args.catalog / "panel").mkdir(exist_ok=True)
    shutil.copyfile(args.image, args.catalog / name)
    catalog_file = args.catalog / "catalog.json"
    catalog = json.loads(catalog_file.read_text())
    catalog["panel"].append({"version": args.version, "sha": args.sha, "image": name})
    catalog_file.write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"added {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
