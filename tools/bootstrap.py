#!/usr/bin/env python3
"""Install pinned Linux x86_64 tools locally, retaining TLS and SHA256 checks."""
import hashlib
import io
from pathlib import Path
import platform
import urllib.request
import zipfile

TOOLS = [
    ("rojo", "7.7.1", "rojo-rbx/rojo", "00feb4fa0829a1dd72b49df2639da519a352bfe13cadcd83969e2ba2bb5693c4"),
    ("lune", "0.11.1", "lune-org/lune", "39859282ce677fce19e6eb45c37596a90a25c324c95b4e7e02d428b6cae294a1"),
]

def main():
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        raise SystemExit("On Windows/macOS install Rokit, then run: rokit install")
    destination = Path(__file__).resolve().parents[1] / ".tools"
    destination.mkdir(exist_ok=True)
    for name, version, repository, expected in TOOLS:
        url = f"https://github.com/{repository}/releases/download/v{version}/{name}-{version}-linux-x86_64.zip"
        with urllib.request.urlopen(url, timeout=60) as response:
            archive = response.read()
        if hashlib.sha256(archive).hexdigest() != expected:
            raise SystemExit(f"Integrity check failed for {name}; no binary installed")
        with zipfile.ZipFile(io.BytesIO(archive)) as package:
            entry = next(item for item in package.namelist() if Path(item).name == name)
            temporary = destination / (name + ".download")
            temporary.write_bytes(package.read(entry))
            temporary.chmod(0o755)
            temporary.replace(destination / name)
        print(f"Installed {name} {version} (SHA256 verified)")

if __name__ == "__main__":
    main()
