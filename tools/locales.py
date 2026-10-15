"""Keep Catnip's translation files in step with the code.

Every piece of text the addon shows is written L["English text"] in the .lua files. This script
collects those keys and rewrites Locales/<locale>.lua for each language:

  - translated keys stay as they are:          L["Reset"] = "..."
  - keys still to translate become comments:   -- L["Reset"] = ""
  - translations whose English no longer appears in the code (reworded or removed) move to a
    section at the end, so they can be reused or deleted.

Keys are grouped by the file that first uses them, in Catnip.toc's load order, so translators can
see where each one shows. Run from the repo root after changing any text:

    py tools/locales.py            update every Locales/*.lua except enUS
    py tools/locales.py zhTW       also start a new language file (then add it to Catnip.toc)
    py tools/locales.py --check    change nothing; exit 1 if any file is out of date
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LOCALES = os.path.join(ROOT, "Locales")
TOC = os.path.join(ROOT, "Catnip.toc")

# A key or value in double quotes, escapes kept as written so they round-trip unchanged.
STRING = r'"((?:[^"\\]|\\.)*)"'
USE = re.compile(r"\bL\[" + STRING + r"\]")
TRANSLATED = re.compile(r"^L\[" + STRING + r"\]\s*=\s*" + STRING + r"\s*$")
UNUSED_MARK = "-- No longer used"

NAMES = {
    "zhCN": "Simplified Chinese",
    "zhTW": "Traditional Chinese",
    "koKR": "Korean",
    "deDE": "German",
    "frFR": "French",
    "esES": "Spanish (Spain)",
    "esMX": "Spanish (Mexico)",
    "ptBR": "Portuguese (Brazil)",
    "ruRU": "Russian",
    "itIT": "Italian",
}

HEADER = """\
-- {name} ({locale}) translation for Catnip.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty
-- quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in
-- English. Keep %s (a name or text) and %d (a number) in the translation; if the sentence needs
-- two of them in the other order, number them: %2$d ... %1$s. Spell names (Rake, Prowl...) come
-- from the game already translated, so they aren't listed here.
--
-- This file is rewritten by tools/locales.py, which keeps your translations and adds new text as
-- it appears. Only edit the L[...] lines; other changes here are lost.
if GetLocale() ~= "{locale}" then
    return
end
local addonName, ns = ...
local L = ns.L
"""


def lua_files():
    """The addon's own .lua files in load order (Catnip.toc), Locales and libs excluded."""
    files = []
    with open(TOC, encoding="utf-8") as toc:
        for line in toc:
            path = line.strip().replace("\\", "/")
            if path.endswith(".lua") and not path.startswith(("libs/", "Locales/")):
                files.append(path)
    return files


def collect_keys():
    """{file: [keys first used there]} in load order, each key once."""
    seen, by_file = set(), {}
    for path in lua_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as source:
            text = source.read()
        keys = []
        for match in USE.finditer(text):
            key = match.group(1)
            if key not in seen:
                seen.add(key)
                keys.append(key)
        if keys:
            by_file[path] = keys
    return by_file


def read_translations(path):
    """{key: value} of the translated (uncommented, non-empty) lines in a locale file."""
    translations = {}
    if not os.path.exists(path):
        return translations
    with open(path, encoding="utf-8") as existing:
        for line in existing:
            match = TRANSLATED.match(line.strip())
            if match and match.group(2):
                translations[match.group(1)] = match.group(2)
    return translations


def render(locale, by_file, translations):
    lines = [HEADER.format(name=NAMES.get(locale, locale), locale=locale)]
    used = set()
    for path, keys in by_file.items():
        lines.append("\n-- " + path + "\n")
        for key in keys:
            used.add(key)
            if key in translations:
                lines.append('L["%s"] = "%s"\n' % (key, translations[key]))
            else:
                lines.append('-- L["%s"] = ""\n' % key)
    unused = [key for key in translations if key not in used]
    if unused:
        lines.append("\n" + UNUSED_MARK + " (the English changed or the text was removed). Reuse or delete:\n")
        for key in unused:
            lines.append('L["%s"] = "%s"\n' % (key, translations[key]))
    total = sum(len(keys) for keys in by_file.values())
    done = total - sum(1 for keys in by_file.values() for key in keys if key not in translations)
    return "".join(lines), done, total, len(unused)


def main(args):
    check = "--check" in args
    new = [arg for arg in args if not arg.startswith("--")]
    locales = sorted({name[:-4] for name in os.listdir(LOCALES) if name.endswith(".lua")} - {"enUS"} | set(new))
    by_file = collect_keys()
    with open(TOC, encoding="utf-8") as toc:
        listed = toc.read().replace("\\", "/")
    stale = False
    for locale in locales:
        path = os.path.join(LOCALES, locale + ".lua")
        text, done, total, unused = render(locale, by_file, read_translations(path))
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        status = "%s: %d of %d translated" % (locale, done, total)
        if unused:
            status += ", %d no longer used" % unused
        if current != text:
            stale = True
            if check:
                status += " (out of date: run py tools/locales.py)"
            else:
                with open(path, "w", encoding="utf-8", newline="\n") as out:
                    out.write(text)
                status += " (updated)"
        if "Locales/%s.lua" % locale not in listed:
            status += " (not in Catnip.toc yet)"
        print(status)
    return 1 if check and stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
