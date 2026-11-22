"""Writes the CooldownCollaborator icon board (index.html) from make.py's candidates.
  python board.py <candidates dir> <CDCicon.png> > index.html
The picks block (picks.part.html, the same as WhisperCast's) is one row of buttons per section.look, saved to the
page's db collection "picks"."""
import base64, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "..")   # ~/Source
out, art = sys.argv[1], sys.argv[2]

def uri(path):
	mime = "image/png" if path.endswith(".png") else "image/jpeg"
	with open(path, "rb") as f:
		return f"data:{mime};base64," + base64.b64encode(f.read()).decode()

def small(path, px):   # the big picture, shrunk for the header
	b = io.BytesIO(); Image.open(path).convert("RGB").resize((px, px), Image.LANCZOS).save(b, "JPEG", quality=86)
	return "data:image/jpeg;base64," + base64.b64encode(b.getvalue()).decode()

CROPS = [
	("face", "Her face", "Close on the eyes and blue lips. The clearest at 18 px."),
	("head", "Head and ears", "A little wider: the long ears and the blue hair frame her."),
	("pair", "The pair", "Her and the blood elf in the bubble, as in the WhisperCast picture."),
	("crystal", "The staff crystal", "The violet crystal in its gold claws. A shape, not a face."),
	("bubble", "The blood elf", "The little one in the bubble, calling out."),
]
sq = {k: uri(f"{out}/{k}-icon-128.png") for k, _, _ in CROPS}
rd = {k: uri(f"{out}/{k}-minimap-128.png") for k, _, _ in CROPS}
cur_icon = uri(os.path.join(SRC, "CooldownCollaborator/Media/icon.png"))
cur_mini = uri(os.path.join(SRC, "CooldownCollaborator/Media/minimap.png"))
wc_icon = uri(os.path.join(SRC, "WhisperCast/Media/icon.png"))
wc_mini = uri(os.path.join(SRC, "WhisperCast/Media/minimap.png"))
cdtl_icon = uri(os.path.join(SRC, "cdtl3-dev/Media/icon-128.png"))
cdtl_mini = uri(os.path.join(SRC, "cdtl3-dev/Media/minimap.png"))
hero = small(art, 440)

def addons_mock(icon):
	rows = [(icon, "CooldownCollaborator"), (cdtl_icon, "CooldownTimeline3"), (wc_icon, '<span class="pink">WhisperCast</span>: Second Wind')]
	h = "".join(f'<div class="ar{" me" if i == 0 else ""}"><i class="cb"></i><img src="{a}" alt="" width="18" height="18"><span>{n}</span></div>' for i, (a, n) in enumerate(rows))
	return f'<div class="mock"><div class="addons">{h}</div><div class="zoom"><img src="{icon}" alt="" width="64" height="64"><span>64 px, as in the file</span></div></div>'

def mini_mock(icon):
	return (f'<div class="mock"><div class="map"><div class="ground"></div>'
		f'<img class="mb b1" src="{wc_mini}" alt="" width="32" height="32">'
		f'<img class="mb b2" src="{cdtl_mini}" alt="" width="32" height="32">'
		f'<img class="mb b3" src="{icon}" alt="" width="32" height="32"></div>'
		f'<div class="zoom"><img src="{icon}" alt="" width="64" height="64"><span>Yours is the bottom one</span></div></div>')

def fig(key, name, line, mock):
	return f'<figure class="choice" data-choice="{key}">{mock}<figcaption><b>{name}</b>{line}</figcaption></figure>'

KEEP = ("keep", "Keep the current icon", "The one CooldownCollaborator has now.")
addons = "".join(fig(k, n, l, addons_mock(sq[k])) for k, n, l in CROPS) + fig(*KEEP, addons_mock(cur_icon))
minis = "".join(fig(k, n, l, mini_mock(rd[k])) for k, n, l in CROPS) + fig(*KEEP, mini_mock(cur_mini))

page = f"""<title>CooldownCollaborator Icon Board</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600&family=Inter:wght@400;500;600&display=swap">
<style>
/* Layout: one column of three places the icon shows; each place lists its choices as cards drawn at game size. */
:root {{
	--bg: #f6f3f7; --panel: #ffffff; --ink: #221a26; --ink-2: #5d5263; --line: #ddd3e0; --accent: #a8329a;
	--game: #121019; --game-2: #1c1826; --game-ink: #e8e3ee; --gold: #ffc940; --pink: #ff80ff;
	--display: "Cinzel", Georgia, serif; --body: "Inter", system-ui, -apple-system, "Segoe UI", sans-serif;
}}
@media (prefers-color-scheme: dark) {{
	:root:not([data-theme="light"]) {{ --bg: #141117; --panel: #1d1922; --ink: #efe8f2; --ink-2: #ad9fb4; --line: #3a3140; --accent: #f29be6; color-scheme: dark; }}
}}
:root[data-theme="dark"] {{ --bg: #141117; --panel: #1d1922; --ink: #efe8f2; --ink-2: #ad9fb4; --line: #3a3140; --accent: #f29be6; color-scheme: dark; }}
body {{ background: var(--bg); color: var(--ink); font: 15px/1.5 var(--body); }}
.wrap {{ max-width: 1080px; margin: 0 auto; padding-block: 28px 64px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); display: flex; flex-direction: column; gap: 36px; }}
header {{ display: grid; grid-template-columns: minmax(0, 1fr) 220px; gap: 24px; align-items: center; }}
@media (max-width: 640px) {{ header {{ grid-template-columns: minmax(0, 1fr); }} }}
h1 {{ font: 600 30px/1.15 var(--display); margin: 0 0 8px; text-wrap: balance; }}
h2 {{ font: 600 20px/1.2 var(--display); margin: 0; text-wrap: balance; }}
header p, .look > p {{ margin: 0; color: var(--ink-2); max-width: 66ch; }}
.hero-art {{ width: 100%; height: auto; border-radius: 6px; display: block; }}
.look {{ display: flex; flex-direction: column; gap: 14px; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 320px), 1fr)); gap: 14px; }}
figure {{ margin: 0; background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 12px; display: flex; flex-direction: column; gap: 10px; min-width: 0; }}
figcaption {{ font-size: 14px; line-height: 1.45; color: var(--ink-2); }}
figcaption b {{ display: block; margin-bottom: 1px; color: var(--ink); font-weight: 600; font-size: 15px; }}
.mock {{ background: var(--game); color: var(--game-ink); border-radius: 6px; padding: 12px; display: flex; gap: 12px; align-items: center; justify-content: space-between; min-height: 116px; font: 12px/1.3 var(--body); }}
.mock img {{ display: block; max-width: none; }}
.zoom {{ flex: none; width: 76px; display: flex; flex-direction: column; align-items: center; gap: 4px; font-size: 10.5px; color: #9a90a6; text-align: center; }}
.zoom img {{ border-radius: 3px; }}
.addons {{ display: flex; flex-direction: column; gap: 3px; min-width: 0; flex: 1; }}
.ar span {{ overflow: hidden; text-overflow: ellipsis; }}
.ar {{ display: flex; align-items: center; gap: 6px; padding: 3px 6px 3px 3px; border-radius: 3px; white-space: nowrap; }}
.ar.me {{ background: rgba(255, 255, 255, 0.07); }}
.cb {{ width: 12px; height: 12px; border: 1px solid #8d8399; border-radius: 2px; background: #2a2433; position: relative; flex: none; }}
.cb::after {{ content: ""; position: absolute; left: 3px; top: 0; width: 3px; height: 7px; border: solid var(--gold); border-width: 0 2px 2px 0; transform: rotate(45deg); }}
.pink {{ color: var(--pink); }}
.map {{ position: relative; width: 132px; height: 112px; flex: none; }}
.ground {{ position: absolute; right: 0; top: 0; width: 112px; height: 112px; border-radius: 50%; background: radial-gradient(circle at 40% 45%, #6f7a4b, #46512f 55%, #2d3420); box-shadow: 0 0 0 3px #4b4036; }}
.mb {{ position: absolute; border-radius: 50%; }}
.b1 {{ left: 0; top: 6px; }} .b2 {{ left: 8px; top: 42px; }} .b3 {{ left: 26px; top: 78px; }}
.small {{ display: grid; grid-template-columns: auto 1fr; gap: 8px 12px; align-items: center; }}
.cap {{ color: #9a90a6; font-size: 11px; }}
.cast {{ position: relative; width: 40px; height: 40px; background: #000; box-shadow: inset 0 0 0 1px #5d5d5d; display: grid; place-items: center; }}
.cast img {{ opacity: 0.4; }}
.cast b {{ position: absolute; right: 3px; top: 1px; font-size: 11px; font-weight: 600; color: #fff; text-shadow: 0 1px 1px #000; }}
.fold {{ position: relative; width: 34px; height: 34px; border-radius: 50%; box-shadow: 0 0 10px 2px rgba(255, 128, 255, 0.55); }}
.fold img {{ border-radius: 50%; }}
.fold b {{ position: absolute; right: -6px; top: -5px; min-width: 16px; height: 16px; border-radius: 8px; background: var(--pink); color: #2a0a2a; font-size: 10.5px; display: grid; place-items: center; }}
.files {{ font-size: 13px; color: var(--ink-2); }}
code {{ font-size: 12.5px; }}
</style>
<div class="wrap">
<header>
	<div>
		<h1>CooldownCollaborator icon</h1>
		<p>Your new picture, cut five ways and drawn where the game shows it, next to your WhisperCast and CooldownTimeline3 icons. Pick one for each place; they don't have to match. The whole picture goes on the CurseForge and Wago pages as it is.</p>
	</div>
	<img class="hero-art" src="{hero}" alt="Your new CooldownCollaborator picture" width="440" height="440">
</header>

<section class="look" data-item="addons">
	<h2>The AddOns list</h2>
	<p>Game menu › AddOns, beside the name, about 18 px. The same file is the icon on CooldownTimeline3's bars when CooldownCollaborator feeds them.</p>
	<div class="grid">{addons}</div>
</section>

<section class="look" data-item="minimap">
	<h2>The minimap button</h2>
	<p>Round, with the same gold ring as now, at 32 px on the minimap's edge.</p>
	<div class="grid">{minis}</div>
</section>

<p class="files">Each choice becomes a 128 px PNG for the source art plus 64 px <code>icon.tga</code> and <code>minimap.tga</code>, in the same format as now.</p>
</div>
"""
with open(os.path.join(HERE, "picks.part.html")) as f:
	page += f.read()
sys.stdout.write(page)
