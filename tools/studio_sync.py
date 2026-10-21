"""Print a Luau snippet (for the Studio MCP's execute_luau, Edit datamodel) that pulls every src/*.lua
file changed between two commits into Studio from GitHub raw, each only if Studio's copy hashes to the
base commit's version (a script edited in Studio is skipped and reported). Usage: studio_sync.py BASE NEW"""
import subprocess, sys

base, new = sys.argv[1], sys.argv[2]
files = subprocess.run(["git", "diff", "--name-only", base, new, "--", "src"], capture_output=True, text=True).stdout.split()
files = [f for f in files if f.endswith(".lua")]
sha = subprocess.run(["git", "rev-parse", "--short", new], capture_output=True, text=True).stdout.strip()

def h(b):
    x = 5381
    for c in b:
        x = (x * 33 + c) % 4294967296
    return x

def blob(rev, f):
    r = subprocess.run(["git", "show", rev + ":" + f], capture_output=True)
    return r.stdout.replace(b"\r\n", b"\n") if r.returncode == 0 else None

rows = []
for f in files:
    b, n = blob(base, f), blob(new, f)
    if n is None:
        continue
    rows.append('{"%s",%s,%d}' % (f, str(h(b)) if b is not None else "nil", h(n)))

print('''local SHA = "%s"
local ROWS = {%s}
local H = game:GetService("HttpService")
local CRLF, LF = string.char(13, 10), string.char(10)
local function hash(s) s = s:gsub(CRLF, LF) local x = 5381 for i = 1, #s do x = (x * 33 + s:byte(i)) %% 4294967296 end return x end
local function strip(s) s = s:gsub("%%.server%%.lua$", "") s = s:gsub("%%.client%%.lua$", "") s = s:gsub("%%.lua$", "") return s end
local function resolve(f)
  local parts = string.split(f, "/")
  if parts[2] == "first" then return game.ReplicatedFirst:FindFirstChild("LoadingScreen") end
  local inst = (parts[2] == "shared" and game.ReplicatedStorage:FindFirstChild("Shared")) or (parts[2] == "server" and game:GetService("ServerScriptService"):FindFirstChild("Server")) or (parts[2] == "client" and game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Client"))
  for i = 3, #parts do if not inst then return nil end inst = inst:FindFirstChild(strip(parts[i])) end
  return inst
end
local was = H.HttpEnabled H.HttpEnabled = true
local out = {}
for _, r in ipairs(ROWS) do
  local inst = resolve(r[1])
  if not inst then table.insert(out, r[1] .. " MISSING (new script? create it by hand)")
  else
    local cur = hash(inst.Source)
    if cur == r[3] then table.insert(out, r[1] .. " already")
    elseif r[2] and cur ~= r[2] then table.insert(out, r[1] .. " SKIP " .. cur)
    else
      local ok, src = pcall(function() return H:GetAsync("https://raw.githubusercontent.com/yoitsjun/spikerush/" .. SHA .. "/" .. r[1]) end)
      if not ok then table.insert(out, r[1] .. " fetch fail")
      elseif hash(src) ~= r[3] then table.insert(out, r[1] .. " mismatch")
      else game:GetService("ScriptEditorService"):UpdateSourceAsync(inst, function() return src end) table.insert(out, r[1] .. " updated") end
    end
  end
  task.wait()
end
H.HttpEnabled = was
return table.concat(out, LF)''' % (sha, ",".join(rows)))
