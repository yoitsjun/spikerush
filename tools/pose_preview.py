#!/usr/bin/env python3
"""Preview intro poses (or any static pose) without a Studio screenshot.

Studio poses a clone of the player's real avatar and posts every body part's box here; this
draws them as shaded boxes from the intro camera (front, a little right and low) and from the
side, one panel per pose. Right-side limbs are tinted red, left-side blue.

  python tools/pose_preview.py serve [folder]              # receive posts on 127.0.0.1:34991
  python tools/pose_preview.py render poses.json out.png [panelW panelH]

In a playtest, run this in the Server datamodel (Studio's execute_luau / command bar), with the
poses to try as { name, { Joint = { x, y, z } degrees, drop = studs } } like POSE_DEFS in
AnimationController (HttpService is switched on for the post and back off after):

  local POSES = { { "Arms", { Waist = { 4, 0, 0 }, LeftShoulder = { 12, -75, -4 }, ... } } }
  local HttpService = game:GetService("HttpService")
  local char = game.Players:GetPlayers()[1].Character
  local JOINT = { LowerTorso = "Root", UpperTorso = "Waist", Head = "Neck",
      LeftUpperArm = "LeftShoulder", LeftLowerArm = "LeftElbow", LeftHand = "LeftWrist",
      RightUpperArm = "RightShoulder", RightLowerArm = "RightElbow", RightHand = "RightWrist",
      LeftUpperLeg = "LeftHip", LeftLowerLeg = "LeftKnee", LeftFoot = "LeftAnkle",
      RightUpperLeg = "RightHip", RightLowerLeg = "RightKnee", RightFoot = "RightAnkle" }
  char.Archivable = true
  local model = char:Clone()
  local root = model.HumanoidRootPart
  local byPart0 = {}
  for _, d in ipairs(model:GetDescendants()) do
      local j
      if d:IsA("Motor6D") and d.Part0 and d.Part1 then
          j = { p0 = d.Part0, p1 = d.Part1, c0 = d.C0, c1 = d.C1 }
      elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
          j = { p0 = d.Attachment0.Parent, p1 = d.Attachment1.Parent,
                c0 = d.Attachment0.CFrame, c1 = d.Attachment1.CFrame }
      end
      if j then byPart0[j.p0] = byPart0[j.p0] or {}; table.insert(byPart0[j.p0], j) end
  end
  local standY = model.Humanoid.HipHeight + root.Size.Y / 2
  local out = { poses = {} }
  for _, p in ipairs(POSES) do
      local joints = {}
      for k, a in pairs(p[2]) do
          if k ~= "drop" then
              joints[k] = CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
          end
      end
      if p[2].drop then joints.Root = CFrame.new(0, -p[2].drop, 0) end
      root.CFrame = CFrame.new(0, standY, 0)
      local queue, seen, i = { root }, { [root] = true }, 1
      while queue[i] do
          local p0 = queue[i]; i = i + 1
          for _, j in ipairs(byPart0[p0] or {}) do
              if not seen[j.p1] then
                  seen[j.p1] = true
                  local rot = joints[JOINT[j.p1.Name] or ""] or CFrame.identity
                  j.p1.CFrame = p0.CFrame * j.c0 * rot * j.c1:Inverse()
                  table.insert(queue, j.p1)
              end
          end
      end
      local parts = {}
      for _, d in ipairs(model:GetChildren()) do
          if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
              local c = { d.CFrame:GetComponents() }
              table.insert(parts, { n = d.Name, p = { c[1], c[2], c[3] },
                  r = { c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12] },
                  s = { d.Size.X, d.Size.Y, d.Size.Z } })
          end
      end
      table.insert(out.poses, { name = p[1], parts = parts })
  end
  model:Destroy()
  HttpService.HttpEnabled = true
  HttpService:PostAsync("http://127.0.0.1:34991/save/poses.json", HttpService:JSONEncode(out))
  HttpService.HttpEnabled = false

Joint conventions (degrees, applied Z then Y then X): +X swings a shoulder or hip forward and up;
+Z raises the right arm sideways, -Z the left; +X bends an elbow, -X a knee; -X on the waist
leans forward; +X on the neck tips the head back; +Y on the waist turns the chest to the left.
"""
import json
import math
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

COLORS = {
    "Head": (236, 200, 170),
    "UpperTorso": (230, 230, 236),
    "LowerTorso": (60, 60, 70),
    "LeftUpperArm": (225, 225, 232), "RightUpperArm": (225, 225, 232),
    "LeftLowerArm": (236, 200, 170), "RightLowerArm": (236, 200, 170),
    "LeftHand": (236, 200, 170), "RightHand": (236, 200, 170),
    "LeftUpperLeg": (55, 55, 64), "RightUpperLeg": (55, 55, 64),
    "LeftLowerLeg": (55, 55, 64), "RightLowerLeg": (55, 55, 64),
    "LeftFoot": (240, 240, 240), "RightFoot": (240, 240, 240),
}
FACES = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]


def tint(name, c):
    if name.startswith("Left"):
        return (int(c[0] * 0.8), int(c[1] * 0.85), min(255, int(c[2] * 1.1) + 20))
    if name.startswith("Right"):
        return (min(255, int(c[0] * 1.05) + 20), int(c[1] * 0.8), int(c[2] * 0.8))
    return c


def corners(p, r, s):
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    out = []
    for dx in (-hx, hx):
        for dy in (-hy, hy):
            for dz in (-hz, hz):
                out.append((p[0] + r[0] * dx + r[1] * dy + r[2] * dz,
                            p[1] + r[3] * dx + r[4] * dy + r[5] * dz,
                            p[2] + r[6] * dx + r[7] * dy + r[8] * dz))
    return out


def basis(eye, target):
    f = [target[i] - eye[i] for i in range(3)]
    m = math.sqrt(sum(v * v for v in f))
    f = [v / m for v in f]
    rx = [f[1] * 0 - f[2] * 1, f[2] * 0 - f[0] * 0, f[0] * 1 - f[1] * 0]
    m = math.sqrt(sum(v * v for v in rx))
    rx = [v / m for v in rx]
    ux = [rx[1] * f[2] - rx[2] * f[1], rx[2] * f[0] - rx[0] * f[2], rx[0] * f[1] - rx[1] * f[0]]
    return f, rx, ux


def draw_view(draw, parts, eye, target, box, fov=32, light=(-0.5, -0.8, -0.4)):
    f, rx, ux = basis(eye, target)
    x0, y0, w, h = box
    t = math.tan(math.radians(fov) / 2)
    lm = math.sqrt(sum(v * v for v in light))
    L = [-v / lm for v in light]
    polys = []
    for part in parts:
        cs = corners(part["p"], part["r"], part["s"])
        cam = []
        for c in cs:
            d = [c[i] - eye[i] for i in range(3)]
            cam.append((sum(d[i] * rx[i] for i in range(3)), sum(d[i] * ux[i] for i in range(3)),
                        sum(d[i] * f[i] for i in range(3)), c))
        base = tint(part["n"], COLORS.get(part["n"], (200, 200, 200)))
        for face in FACES:
            pts = [cam[i] for i in face]
            a, b, c = pts[0][3], pts[1][3], pts[2][3]
            u = [b[i] - a[i] for i in range(3)]
            v = [c[i] - a[i] for i in range(3)]
            n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
            nm = math.sqrt(sum(k * k for k in n)) or 1
            n = [k / nm for k in n]
            fc = [sum(p[3][k] for p in pts) / 4 for k in range(3)]
            out = [fc[k] - part["p"][k] for k in range(3)]
            if sum(n[k] * out[k] for k in range(3)) < 0:
                n = [-k for k in n]
            view = [fc[k] - eye[k] for k in range(3)]
            if sum(n[k] * view[k] for k in range(3)) >= 0:
                continue
            shade = 0.45 + 0.55 * max(0.0, sum(n[k] * L[k] for k in range(3)))
            col = tuple(int(min(255, k * shade)) for k in base)
            scr = []
            for (x, y, z, _) in pts:
                if z <= 0.1:
                    break
                scr.append((x0 + w / 2 + (x / (z * t)) * (h / 2), y0 + h / 2 - (y / (z * t)) * (h / 2)))
            if len(scr) == 4:
                polys.append((sum(p[2] for p in pts) / 4, scr, col))
    polys.sort(key=lambda q: -q[0])
    for _, scr, col in polys:
        draw.polygon(scr, fill=col, outline=(20, 20, 26))


def render(src, dst, pw=300, ph=420):
    from PIL import Image, ImageDraw, ImageFont
    poses = json.load(open(src, encoding="utf-8"))["poses"]
    img = Image.new("RGB", (pw * len(poses), ph * 2 + 30), (38, 44, 64))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for i, pose in enumerate(poses):
        parts = pose["parts"]
        cy = sum(p["p"][1] for p in parts) / len(parts)
        target = (0, cy, 0)
        # the character faces -z: the intro camera stands in front, a little right and low
        draw_view(draw, parts, (4.2, cy - 0.5, -13), target, (i * pw, 30, pw, ph))
        draw_view(draw, parts, (13, cy, 0), target, (i * pw, 30 + ph, pw, ph))
        draw.text((i * pw + 8, 6), pose["name"], fill=(255, 220, 90), font=font)
        draw.line([(i * pw, 0), (i * pw, img.height)], fill=(20, 22, 30), width=2)
    img.save(dst)
    print("saved", dst, img.size)


def serve(folder):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            m = re.match(r"^/save/([A-Za-z0-9_.-]+)$", self.path)
            if not m:
                self.send_response(404)
                self.end_headers()
                return
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            with open(os.path.join(folder, m.group(1)), "wb") as f:
                f.write(body)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, *args):
            pass

    print("receiving on http://127.0.0.1:34991/save/<name> into", folder)
    HTTPServer(("127.0.0.1", 34991), Handler).serve_forever()


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "serve":
        serve(sys.argv[2] if len(sys.argv) > 2 else os.getcwd())
    elif len(sys.argv) >= 4 and sys.argv[1] == "render":
        size = (int(sys.argv[4]), int(sys.argv[5])) if len(sys.argv) > 5 else (300, 420)
        render(sys.argv[2], sys.argv[3], *size)
    else:
        print(__doc__)
