"""Read-only structural audit of PR #158 rfvehicle signal paths (stdlib only)."""
import json
import re
from pathlib import Path


def parse(text):
    root = {"name": "root", "values": {}, "children": [], "start": 0}
    stack = [root]
    for number, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if s.startswith("ENDGROUP["):
            assert len(stack) > 1 and stack[-1]["name"] == s[9:-1], (number, s)
            stack.pop()["end"] = number
        elif s.startswith("SUBGROUP[") or re.fullmatch(r"\[[^]]+\]", s):
            if s.startswith("SUBGROUP["):
                name = s[9:-1]
            else:
                assert len(stack) <= 2, (number, s)
                stack = [root]
                name = s[1:-1]
            node = {"name": name, "values": {}, "children": [], "start": number}
            stack[-1]["children"].append(node)
            stack.append(node)
        elif "=" in s:
            k, v = s.split("=", 1)
            stack[-1]["values"][k] = v
    return root


def descendants(node):
    yield node
    for child in node["children"]:
        yield from descendants(child)


def audit(path):
    root = parse(path.read_bytes().decode("latin-1"))
    sections = {c["name"]: c for c in root["children"]}
    electronics = {n["name"]: n["values"] for n in sections["VehicleElectronics"]["children"]}
    motors, surfaces = [], []
    for node in descendants(root):
        v = node["values"]
        if v.get("ComponentType") == "STRING:PropellerComponent":
            sid = v.get("ServoThrottle", "INT:0").split(":")[1]
            e = electronics.get("#" + sid, {})
            motors.append({"line": node["start"], "component": v.get("ComponentNameTSTRING"),
                           "frame": v.get("EngineTorusFrame"), "signal": sid,
                           "rx": e.get("ConnectTo_InternalName"), "label": e.get("UserNameTSTRING"),
                           "clockwise": v.get("ClockSpinsClockwiseFromRear"),
                           "reversed": v.get("ServoThrottleRev"), "brake": v.get("HasSpeedControlBrake")})
        if "ServoMaster" in v:
            surfaces.append({k: val for k, val in v.items() if k.startswith("Servo") or k.startswith("ComponentName")})
    outputs = sections["AirplaneSoftwareRadio"]["children"][0]["children"]
    radio = [{"channel": n["name"], "trim": n["values"].get("Trim"),
              "input_count": n["values"].get("InputFeedsArray"),
              "inputs": [c["values"]["InputChannel"] for c in descendants(n) if "InputChannel" in c["values"]]}
             for n in outputs]
    return {"file": str(path), "radio": radio, "motors": motors, "surfaces": surfaces, "electronics": electronics}


if __name__ == "__main__":
    base = Path(__file__).resolve().parents[1] / "artifacts/mfe-four-models/extracted"
    print(json.dumps([audit(p) for p in sorted(base.glob("*/*.rfvehicle"))], indent=2, ensure_ascii=False))
