"""Build a dependency-free install ZIP using only manifest-listed addon files."""
from pathlib import Path
import re
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
manifest = root / "BattlegroundDossier.txt"
addon_files = [line.strip() for line in manifest.read_text().splitlines() if line.strip().endswith((".lua", ".xml"))]
files = [manifest.name, *addon_files, "README.md", "docs/API_VERIFICATION.md", "docs/UI_ACCEPTANCE.md", "docs/RELIABILITY_AUDIT.md"]
version = re.search(r"^## Version:\s*(\S+)", manifest.read_text(), re.MULTILINE).group(1)
destination = root / "dist" / f"BattlegroundDossier-{version}.zip"
destination.parent.mkdir(exist_ok=True)
with ZipFile(destination, "w", ZIP_DEFLATED) as archive:
    for file in files:
        source = root / file
        if not source.is_file():
            raise FileNotFoundError(source)
        archive.write(source, "BattlegroundDossier/" + file)
with ZipFile(destination) as archive:
    assert archive.testzip() is None
print(f"Built {destination} ({destination.stat().st_size:,} bytes, {len(files)} files)")
