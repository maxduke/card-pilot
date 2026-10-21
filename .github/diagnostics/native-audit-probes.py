import os,subprocess
from pathlib import Path
variant = os.environ['AUDIT_VARIANT']
assert variant in ('date_navigation', 'date_navigation_keep_row')
subprocess.run(['git','apply','.github/diagnostics/date-navigation.patch'],check=True)
if variant == 'date_navigation_keep_row':
    path = 'CardPilot/Features/Cards/CardDetailsView.swift'
    Path(path).write_bytes(subprocess.check_output(['git','show','HEAD:'+path]))
print('Applied native date navigation candidate:', variant)
