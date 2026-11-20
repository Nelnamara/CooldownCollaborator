"""Rebuilds Locales/enUS.lua from the L["..."] lookups in the addon's files.

    python tools/gen-enus.py          (from the addon folder)

The English text is the key, so every phrase is listed as L["text"] = true, grouped by the
file that first uses it, in the order the TOC loads the files. tools/tests/locale.lua checks
that the file and the code agree.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
HEAD = '''-- English base for CooldownCollaborator. The English text is the key, so a phrase with no
-- translation shows in English. Other languages: the files beside this one, filled from the
-- CurseForge translation tool when a release is packaged. Keep this table in step with the
-- L["..."] lookups in the code (python tools/gen-enus.py rebuilds it; tools/tests/locale.lua checks it).
local L = CooldownCollaborator.NewLocale("enUS")
if not L then return end

--@localization(locale="enUS", format="lua_additive_table", same-key-is-true=true)@
'''


def toc_files():
    with open(os.path.join(ROOT, "CooldownCollaborator_Mainline.toc"), encoding="utf-8") as f:
        names = [l.strip() for l in f if l.strip() and not l.startswith("##")]
    out = [n.replace("\\", "/") for n in names if n.endswith(".lua")]
    # the files the other TOCs add (the per-client spell lists) hold no phrases
    return [n for n in out if not n.startswith("Locales/") and not n.startswith("Data")]


def literals(src):
    found = []
    i = 0
    while True:
        s = src.find('L["', i)
        if s < 0:
            break
        i = s + 3
        before = src[s - 1] if s > 0 else " "
        if re.match(r"[\w:.]", before):
            continue
        j = i
        while j < len(src):
            c = src[j]
            if c == "\\":
                j += 2
            elif c == '"':
                break
            else:
                j += 1
        if src[j + 1:j + 2] == "]":
            found.append(src[i:j])
            i = j + 1
    return found


def main():
    seen = set()
    out = [HEAD]
    total = 0
    for name in toc_files():
        with open(os.path.join(ROOT, name), encoding="utf-8", newline="") as f:
            src = f.read().replace("\r\n", "\n")
        keys = []
        for k in literals(src):
            if k not in seen:
                seen.add(k)
                keys.append(k)
        if keys:
            out.append("\n-- %s\n" % name)
            for k in keys:
                out.append('L["%s"] = true\n' % k)
            total += len(keys)
    with open(os.path.join(ROOT, "Locales", "enUS.lua"), "w", encoding="utf-8", newline="") as f:
        f.write("".join(out).replace("\n", "\r\n"))
    print("%d phrases" % total)


if __name__ == "__main__":
    sys.exit(main())
