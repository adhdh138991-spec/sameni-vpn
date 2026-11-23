#!/usr/bin/env python3
"""Generate a fresh Flutter Android host and overlay SAMENI's native branding."""
from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
ICONS = ROOT / "launcher_icons"


def run(command: list[str]) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def patch_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'android:label="[^"]*"', 'android:label="SAMENI VPN"', text)
    text = re.sub(r'android:icon="[^"]*"', 'android:icon="@mipmap/ic_launcher"', text)
    if "android:roundIcon=" in text:
        text = re.sub(r'android:roundIcon="[^"]*"', 'android:roundIcon="@mipmap/ic_launcher_round"', text)
    else:
        text = text.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@mipmap/ic_launcher" android:roundIcon="@mipmap/ic_launcher_round"',
            1,
        )
    if "android:usesCleartextTraffic=" not in text:
        text = text.replace('<application', '<application android:usesCleartextTraffic="false"', 1)
    for permission in (
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.POST_NOTIFICATIONS",
    ):
        if permission not in text:
            text = text.replace(
                "    <application",
                f'    <uses-permission android:name="{permission}" />\n    <application',
                1,
            )
    path.write_text(text, encoding="utf-8")


def patch_gradle(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'namespace\s*=\s*"[^"]+"', 'namespace = "com.sameni.vpn"', text)
    text = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.sameni.vpn"', text)
    if path.suffix == ".kts":
        text = re.sub(r'minSdk\s*=\s*[^\r\n]+', 'minSdk = 23', text)
        if "useLegacyPackaging" not in text:
            text = re.sub(
                r'(?m)^android\s*\{',
                'android {\n    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }',
                text,
                count=1,
            )
    else:
        text = re.sub(r'minSdkVersion\s+[^\r\n]+', 'minSdkVersion 23', text)
        if "useLegacyPackaging" not in text:
            text = re.sub(
                r'(?m)^android\s*\{',
                'android {\n    packaging {\n        jniLibs {\n            useLegacyPackaging true\n        }\n    }',
                text,
                count=1,
            )
    path.write_text(text, encoding="utf-8")


def main() -> None:
    if not ICONS.is_dir():
        raise SystemExit("launcher_icons folder is missing")

    with tempfile.TemporaryDirectory(prefix="sameni-android-") as tmp:
        scaffold = Path(tmp) / "host"
        run([
            "flutter", "create", "--no-pub", "--platforms=android",
            "--org", "com.sameni", "--project-name", "vpn", str(scaffold),
        ])
        fresh_android = scaffold / "android"
        if not fresh_android.is_dir():
            raise SystemExit("Flutter did not generate the Android host project")
        if ANDROID.exists():
            shutil.rmtree(ANDROID)
        shutil.copytree(fresh_android, ANDROID)

    app_res = ANDROID / "app" / "src" / "main" / "res"
    anydpi = app_res / "mipmap-anydpi-v26"
    if anydpi.exists():
        # Prefer the supplied raster launcher/round icons rather than template XML.
        shutil.rmtree(anydpi)
    for source in ICONS.glob("mipmap-*"):
        destination = app_res / source.name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination)

    manifest = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    gradle_kts = ANDROID / "app" / "build.gradle.kts"
    gradle_groovy = ANDROID / "app" / "build.gradle"
    patch_manifest(manifest)
    if gradle_kts.exists():
        patch_gradle(gradle_kts)
    elif gradle_groovy.exists():
        patch_gradle(gradle_groovy)
    else:
        raise SystemExit("Flutter scaffold did not contain app Gradle build file")

    print("Android host regenerated with SAMENI package ID, VPN-compatible packaging and Achaemenid icons.")


if __name__ == "__main__":
    main()
