"""Apply the exact stable-row candidate; no observer or test transformations."""
from pathlib import Path
import subprocess

patch = Path(__file__).with_suffix('.patch')
subprocess.run(['git', 'apply', '--check', str(patch)], check=True)
subprocess.run(['git', 'apply', str(patch)], check=True)
