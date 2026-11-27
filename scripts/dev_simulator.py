#!/usr/bin/env python3

import subprocess
import time
from pathlib import Path


def snapshot(root):
    watched = [
        root / "rssreader",
        root / "rssreader.xcodeproj" / "project.pbxproj",
        root / "rssreader.xcodeproj" / "xcshareddata",
        root / "scripts" / "install_simulator.sh",
        root / "scripts" / "load_env.sh",
        root / ".env",
    ]
    files = {}
    for path in watched:
        candidates = path.rglob("*") if path.is_dir() else [path]
        for candidate in candidates:
            try:
                if candidate.is_file() and candidate.name != ".DS_Store":
                    stat = candidate.stat()
                    files[candidate] = (stat.st_mtime_ns, stat.st_size)
            except FileNotFoundError:
                # Editors can replace a file between enumeration and stat.
                continue
    return files


def deploy(root):
    log_path = root / "build" / "dev-simulator.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print("Building and deploying to the development simulator...", flush=True)
    with log_path.open("w") as log:
        result = subprocess.run(
            ["bash", str(root / "scripts" / "install_simulator.sh")],
            cwd=root,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    if result.returncode:
        print(f"Deployment failed. Full log: {log_path}", flush=True)
        print("\n".join(log_path.read_text().splitlines()[-25:]), flush=True)
    else:
        print("Updated app launched in Simulator.", flush=True)
    return result.returncode


def main():
    root = Path(__file__).resolve().parent.parent
    previous = snapshot(root)
    pending = False
    changed_at = 0
    try:
        deploy(root)
        print("Watching app sources and resources. Ctrl-C to stop. App data is preserved.", flush=True)
        while True:
            current = snapshot(root)
            if current != previous:
                previous = current
                changed_at = time.monotonic()
                pending = True
            if pending and time.monotonic() - changed_at >= 1:
                pending = False
                deploy(root)
            time.sleep(0.25)
    except KeyboardInterrupt:
        print("\nStopped watching.", flush=True)


if __name__ == "__main__":
    main()
