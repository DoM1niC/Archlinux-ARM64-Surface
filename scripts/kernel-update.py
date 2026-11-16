#!/usr/bin/env python3
"""Bringt kernel/PKGBUILD auf eine Version von linux-surface (aarch64).

Holt das PKGBUILD des gewünschten Tags von linux-surface/aarch64-packages
(Vorgabe: der neueste Tag linux_surface-*), übernimmt Quellstand und
Konfigurationsstände, kopiert overrides.config, Preset und Install-Datei,
berechnet die Prüfsummen und wählt die eigene Revision (pkgrel X.N):

  - Gibt es die Version X in der Paketregistry noch nicht: N = 1.
  - Gibt es sie schon: ohne --force nichts zu tun (Status "uptodate"),
    mit --force die nächste freie Revision.

Bricht ab, wenn linux-surface die Quellen seines PKGBUILD umgebaut hat; dann
muss kernel/PKGBUILD von Hand angeglichen werden.

Ergebnis als KEY=WERT-Zeilen in --status (STATUS, VERSION, KERNELRELEASE, TAG).
Läuft im Build-Container (scripts/kernel-in-container.sh), geht aber auch
direkt auf dem Host.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request

UPSTREAM = "linux-surface/aarch64-packages"
RAW = f"https://raw.githubusercontent.com/{UPSTREAM}"
TAGS_API = f"https://api.github.com/repos/{UPSTREAM}/tags?per_page=100"
AUX_FILES = ["overrides.config", "linux-surface.preset", "linux-surface.install"]

# Erwartete Quellen im PKGBUILD von linux-surface (Refs als Platzhalter)
EXPECTED_SOURCES = [
    '"kernel::git+https://github.com/linux-surface/kernel.git#commit=${_ref_ksource}"',
    '"base.config::https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/${_ref_config_base}/core/linux-aarch64/config"',
    '"surface.config::https://raw.githubusercontent.com/qzed/aarch64-kernel-configs/${_ref_config_surface}/fragments/spx.config"',
    '"overrides.config"',
    '"linux-surface.preset"',
]


def die(msg):
    print(f"FEHLER: {msg}", file=sys.stderr)
    sys.exit(1)


def fetch(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": "surface-kernel-update", **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def download(url, dest):
    """Lädt url nach dest und gibt die SHA-256 zurück (vorhandene Datei wird wiederverwendet)."""
    h = hashlib.sha256()
    if not os.path.exists(dest):
        tmp = dest + ".part"
        req = urllib.request.Request(url, headers={"User-Agent": "surface-kernel-update"})
        with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
        os.replace(tmp, dest)
    with open(dest, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def version_key(tag):
    return [int(x) for x in re.findall(r"\d+", tag)]


def latest_tag():
    tags = [t["name"] for t in json.loads(fetch(TAGS_API)) if t["name"].startswith("linux_surface-")]
    if not tags:
        die("keine linux_surface-Tags gefunden")
    return max(tags, key=version_key)


def pkgbuild_var(text, name):
    m = re.search(rf'^{name}="?([^"\n]*)"?\s*$', text, re.M)
    if not m:
        die(f"{name} nicht im PKGBUILD von linux-surface gefunden")
    return m.group(1)


def pkgbuild_array(text, name):
    m = re.search(rf"^{name}=\((.*?)\)", text, re.M | re.S)
    if not m:
        die(f"{name}=() nicht gefunden")
    return re.findall(r'"[^"]*"|\'[^\']*\'', m.group(1))


def existing_revisions(base, registry, owner, token):
    """Revisionen N, für die linux-surface base.N schon in der Registry liegt."""
    revs = set()
    if token:
        api = f"{registry}/api/v1/packages/{owner}/arch/linux-surface"
        n = 1
        while True:
            try:
                fetch(f"{api}/{base}.{n}", {"Authorization": f"token {token}"})
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    break
                raise
            revs.add(n)
            n += 1
        return revs
    # ohne Token: die öffentliche Repository-Datenbank (enthält die neueste Version)
    try:
        db = fetch(f"{registry}/api/packages/{owner}/arch/surface-kernel/aarch64/surface-kernel.db")
    except urllib.error.HTTPError:
        return revs
    with tempfile.NamedTemporaryFile() as f:
        f.write(db)
        f.flush()
        with tarfile.open(f.name) as t:
            for name in t.getnames():
                m = re.fullmatch(rf"linux-surface-{re.escape(base)}\.(\d+)/desc", name)
                if m:
                    revs.add(int(m.group(1)))
    return revs


def set_var(text, name, value):
    new, n = re.subn(rf'^{name}=.*$', f'{name}="{value}"', text, count=1, flags=re.M)
    if n != 1:
        die(f"{name} nicht in kernel/PKGBUILD gefunden")
    return new


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="Ordner mit dem PKGBUILD (wird geändert)")
    ap.add_argument("--tag", default="latest", help="linux_surface-X.Y.Z-N oder latest")
    ap.add_argument("--force", action="store_true", help="neue Revision, auch wenn die Version schon gebaut ist")
    ap.add_argument("--srcdest", default=None, help="Quellen-Cache (wie SRCDEST von makepkg)")
    ap.add_argument("--status", required=True, help="Datei für das Ergebnis")
    ap.add_argument("--registry", default=os.environ.get("GITEA_URL", "https://git.3dns.eu"))
    ap.add_argument("--owner", default=os.environ.get("GITEA_OWNER", "dom1nic"))
    args = ap.parse_args()
    token = os.environ.get("GITEA_TOKEN", "")

    tag = latest_tag() if args.tag in ("", "latest") else args.tag
    if not tag.startswith("linux_surface-"):
        tag = "linux_surface-" + tag
    print(f"==> linux-surface: {tag}")
    try:
        up = fetch(f"{RAW}/{tag}/linux-surface/PKGBUILD").decode()
    except urllib.error.HTTPError as e:
        die(f"PKGBUILD für {tag} nicht abrufbar ({e.code})")

    sources = pkgbuild_array(up, "source")
    if [s.strip() for s in sources] != EXPECTED_SOURCES:
        die("linux-surface hat die Quellen seines PKGBUILD geändert:\n  " + "\n  ".join(sources)
            + "\nkernel/PKGBUILD muss von Hand angeglichen werden.")

    pkgver = pkgbuild_var(up, "pkgver")
    uprel = pkgbuild_var(up, "pkgrel")
    refs = {k: pkgbuild_var(up, k) for k in ("_ref_ksource", "_ref_config_base", "_ref_config_surface")}
    base = f"{pkgver}-{uprel}"

    revs = existing_revisions(base, args.registry, args.owner, token)
    if revs and not args.force:
        version = f"{base}.{max(revs)}"
        print(f"==> {version} liegt schon in der Registry, nichts zu tun (neu bauen: --force)")
        with open(args.status, "w") as f:
            f.write(f"STATUS=uptodate\nVERSION={version}\nTAG={tag}\n")
        return
    rev = max(revs) + 1 if revs else 1
    version = f"{base}.{rev}"
    print(f"==> baue linux-surface {version} (Kernel-Quellstand {refs['_ref_ksource'][:12]})")

    pkgdir = args.dir
    srcdest = args.srcdest or pkgdir
    os.makedirs(srcdest, exist_ok=True)

    # Hilfsdateien von linux-surface übernehmen
    for name in AUX_FILES:
        with open(os.path.join(pkgdir, name), "wb") as f:
            f.write(fetch(f"{RAW}/{tag}/linux-surface/{name}"))

    def sha_file(path):
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()

    tarball = f"linux-surface-{refs['_ref_ksource']}.tar.gz"
    print(f"==> lade Kernel-Quellen ({tarball})")
    sums = [
        download(f"https://github.com/linux-surface/kernel/archive/{refs['_ref_ksource']}.tar.gz",
                 os.path.join(srcdest, tarball)),
        hashlib.sha256(fetch("https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/"
                             f"{refs['_ref_config_base']}/core/linux-aarch64/config")).hexdigest(),
        hashlib.sha256(fetch("https://raw.githubusercontent.com/qzed/aarch64-kernel-configs/"
                             f"{refs['_ref_config_surface']}/fragments/spx.config")).hexdigest(),
        sha_file(os.path.join(pkgdir, "overrides.config")),
        "SKIP",
        sha_file(os.path.join(pkgdir, "linux-surface.preset")),
        "SKIP",
        "SKIP",
    ]

    path = os.path.join(pkgdir, "PKGBUILD")
    with open(path) as f:
        text = f.read()
    text = set_var(text, "pkgver", pkgver)
    text = re.sub(r'^_surfacerel=.*$', f'_surfacerel="{uprel}"                 # pkgrel von linux-surface, auf dem wir aufbauen',
                  text, count=1, flags=re.M)
    text = re.sub(r'^pkgrel=.*$', f'pkgrel="${{_surfacerel}}.{rev}"       # .N = eigene Revision', text, count=1, flags=re.M)
    for k, v in refs.items():
        text = set_var(text, k, v)
    old = pkgbuild_array(text, "sha256sums")
    if len(old) != len(sums):
        die(f"sha256sums in kernel/PKGBUILD hat {len(old)} Einträge, erwartet {len(sums)}")
    block = "sha256sums=(" + "\n            ".join(f"'{s}'" for s in sums) + ")"
    text = re.sub(r"^sha256sums=\(.*?\)", lambda _: block, text, count=1, flags=re.M | re.S)
    with open(path, "w") as f:
        f.write(text)

    with open(args.status, "w") as f:
        f.write(f"STATUS=build\nVERSION={version}\nKERNELRELEASE={version}-surface\nTAG={tag}\n")


if __name__ == "__main__":
    main()
