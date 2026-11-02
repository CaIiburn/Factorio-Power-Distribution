# Static lint for Factorio require() pitfalls: Factorio resolves require() relative to the requiring
# file's directory first, so a bare name can silently resolve to a sibling (or the file itself).
import re, glob, os, sys
MOD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bad = []
for f in glob.glob(MOD + "/**/*.lua", recursive=True):
    if "dev-tests" in f: continue
    rel = os.path.relpath(f, MOD)
    for m in re.finditer(r'require\(\s*"([^"]+)"\s*\)', open(f).read()):
        name = m.group(1)
        if name.startswith("__core__.") or name.startswith("__base__."): continue
        top = name.split(".")[0]
        if "." not in name and os.path.exists(os.path.join(MOD, name + ".lua")) and not os.path.exists(os.path.join(os.path.dirname(f), name + ".lua")):
            continue   # a root-level module (config.lua) required from a subfolder: unambiguous
        if "." not in name or not os.path.isdir(os.path.join(MOD, top)):
            bad.append(f"{rel}: bare/unknown require '{name}'")
        elif not os.path.exists(os.path.join(MOD, *name.split(".")) + ".lua"):
            bad.append(f"{rel}: require '{name}' file missing")
        # relative-resolution hazard: same module name exists next to the requiring file
        sib = os.path.join(os.path.dirname(f), *name.split(".")) + ".lua"
        if os.path.exists(sib) and os.path.abspath(sib) == os.path.abspath(f):
            bad.append(f"{rel}: requires itself")
    if os.path.basename(f) in ("util.lua",):
        bad.append(f"{rel}: file named util.lua shadows core util")
print("LINT FAILURES:" if bad else "LINT OK")
for b in bad: print(" -", b)
sys.exit(1 if bad else 0)
