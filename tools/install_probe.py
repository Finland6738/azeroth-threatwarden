"""Copies the throwaway probe addon (tools/probe/AzTw_Probe) into the WoW AddOns folder.

Adapted from Azeroth Accord (tools/install_probe.py), same owner, GPL-3.0 (ADR 0012).
The folder is read from tools/local.ini (git-ignored); see tools/local.example.ini. Only the AzTw_Probe folder of the
AddOns folder is replaced; the saved results (AzTw_ProbeDB, in the WTF folder) are not touched.

Usage: python -I -X utf8 tools/install_probe.py
"""
import configparser
import os
import shutil
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
NAME = "AzTw_Probe"
SOURCE = os.path.join(TOOLS, "probe", NAME)
INI = os.path.join(TOOLS, "local.ini")


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
    target = os.path.join(addons, NAME)
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(SOURCE, target)
    print(f"Installed {NAME} into {target}. In game: /reload, then /atwp.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
