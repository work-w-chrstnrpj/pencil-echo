import json, math, os, sys
out = sys.argv[1]
assets = os.path.join(out, "Assets")
os.makedirs(assets, exist_ok=True)
W = 1024
CX, CY = 470, 590          # center of the annotation loop
RX, RY, ROT = 225, 190, -12  # loop size and tilt (degrees)

def loop_points(scale=1.0, start=-20, sweep=380, wobble=6, n=220):
    """A hand-drawn ellipse that overshoots its start, like a quick pen circle."""
    pts = []
    r = math.radians(ROT)
    for i in range(n + 1):
        t = math.radians(start + sweep * i / n)
        w = 1 + wobble / 1000 * math.sin(3 * t) + (0.04 * i / n)  # slight spiral: ends a little wider
        x, y = RX * scale * w * math.cos(t), RY * scale * w * math.sin(t)
        pts.append((CX + x * math.cos(r) - y * math.sin(r), CY + x * math.sin(r) + y * math.cos(r)))
    return pts

def path(pts):
    d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
    for x, y in pts[1:]:
        d += f" L{x:.1f},{y:.1f}"
    return d

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" viewBox="0 0 {W} {W}">{body}</svg>\n'

def write(name, body):
    open(os.path.join(assets, name), "w").write(svg(body))

# Echoes: partial arcs outside the loop, fading outward (opacity set per layer).
write("echo-outer.svg", f'<path d="{path(loop_points(1.62, 120, 150, 0))}" fill="none" stroke="#FFFFFF" stroke-width="22" stroke-linecap="round"/>')
write("echo-inner.svg", f'<path d="{path(loop_points(1.30, 105, 175, 0))}" fill="none" stroke="#FFFFFF" stroke-width="30" stroke-linecap="round"/>')
# The annotation loop the pencil just drew.
loop = loop_points(1.0)
write("annotation.svg", f'<path d="{path(loop)}" fill="none" stroke="#FFFFFF" stroke-width="46" stroke-linecap="round" stroke-linejoin="round"/>')

# Pencil: tip at the loop's end, body running up and to the right.
tipx, tipy = loop[-1]
ang = -60  # degrees; body points up-right
body = (
    f'<g transform="translate({tipx:.1f},{tipy:.1f}) rotate({ang}) scale(0.8)">'
    '<path d="M0,0 L150,-56 L150,56 Z" fill="#E9ECF5"/>'                 # sharpened wood cone
    '<path d="M0,0 L44,-16.5 L44,16.5 Z" fill="#2B2F45"/>'                # graphite tip
    '<rect x="150" y="-56" width="300" height="112" rx="0" fill="#FFFFFF"/>'  # body
    '<path d="M450,-56 h20 a56,56 0 0 1 0,112 h-20 Z" fill="#FFFFFF"/>'   # rounded end
    '<rect x="400" y="-56" width="14" height="112" fill="#C9CEDF"/>'      # band, like a pencil's flat edge
    '</g>'
)
write("pencil.svg", body)

def star(cx, cy, r, inner=0.28):
    """Four-point sparkle with concave sides."""
    k = r * inner
    return (f"M{cx},{cy-r} C{cx+k*0.4},{cy-k} {cx+k},{cy-k*0.4} {cx+r},{cy} "
            f"C{cx+k},{cy+k*0.4} {cx+k*0.4},{cy+k} {cx},{cy+r} "
            f"C{cx-k*0.4},{cy+k} {cx-k},{cy+k*0.4} {cx-r},{cy} "
            f"C{cx-k},{cy-k*0.4} {cx-k*0.4},{cy-k} {cx},{cy-r} Z")
write("sparkle.svg", f'<path d="{star(CX-10, CY+5, 150)}" fill="#FFC93C"/><path d="{star(CX+92, CY-88, 44)}" fill="#FFE08A"/>')

doc = {
    "fill": {"linear-gradient": ["srgb:0.21961,0.15686,0.60392,1.00000", "srgb:0.05490,0.45098,1.00000,1.00000"],
             "orientation": {"start": {"x": 0.5, "y": 0.0}, "stop": {"x": 0.5, "y": 1.0}}},
    "groups": [
        {"name": "Spark", "layers": [{"name": "sparkle", "image-name": "sparkle.svg", "glass": True}],
         "shadow": {"kind": "neutral", "opacity": 0.5}, "translucency": {"enabled": True, "value": 0.3}, "specular": True},
        {"name": "Pencil", "layers": [{"name": "pencil", "image-name": "pencil.svg", "glass": True}],
         "shadow": {"kind": "neutral", "opacity": 0.5}, "translucency": {"enabled": True, "value": 0.2}, "specular": True},
        {"name": "Annotation", "layers": [
            {"name": "annotation", "image-name": "annotation.svg", "glass": True},
            {"name": "echo inner", "image-name": "echo-inner.svg", "glass": True, "opacity": 0.55},
            {"name": "echo outer", "image-name": "echo-outer.svg", "glass": True, "opacity": 0.3}],
         "shadow": {"kind": "neutral", "opacity": 0.4}, "translucency": {"enabled": True, "value": 0.4}, "specular": True},
    ],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}
json.dump(doc, open(os.path.join(out, "icon.json"), "w"), indent=2)
print("wrote", out)
