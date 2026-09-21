#!/usr/bin/env python3
from pathlib import Path
import re
import sys
import json

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "Packages" / "GuidanceUI"
RESOURCES = UI / "Resources"
LOCALES = ("en", "zh-Hans", "zh-Hant")

call_pattern = re.compile(r'LF?\("((?:[^"\\]|\\.)*)"')
string_pattern = re.compile(r'"((?:[^"\\]|\\.)*[\u4e00-\u9fff](?:[^"\\]|\\.)*)"')
entry_pattern = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')


def decode(value: str) -> str:
    return (value
            .replace(r'\"', '"')
            .replace(r'\n', '\n')
            .replace(r'\\', '\\'))


def load_strings(path: Path):
    result = {}
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("/*") or line.startswith("//"):
            continue
        match = entry_pattern.match(line)
        if not match:
            raise ValueError(f"Malformed .strings entry: {path}:{line_no}: {line}")
        key, value = map(decode, match.groups())
        if key in result:
            raise ValueError(f"Duplicate localization key {key!r} in {path}")
        result[key] = value
    return result

keys = set()
unwrapped = []
for recipe_path in (ROOT / "Packages" / "RecipeKit" / "Resources").glob("*.recipe.json"):
    try:
        recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValueError(f"Invalid recipe JSON {recipe_path}: {exc}")
    for field in ("title", "subtitle"):
        if recipe.get(field):
            keys.add(recipe[field])
    for tag in recipe.get("presentation", {}).get("tags", []):
        if tag:
            keys.add(tag)

for path in UI.glob("*.swift"):
    if path.name == "Localization.swift":
        continue
    text = path.read_text(encoding="utf-8")
    keys.update(decode(match.group(1)) for match in call_pattern.finditer(text))
    for line_no, line in enumerate(text.splitlines(), 1):
        for match in string_pattern.finditer(line):
            prefix2 = line[max(0, match.start() - 2):match.start()]
            prefix3 = line[max(0, match.start() - 3):match.start()]
            if prefix2 != "L(" and prefix3 != "LF(":
                unwrapped.append(f"{path.name}:{line_no}: {match.group(0)}")

errors = []
if unwrapped:
    errors.append("Unlocalized CJK string literals:\n  " + "\n  ".join(unwrapped))

locale_maps = {}
for locale in LOCALES:
    path = RESOURCES / f"{locale}.lproj" / "Localizable.strings"
    if not path.exists():
        errors.append(f"Missing localization file: {path}")
        continue
    try:
        locale_maps[locale] = load_strings(path)
    except ValueError as exc:
        errors.append(str(exc))
        continue
    missing = sorted(keys - set(locale_maps[locale]))
    extra = sorted(set(locale_maps[locale]) - keys)
    if missing:
        errors.append(f"{locale}: {len(missing)} missing keys: {missing}")
    if extra:
        errors.append(f"{locale}: {len(extra)} orphaned keys: {extra}")

if "en" in locale_maps:
    untranslated = sorted(k for k, v in locale_maps["en"].items() if re.search(r'[\u4e00-\u9fff]', v))
    if untranslated:
        errors.append(f"en: values still containing CJK: {untranslated}")

# Privacy permission prompts are app-bundle localizations, not GuidanceUI strings.
for locale in LOCALES:
    info_path = ROOT / "PhotoGuideApp" / "Resources" / f"{locale}.lproj" / "InfoPlist.strings"
    if not info_path.exists():
        errors.append(f"Missing localized privacy strings: {info_path}")
        continue
    try:
        info = load_strings(info_path)
    except ValueError as exc:
        errors.append(str(exc))
        continue
    for required in ("NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription"):
        if not info.get(required, "").strip():
            errors.append(f"{locale}: missing {required} in InfoPlist.strings")

if errors:
    print("Localization validation failed:\n" + "\n".join(errors), file=sys.stderr)
    sys.exit(1)

print(f"Localization OK: {len(keys)} keys × {len(LOCALES)} locales ({', '.join(LOCALES)})")
