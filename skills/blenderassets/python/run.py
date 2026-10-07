"""Entry point blend.js hands to Blender: `blender -b -P run.py -- <asset.py> <out dir>`.

Puts blendlib (and the asset's own folder) on sys.path, points blendlib at the output folder, then runs the asset
script as __main__.
"""

import os
import runpy
import sys

separator = sys.argv.index("--")
script = os.path.abspath(sys.argv[separator + 1])
out = os.path.abspath(sys.argv[separator + 2])
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(script))

import blendlib

blendlib.OUT = out
blendlib.SOURCE = script
os.makedirs(out, exist_ok=True)
sys.argv = [script]
runpy.run_path(script, run_name="__main__")
