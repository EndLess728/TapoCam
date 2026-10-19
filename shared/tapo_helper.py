"""Line-oriented JSON bridge between the desktop apps (macOS, Windows) and pytapo.

Reads one request per line on stdin:  {"id": 1, "cmd": "move", "args": {"x": 10, "y": 0}}
Writes one reply per line on stdout:  {"id": 1, "ok": true, "result": ...}
"""

import json
import sys
import traceback

try:
    from pytapo import Tapo
except Exception as e:  # pragma: no cover - reported to the app
    print(json.dumps({"id": 0, "ok": False, "error": f"pytapo import failed: {e}"}), flush=True)
    sys.exit(1)

cam = None


def safe(fn, default=None):
    try:
        return fn()
    except Exception:
        return default


def status():
    privacy = safe(lambda: cam.getPrivacyMode().get("enabled") == "on")
    led = safe(lambda: cam.getLED().get("enabled") == "on")
    daynight = safe(lambda: cam.getDayNightMode())
    motion = safe(lambda: cam.getMotionDetection().get("enabled") == "on")
    flip = safe(lambda: cam.getImageFlipVertical())
    presets = safe(lambda: cam.getPresets(), {}) or {}
    info = safe(lambda: cam.getBasicInfo()["device_info"]["basic_info"], {}) or {}
    return {
        "privacy": privacy,
        "led": led,
        "dayNight": daynight if isinstance(daynight, str) else None,
        "motion": motion,
        "flip": flip if isinstance(flip, bool) else None,
        "presets": [{"id": str(k), "name": str(v)} for k, v in presets.items()],
        "model": info.get("device_model"),
        "name": info.get("device_alias"),
        "firmware": info.get("sw_version"),
    }


def handle(cmd, a):
    global cam
    if cmd == "connect":
        cam = Tapo(a["host"], a.get("user") or "admin", a["password"], a.get("cloudPassword") or "",
                   printDebugInformation=False, printWarnInformation=False)
        return status()
    if cam is None:
        raise RuntimeError("not connected")
    if cmd == "status":
        return status()
    if cmd == "move":
        return cam.moveMotor(a.get("x", 0), a.get("y", 0))
    if cmd == "calibrate":
        return cam.calibrateMotor()
    if cmd == "presetGoto":
        return cam.setPreset(a["id"])
    if cmd == "presetSave":
        cam.savePreset(a["name"])
        return status()["presets"]
    if cmd == "presetDelete":
        cam.deletePreset(a["id"])
        return status()["presets"]
    if cmd == "privacy":
        return cam.setPrivacyMode(bool(a["on"]))
    if cmd == "led":
        return cam.setLEDEnabled(bool(a["on"]))
    if cmd == "dayNight":
        return cam.setDayNightMode(a["mode"])
    if cmd == "motion":
        return cam.setMotionDetection(bool(a["on"]))
    if cmd == "flip":
        return cam.setImageFlipVertical(bool(a["on"]))
    if cmd == "alarm":
        return cam.startManualAlarm() if a["on"] else cam.stopManualAlarm()
    if cmd == "reboot":
        return cam.reboot()
    raise ValueError(f"unknown command {cmd}")


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    req = {}
    try:
        req = json.loads(line)
        result = handle(req.get("cmd"), req.get("args") or {})
        reply = {"id": req.get("id"), "ok": True, "result": result}
    except Exception as e:
        traceback.print_exc(file=sys.stderr)
        reply = {"id": req.get("id"), "ok": False, "error": str(e) or e.__class__.__name__}
    print(json.dumps(reply, default=str), flush=True)
