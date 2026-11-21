"""Report explicitly scoped Bash function-entry coverage, not line/branch coverage."""
import json
import re
import sys
from pathlib import Path

source, trace, output = map(Path, sys.argv[1:])
raw_observed = set()
with trace.open() as events:
    for row in events:
        fields = row.rstrip("\n").split("\t")
        if len(fields) == 2:
            raw_observed.add(tuple(fields))
normalized_paths = {filename: str(Path(filename).resolve()) for filename, _ in raw_observed}
observed = {(normalized_paths[filename], name) for filename, name in raw_observed}
rows = []
for filename in (source / "tests/coverage_scope.txt").read_text().splitlines():
    if not filename or filename.startswith("#"):
        continue
    for match in re.finditer(r"^function ([a-zA-Z_][a-zA-Z0-9_]*)\(\)", (source / filename).read_text(), re.M):
        name = match.group(1)
        rows.append({"file": filename, "function": name, "entered": (str(source / filename), name) in observed})
if not rows:
    raise SystemExit("No functions in the declared coverage scope")
entered = sum(row["entered"] for row in rows)
report = {"metric": "function entry", "entered": entered, "total": len(rows), "functions": rows}
output.mkdir(parents=True, exist_ok=True)
(output / "functions.json").write_text(json.dumps(report, indent=2) + "\n")
summary = f"Scoped function-entry coverage: {entered}/{len(rows)} ({entered / len(rows):.1%}).\n"
summary += "\nThis reports function entry during synthetic Bats tests, not line/branch coverage or live installation proof.\n\n"
summary += "| File | Function | Entered |\n|---|---|---|\n"
summary += "".join(f"| {r['file']} | {r['function']} | {'yes' if r['entered'] else 'no'} |\n" for r in rows)
(output / "functions.md").write_text(summary)
print(summary.splitlines()[0])
