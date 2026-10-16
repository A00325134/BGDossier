"""Offline Lua 5.1 checks. Install test dependency: uv pip install lupa."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((root / "tests" / "eso_mock.lua").read_text(encoding="utf-8"))
files = [line.strip() for line in (root / "BattlegroundDossier.txt").read_text().splitlines()
         if line.strip().endswith(".lua")]
for file in files:
    source = (root / file).read_text(encoding="utf-8")
    lua.execute(source, name="@" + file)
lua.execute((root / "tests" / "spec.lua").read_text(encoding="utf-8"), name="@tests/spec.lua")
lua.execute((root / "tests" / "ui_spec.lua").read_text(encoding="utf-8"), name="@tests/ui_spec.lua")
lua.execute((root / "tests" / "reliability_spec.lua").read_text(encoding="utf-8"), name="@tests/reliability_spec.lua")
bindings = ET.parse(root / "Bindings.xml").getroot()
assert bindings.tag == "Bindings"
action = bindings.find("./Layer[@name='SI_KEYBINDINGS_LAYER_GENERAL']/Category[@name='SI_BGD_KEYBINDINGS_CATEGORY']/Action[@name='BGD_TOGGLE']")
assert action is not None and action.findtext("Down") == "BattlegroundDossier.Keybindings:Toggle()"
assert not bindings.findall(".//Binding") and not bindings.findall(".//Bind")
manifest = (root / "BattlegroundDossier.txt").read_text().splitlines()
assert manifest.index("Keybindings.lua") < manifest.index("Bindings.xml") < manifest.index("BattlegroundDossier.lua")
print("Native keybinding XML and manifest order verified; no default binding.")
print(f"Compiled and loaded {len(files)} addon files under Lua 5.1.")
