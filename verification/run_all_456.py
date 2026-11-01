"""Run current FAT32/cache software checks. The full FIFO/video test can take 10-20 minutes."""
from pathlib import Path
import subprocess,sys
v=Path(__file__).resolve().parent
for name in ['run_storage_tests.py','run_schedule_tests.py','run_shared_regression.py','run_aux_tests.py','run_cache_tests.py']:
 print('RUN',name,flush=True)
 subprocess.run([sys.executable,'-B',str(v/name)],check=True)
print('ALL LESSON 4/5/6 SOFTWARE CHECKS PASSED; HARDWARE VALIDATION IS STILL REQUIRED')
