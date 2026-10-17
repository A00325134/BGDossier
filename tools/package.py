"""Build a dependency-free install ZIP using only manifest-listed addon files."""
from pathlib import Path
import re
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
manifest = root / "BattlegroundDossier.txt"
addon_files = [line.strip() for line in manifest.read_text().splitlines() if line.strip().endswith((".lua", ".xml"))]
files = [manifest.name, *addon_files, "README.md", "docs/API_VERIFICATION.md", "docs/UI_ACCEPTANCE.md", "docs/RELIABILITY_AUDIT.md", "docs/MERGE_NOTES.md", "docs/PERSONAL_HISTORY.md", "docs/RELEASE_CANDIDATE_UI.md"]
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
    assert sum(name.endswith(".txt") for name in archive.namelist()) == 1
    assert sum(name.endswith("Bindings.xml") for name in archive.namelist()) == 1
    assert not any("tracker/" in name.lower() for name in archive.namelist())
    for file in files:
        assert archive.read("BattlegroundDossier/" + file) == (root / file).read_bytes()
print(f"Built {destination} ({destination.stat().st_size:,} bytes, {len(files)} files)")
