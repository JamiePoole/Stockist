"""Run the pure-Lua specs under Lua 5.1 (the same version WoW embeds) using lupa.

Usage: .venv/Scripts/python.exe tests/run.py [spec-name-substring]
"""
import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
ADDON = ROOT / "Stockist"

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.ADDON_DIR = str(ADDON).replace("\\", "/")
g.TESTS_DIR = str(TESTS).replace("\\", "/")
lua.execute(f'dofile("{g.TESTS_DIR}/harness.lua")')

pattern = sys.argv[1] if len(sys.argv) > 1 else ""
specs = sorted(p for p in (TESTS / "specs").glob("*_spec.lua") if pattern in p.name)
if not specs:
    print("no specs matched")
    sys.exit(1)

for spec in specs:
    g.set_current_file(spec.name)
    lua.execute(f'dofile("{str(spec).replace(chr(92), "/")}")')

passed, failed, details = g.report()
print(f"{passed} passed, {failed} failed")
if failed:
    print(details)
    sys.exit(1)
