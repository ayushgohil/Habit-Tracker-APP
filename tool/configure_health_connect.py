"""Prepares the generated android/ project for Health Connect.

Health Connect needs: read permissions, a <queries> entry, a permissions
rationale intent on the main activity, a privacy-policy activity alias,
a FlutterFragmentActivity main activity, and minSdk 26.
"""
import re
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://schemas.android.com/apk/res/android"
ANDROID = "{%s}" % NS
ET.register_namespace("android", NS)

main = Path("android/app/src/main")

# --- MainActivity must extend FlutterFragmentActivity ---------------------
activity = next(main.glob("kotlin/**/MainActivity.kt"), None) or next(main.glob("java/**/MainActivity.*"))
code = activity.read_text()
if "FlutterFragmentActivity" not in code:
    code = code.replace(
        "import io.flutter.embedding.android.FlutterActivity",
        "import io.flutter.embedding.android.FlutterFragmentActivity",
    )
    code = re.sub(r"\bFlutterActivity\(\)", "FlutterFragmentActivity()", code)
    activity.write_text(code)

# --- Manifest ---------------------------------------------------------------
manifest = main / "AndroidManifest.xml"
tree = ET.parse(manifest)
root = tree.getroot()
application = root.find("application")

existing = {n.get(ANDROID + "name") for n in root.findall("uses-permission")}
for permission in [
    "android.permission.health.READ_STEPS",
    "android.permission.health.READ_EXERCISE",
    "android.permission.health.READ_SLEEP",
]:
    if permission not in existing:
        ET.SubElement(root, "uses-permission", {ANDROID + "name": permission})

queries = root.find("queries")
if queries is None:
    queries = ET.SubElement(root, "queries")
if not any(p.get(ANDROID + "name") == "com.google.android.apps.healthdata" for p in queries.findall("package")):
    ET.SubElement(queries, "package", {ANDROID + "name": "com.google.android.apps.healthdata"})
rationale = "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"
if not any(
    a.get(ANDROID + "name") == rationale for i in queries.findall("intent") for a in i.findall("action")
):
    intent = ET.SubElement(queries, "intent")
    ET.SubElement(intent, "action", {ANDROID + "name": rationale})

main_activity = next(
    a for a in application.findall("activity") if (a.get(ANDROID + "name") or "").endswith("MainActivity")
)
if not any(
    a.get(ANDROID + "name") == rationale
    for f in main_activity.findall("intent-filter")
    for a in f.findall("action")
):
    f = ET.SubElement(main_activity, "intent-filter")
    ET.SubElement(f, "action", {ANDROID + "name": rationale})

alias_name = "ViewPermissionUsageActivity"
if not any(a.get(ANDROID + "name") == alias_name for a in application.findall("activity-alias")):
    alias = ET.SubElement(application, "activity-alias", {
        ANDROID + "name": alias_name,
        ANDROID + "exported": "true",
        ANDROID + "targetActivity": main_activity.get(ANDROID + "name"),
        ANDROID + "permission": "android.permission.START_VIEW_PERMISSION_USAGE",
    })
    f = ET.SubElement(alias, "intent-filter")
    ET.SubElement(f, "action", {ANDROID + "name": "android.intent.action.VIEW_PERMISSION_USAGE"})
    ET.SubElement(f, "category", {ANDROID + "name": "android.intent.category.HEALTH_PERMISSIONS"})
tree.write(manifest, encoding="utf-8", xml_declaration=True)

# --- minSdk 26 ----------------------------------------------------------------
app = Path("android/app")
gradle = app / "build.gradle.kts"
if not gradle.exists():
    gradle = app / "build.gradle"
text = gradle.read_text()
text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 26")
text = text.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 26")
gradle.write_text(text)
print("Prepared Android project for Health Connect")
