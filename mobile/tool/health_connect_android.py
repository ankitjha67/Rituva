#!/usr/bin/env python3
"""Patch a freshly-scaffolded Flutter android/ directory for the `health` package
(Health Connect). android/ is gitignored and regenerated (locally and in CI), so
this runs after `flutter create` to inject the Health-Connect requirements:

  1. app/build.gradle.kts : minSdk -> 26 (the health plugin's minimum)
  2. MainActivity.kt       : FlutterActivity -> FlutterFragmentActivity
  3. AndroidManifest.xml    : READ_STEPS / READ_ACTIVE_CALORIES_BURNED permissions,
                              the Health-Connect <queries>, and the Android-14
                              VIEW_PERMISSION_USAGE activity-alias.

Idempotent: running it twice is a no-op. Usage:  python tool/health_connect_android.py android
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "android")


def patch(path: pathlib.Path, change) -> None:
    if not path.exists():
        print(f"  skip (missing): {path}")
        return
    text = path.read_text(encoding="utf-8")
    new = change(text)
    if new != text:
        path.write_text(new, encoding="utf-8")
        print(f"  patched: {path}")
    else:
        print(f"  already ok: {path}")


# 1. minSdk 26 ---------------------------------------------------------------
def min_sdk(t: str) -> str:
    if "minSdk = 26" in t:
        return t
    return t.replace("minSdk = flutter.minSdkVersion", "minSdk = 26")


# 2. FlutterFragmentActivity --------------------------------------------------
def fragment_activity(t: str) -> str:
    return (t.replace("import io.flutter.embedding.android.FlutterActivity",
                      "import io.flutter.embedding.android.FlutterFragmentActivity")
             .replace("class MainActivity : FlutterActivity()",
                      "class MainActivity : FlutterFragmentActivity()"))


# 3. Manifest ----------------------------------------------------------------
_PERMS = (
    '    <uses-permission android:name="android.permission.health.READ_STEPS"/>\n'
    '    <uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>\n'
)
_ALIAS = (
    '        <activity-alias\n'
    '            android:name="ViewPermissionUsageActivity"\n'
    '            android:exported="true"\n'
    '            android:targetActivity=".MainActivity"\n'
    '            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">\n'
    '            <intent-filter>\n'
    '                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />\n'
    '                <category android:name="android.intent.category.HEALTH_PERMISSIONS" />\n'
    '            </intent-filter>\n'
    '        </activity-alias>\n'
)
_HC_QUERIES = (
    '    <queries>\n'
    '        <package android:name="com.google.android.apps.healthdata" />\n'
    '        <intent>\n'
    '            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />\n'
    '        </intent>\n'
    '    </queries>\n'
)
_RATIONALE = (
    '            <intent-filter>\n'
    '                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />\n'
    '            </intent-filter>\n'
)


def manifest(t: str) -> str:
    if "health.READ_STEPS" in t:
        return t  # already patched
    # permissions right after the INTERNET one (or after the opening <manifest ...>)
    if '<uses-permission android:name="android.permission.INTERNET"/>\n' in t:
        t = t.replace('<uses-permission android:name="android.permission.INTERNET"/>\n',
                      '<uses-permission android:name="android.permission.INTERNET"/>\n' + _PERMS, 1)
    else:
        t = t.replace("<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n",
                      "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n" + _PERMS, 1)
    # rationale intent-filter inside MainActivity (after the LAUNCHER filter)
    launcher = ('            <intent-filter>\n'
                '                <action android:name="android.intent.action.MAIN"/>\n'
                '                <category android:name="android.intent.category.LAUNCHER"/>\n'
                '            </intent-filter>\n')
    if launcher in t:
        t = t.replace(launcher, launcher + _RATIONALE, 1)
    # activity-alias before </application>, HC queries before </manifest>
    t = t.replace("    </application>\n", _ALIAS + "    </application>\n", 1)
    t = t.replace("</manifest>", _HC_QUERIES + "</manifest>", 1)
    return t


print("Patching android/ for Health Connect…")
patch(root / "app" / "build.gradle.kts", min_sdk)
for mainact in root.glob("app/src/main/kotlin/**/MainActivity.kt"):
    patch(mainact, fragment_activity)
patch(root / "app" / "src" / "main" / "AndroidManifest.xml", manifest)
print("done.")
