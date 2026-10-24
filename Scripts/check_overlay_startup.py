"""Launch the real macOS app in its permission-free startup-check mode."""
import json
from pathlib import Path
import subprocess
import sys

app, report = map(Path, sys.argv[1:])
report.unlink(missing_ok=True)
result = subprocess.run(
    [str(app / "Contents/MacOS/ArenaMate"), "--smoke-test", str(report)],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
)
if result.returncode or not report.exists():
    print(result.stdout)
    raise SystemExit("The app did not finish the overlay startup check.")
checks = json.loads(report.read_text())
if not checks or not all(value is True for value in checks.values()):
    print(result.stdout)
    print(json.dumps(checks, sort_keys=True))
    raise SystemExit("Overlay startup or window lifecycle failed.")
print("Overlay startup checks passed: " + ", ".join(sorted(checks)))
