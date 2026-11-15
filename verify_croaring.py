"""Independent CRoaring validation. Requires pyroaring==1.2.0."""
from pathlib import Path
import subprocess
import pyroaring

root = Path(__file__).resolve().parent
subprocess.run(["python", "generate_croaring_fixtures.py"], cwd=root, check=True)
subprocess.run(["moon", "fmt"], cwd=root, check=True)
subprocess.run(["moon", "test", "--release", "--deny-warn"], cwd=root, check=True)
print("CRoaring -> MoonBit: regenerated empty, high-bit, Run, Bitmap and random fixtures, PASS")
result = subprocess.run(
    ["moon", "run", "cmd/interop", "--release"],
    cwd=root, text=True, capture_output=True, check=True,
)
payload = bytes(int(line) for line in result.stdout.splitlines() if line.strip())
decoded = pyroaring.BitMap.deserialize(payload)
expected = pyroaring.BitMap(range(10000))
expected.update([2147483648, 4294967295])
assert decoded == expected
print(f"MoonBit -> CRoaring: {len(decoded)} members, {len(payload)} bytes, PASS")
print(f"pyroaring={pyroaring.__version__}")
