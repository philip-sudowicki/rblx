#!/usr/bin/env python3
"""Bundle DEEP HAUL's pure Luau modules + tests into one file runnable by the `luau` CLI.

Roblox ModuleScripts use `require(script.Parent.X)`, which the CLI can't resolve. This script
embeds every module under src/shared (plus selected pure server modules) as source strings,
builds a virtual instance tree, and loads modules on demand with loadstring/setfenv inside a
stubbed Roblox environment (tests/prelude.luau). Output: build/test_bundle.luau
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (virtual path prefix, directory on disk)
MOUNTS = [
    ("ReplicatedStorage/Shared", os.path.join(ROOT, "src", "shared")),
    ("ServerScriptService/Server/Config", os.path.join(ROOT, "src", "server", "Config")),
    ("ServerScriptService/Server/Pure", os.path.join(ROOT, "src", "server", "Pure")),
]


def long_string(src: str) -> str:
    level = 1
    while ("]" + "=" * level + "]") in src:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + src + "]" + eq + "]"


def collect():
    modules = []
    for prefix, directory in MOUNTS:
        if not os.path.isdir(directory):
            continue
        for dirpath, _, files in os.walk(directory):
            for name in sorted(files):
                if not name.endswith(".luau"):
                    continue
                if name.endswith(".server.luau") or name.endswith(".client.luau"):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, directory).replace(os.sep, "/")
                vpath = prefix + "/" + rel[: -len(".luau")]
                if vpath.endswith("/init"):
                    vpath = vpath[: -len("/init")]
                with open(full, "r", encoding="utf-8") as fh:
                    modules.append((vpath, fh.read()))
    return modules


def main():
    script_path = None
    if len(sys.argv) >= 3 and sys.argv[1] == "--script":
        script_path = sys.argv[2]
    modules = collect()
    with open(os.path.join(ROOT, "tests", "prelude.luau"), "r", encoding="utf-8") as fh:
        prelude = fh.read()
    test_dir = os.path.join(ROOT, "tests")
    tests = []
    if script_path:
        with open(script_path, "r", encoding="utf-8") as fh:
            tests.append((os.path.basename(script_path), fh.read()))
    else:
        for name in sorted(os.listdir(test_dir)):
            if name.endswith(".spec.luau"):
                with open(os.path.join(test_dir, name), "r", encoding="utf-8") as fh:
                    tests.append((name, fh.read()))

    out = [prelude, "\nlocal __MODULES = {"]
    for vpath, src in modules:
        out.append("\t[%s] = %s," % (repr(vpath).replace("'", '"'), long_string(src)))
    out.append("}\n")
    out.append("__registerModules(__MODULES)\n")
    out.append("local __TESTS = {")
    for name, src in tests:
        out.append("\t{ name = %s, source = %s }," % (repr(name).replace("'", '"'), long_string(src)))
    out.append("}\n")
    out.append("__runTests(__TESTS)\n")

    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    target = os.path.join(ROOT, "build", "script_bundle.luau" if script_path else "test_bundle.luau")
    with open(target, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))
    print("bundled %d modules and %d test files -> %s" % (len(modules), len(tests), os.path.relpath(target, ROOT)))


if __name__ == "__main__":
    sys.exit(main())
