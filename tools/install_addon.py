"""Adapted from Azeroth Accord (tools/install_addon.py), same owner, GPL-3.0 (ADR 0012).

Copies the addon (AzerothThreatwarden/, including the fetched Libs) into the WoW AddOns folder.

The folder is read from tools/local.ini (git-ignored); see tools/local.example.ini.
Run tools/fetch_libs.py first. Usage: python -I -X utf8 tools/install_addon.py
"""
import configparser
import os
import shutil
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
SOURCE = os.path.join(ROOT, "AzerothThreatwarden")
INI = os.path.join(TOOLS, "local.ini")
NAME = "AzerothThreatwarden"


def main():
    if not os.path.isfile(INI):
        print("tools/local.ini is missing: copy tools/local.example.ini to tools/local.ini and set [paths] addons "
              "to your AddOns folder.")
        return 1
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(INI, encoding="utf-8-sig")   # utf-8-sig: Windows editors may add a byte order mark
    addons = cfg.get("paths", "addons", fallback="").strip().strip('"')
    if not addons or "<" in addons:
        print("tools/local.ini has no real [paths] addons value (still the placeholder?).")
        return 1
    if not os.path.isdir(addons):
        print(f"The AddOns folder does not exist: {addons}")
        return 1
    if not os.path.isfile(os.path.join(SOURCE, "Libs", "Ace3", "LibStub", "LibStub.lua")):
        print("The libraries are missing: run python -I -X utf8 tools/fetch_libs.py first.")
        return 1
    target = os.path.join(addons, NAME)
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(SOURCE, target, ignore=shutil.ignore_patterns(".fetched", "*.md", "tests", ".git*"))
    print(f"Installed {NAME} into {target}. In game: /reload, then check the AddOns list.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
