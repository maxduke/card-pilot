import subprocess
subprocess.run(['git','apply','--unidiff-zero','.github/diagnostics/date-navigation.patch'],check=True)
print('Applied actual date navigation and single text-flow summary candidate.')
