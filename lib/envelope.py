"""Generate compatible upgrade images using a trusted project script exposing envelope(data, numeric_version)."""
import argparse
from pathlib import Path
import runpy
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("script", "fromelf", "axf", "output", "version"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    major, minor = map(int, args.version.split("."))
    if not 0 <= major <= 65535 or not 0 <= minor <= 65535:
        raise ValueError("major/minor exceeds 16 bits")
    header = Path(args.script).resolve().parents[1] / "User_Driver/boot_update.h"
    # Require textual and numeric versions to agree before creating an upgrade package.
    version_ids = re.findall(r"(?m)^#define\s+\w+_FW_VERSION_ID\s+(0x[0-9a-fA-F]+)", header.read_text(encoding="utf-8"))
    if len(version_ids) != 1 or int(version_ids[0], 16) != ((major << 16) | minor):
        raise ValueError("ASCII and numeric firmware versions disagree")
    # This executes the project script at module scope; use only a trusted packager.
    project = runpy.run_path(args.script)
    with tempfile.TemporaryDirectory(prefix="puyuan-") as temporary:
        raw = Path(temporary) / "application.bin"
        subprocess.run([args.fromelf, "--bin", "--output", str(raw), args.axf], check=True)
        image = project["envelope"](raw.read_bytes(), major << 16 | minor)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    print("Upgrade image generated using the project's envelope function")


if __name__ == "__main__":
    main()
