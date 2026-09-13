"""Repair packs produced by older Challenge Maker Exporter builds.

Run after exporting. Only folders with Challenge Maker's ownership marker are
modified. No game save data is changed.
"""
import argparse
import json
import math
from pathlib import Path
import re
import shutil


RUNTIME = Path(__file__).with_name("cm_export_runtime_fixes.lua")
DESCRIPTION = Path(__file__).with_name("cm_description.lua")
OWNERSHIP = "challenge-maker-pack-v1"


def lua_string(value):
    return json.dumps(value, ensure_ascii=False)


def stats_line(stats):
    fields = []
    for key in ("speed", "tears", "damage", "range", "shot_speed", "luck"):
        value = stats.get(key)
        if not isinstance(value, (float, int)) or isinstance(value, bool) or not math.isfinite(value):
            continue
        if value < (0.1 if key == "speed" else 0) or key == "speed" and value > 2 or key == "tears" and value > 120:
            continue
        fields.append(f"[{lua_string(key)}]={value},")
    return "        startStats = {" + "".join(fields) + "},\n"


def saved_challenges(pack, save_file=None):
    """Old exe versions discard new fields before writing challenges.json."""
    root = pack.parent.parent / "data" / "challenge_maker"
    paths = [save_file] if save_file else sorted(root.glob("save[123].dat"), key=lambda p: p.stat().st_mtime)
    if not paths:
        print("Aviso: no se encontro save1.dat/save2.dat/save3.dat; los size perdidos por el exporter antiguo no se pueden recuperar de challenges.json.")
    found = {}
    for path in paths:
        try:
            content = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for challenge in content.get("challenges", []) if isinstance(content, dict) else []:
            if isinstance(challenge, dict) and challenge.get("id"):
                found[str(challenge["id"])] = challenge
    return found


def patch_pack(folder, save_file=None):
    marker = folder / "cm_pack.json"
    try:
        if json.loads(marker.read_text(encoding="utf-8")).get("format") != OWNERSHIP:
            return False
        challenges = json.loads((folder / "challenges.json").read_text(encoding="utf-8"))
        main_path = folder / "main.lua"
        main = main_path.read_text(encoding="utf-8")
    except (OSError, ValueError, AttributeError):
        return False
    if not isinstance(challenges, list) or "local configsByName = {\n" not in main:
        return False
    start = main.index("local configsByName = {\n")
    end = main.find("\nlocal configsById = {}", start)
    if end < 0:
        return False
    configs = main[start:end]
    original = saved_challenges(folder, save_file)
    used = set()
    for challenge in challenges:
        if not isinstance(challenge, dict):
            continue
        latest = original.get(str(challenge.get("id", "")))
        if latest and latest.get("title") == challenge.get("title"):
            challenge = {**challenge, **latest}
        title = (challenge.get("title") or "Generated Challenge").strip()
        base = title + " [" + folder.name + "]"
        title = base
        index = 2
        while title in used:
            title = f"{base} ({index})"
            index += 1
        used.add(title)
        head = "    [" + lua_string(title) + "] = {\n"
        pos = configs.find(head)
        if pos < 0:
            raise ValueError(f"No se encontró el challenge exportado: {title}")
        finish = configs.find("    },\n", pos + len(head))
        if finish < 0:
            raise ValueError(f"Bloque incompleto: {title}")
        body = configs[pos + len(head):finish]
        stats = challenge.get("startStats") or {}
        if not isinstance(stats, dict):
            stats = {}
        body, count = re.subn(r"^        startStats = \{[^\n]*\},\n", lambda _: stats_line(stats), body, count=1, flags=re.M)
        if count != 1:
            raise ValueError(f"Faltan las stats de: {title}")
        body = re.sub(r"^        sizeSteps = -?\d+,\n", "", body, flags=re.M)
        size = challenge.get("sizeSteps")
        if isinstance(size, int) and not isinstance(size, bool) and -999 <= size <= 999:
            body = body.replace("        startHealth = ", f"        sizeSteps = {size},\n        startHealth = ", 1)
        configs = configs[:pos + len(head)] + body + configs[finish:]
    main = main[:start] + configs + main[end:]
    includes = re.search(r'include\("(scripts/[^"\n]+/cm_general)"\)', main)
    if not includes:
        raise ValueError(f"No se encontró el directorio de scripts de {folder.name}")
    module_path = includes.group(1).removesuffix("cm_general") + "cm_export_runtime_fixes"
    module_file = folder / (module_path + ".lua")
    if not module_file.resolve().is_relative_to(folder.resolve()):
        raise ValueError("Ruta de scripts inválida")
    shutil.copy2(DESCRIPTION, module_file.with_name("cm_description.lua"))
    fix_bans = "function mod:OnBannedPocketPickup(" not in main
    fix_size = "function mod:OnSizeCache(" not in main
    attach = f'include("{module_path}").Attach(mod, function() return activeConfig end, {str(fix_bans).lower()}, {str(fix_size).lower()})'
    main = re.sub(r'^include\("scripts/[^"\n]+/cm_export_runtime_fixes"\)\.Attach\([^\n]*\)\n?', '', main, flags=re.M)
    if fix_bans or fix_size:
        main = main.rstrip("\n") + "\n\n" + attach + "\n"
        module_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(RUNTIME, module_file)
    if main != main_path.read_text(encoding="utf-8"):
        backup = main_path.with_suffix(".lua.bak")
        if not backup.exists():
            shutil.copy2(main_path, backup)
        main_path.write_text(main, encoding="utf-8")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="Carpeta mods o un pack exportado")
    parser.add_argument("--save", type=Path, help="Ruta a save1.dat, save2.dat o save3.dat si no esta junto a mods")
    args = parser.parse_args()
    root = args.folder
    if not root.is_dir():
        parser.error(f"No existe la carpeta: {root}")
    folders = [root] if (root / "cm_pack.json").is_file() else sorted(p for p in root.iterdir() if p.is_dir())
    count = 0
    for folder in folders:
        if (folder / "cm_pack.json").is_file():
            if patch_pack(folder, args.save):
                print("Reparado:", folder)
                count += 1
    print(f"Packs reparados: {count}")


if __name__ == "__main__":
    main()
