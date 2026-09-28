"""Run every offline suite with Lua 5.1, independently and from the repo root."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SUITES = sorted((ROOT / "tests").glob("*_spec.lua")) + sorted((ROOT / "probe/tests").glob("*_spec.lua"))


def main():
    os.chdir(ROOT)
    executable = os.environ.get("LUA")
    if not executable:
        for name in ("lua5.1", "lua51", "lua", "luajit"):
            candidate = shutil.which(name)
            if candidate:
                version = subprocess.run([candidate, "-e", "print(_VERSION)"], capture_output=True, text=True)
                if version.returncode == 0 and version.stdout.strip() == "Lua 5.1":
                    executable = candidate
                    break
    if executable:
        version = subprocess.run([executable, "-e", "assert(_VERSION == 'Lua 5.1', 'Lua 5.1 required')"])
        if version.returncode:
            return version.returncode
        for suite in SUITES:
            print(f"\n{suite.relative_to(ROOT)}", flush=True)
            result = subprocess.run([executable, str(suite)])
            if result.returncode:
                return result.returncode
    else:
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            print("Lua 5.1 required: install lua5.1, set LUA to its executable, or use Python lupa.lua51.", file=sys.stderr)
            return 1
        for suite in SUITES:
            print(f"\n{suite.relative_to(ROOT)}", flush=True)
            # Each suite gets a fresh runtime; globals cannot leak between suites.
            runtime = LuaRuntime()
            runtime.globals().print = lambda *values: print(*values, flush=True)
            runtime.execute(suite.read_text(encoding="utf-8"))
    print(f"\nPASS: all {len(SUITES)} Lua 5.1 suites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
