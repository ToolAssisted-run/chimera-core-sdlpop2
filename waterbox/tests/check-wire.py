#!/usr/bin/env python3
"""The declarations: waterbox.config is what gen-config.py writes now from
settings.inc, the driver's file table and its button order (pop2-driver.c,
pop2-driver.h) - so nobody edited one and not the others.

usage: check-wire.py <repo root>
"""
import json
import os
import subprocess
import sys
import tempfile

root = sys.argv[1]
wb = os.path.join(root, "waterbox")
cfg = json.load(open(os.path.join(wb, "waterbox.config")))
with tempfile.TemporaryDirectory() as tmp:
    fresh = os.path.join(tmp, "waterbox.config")
    subprocess.run([sys.executable, os.path.join(wb, "gen-config.py"), fresh], check=True)
    if json.load(open(fresh)) != cfg:
        sys.exit("waterbox.config is not what gen-config.py writes from settings.inc and the driver: regenerate it")
print(f"{len(cfg['input']['buttons'])} buttons, {len(cfg['settings'])} settings and {len(cfg['firmware'])} files agree")
