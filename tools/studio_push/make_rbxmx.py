"""push.json -> an .rbxmx model Studio can load with game:GetObjects("rbxasset://..."): one
ModuleScript per item, its Source the item's JSON (text only, never run).
usage: make_rbxmx.py <push.json> <out.rbxmx>"""
import io, json, sys

items = json.load(io.open(sys.argv[1], encoding="utf-8"))
parts = ['<roblox version="4">', '<Item class="Folder" referent="RBX0"><Properties><string name="Name">ClaudePush</string></Properties>']
for i, it in enumerate(items):
    body = json.dumps(it)
    assert "]]>" not in body
    parts.append('<Item class="ModuleScript" referent="RBX%d"><Properties><string name="Name">Item%03d</string><ProtectedString name="Source"><![CDATA[%s]]></ProtectedString></Properties></Item>' % (i + 1, i + 1, body))
parts.append("</Item>")
parts.append("</roblox>")
with io.open(sys.argv[2], "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(parts))
print("wrote", sys.argv[2], len(items), "items")
