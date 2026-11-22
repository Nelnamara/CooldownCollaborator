"""Cuts the owner's new CooldownCollaborator picture (Downloads/CDCicon.png, 1920 px) into icon candidates and writes the icon board.
  python make.py <CDCicon.png> <out dir>   (needs Pillow)
Each candidate: <key>-icon-128.png, <key>-icon.tga (64, square), <key>-minimap-128.png and <key>-minimap.tga
(64, round, the same gold ring as before). TGAs match the current Media/*.tga: 32-bit BGRA, bottom-left origin, TGA 2.0 footer."""
import base64, io, struct, sys, os
from PIL import Image, ImageDraw

CROPS = {  # (left, top, right, bottom) in the 1920 x 1920 picture
	"face": (730, 190, 1120, 580),
	"head": (619, 75, 1331, 788),
	"pair": (112, 150, 1200, 1238),
	"crystal": (1425, 656, 1763, 994),
	"bubble": (94, 281, 638, 825),
}
GOLD = (255, 201, 64, 255)   # CooldownCollaborator's minimap ring

def tga(img, path):
	img = img.convert("RGBA")
	w, h = img.size
	head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
	rows = []
	px = img.tobytes()
	for y in range(h - 1, -1, -1):
		row = px[y * w * 4:(y + 1) * w * 4]
		out = bytearray(row)
		out[0::4], out[2::4] = row[2::4], row[0::4]   # RGBA -> BGRA
		rows.append(bytes(out))
	foot = b"\0" * 8 + b"TRUEVISION-XFILE.\0"
	with open(path, "wb") as f:
		f.write(head + b"".join(rows) + foot)

def round_icon(sq):
	S = 512   # drawn large, then scaled down: smooth edges
	big = sq.resize((S, S), Image.LANCZOS).convert("RGBA")
	mask = Image.new("L", (S, S), 0)
	ImageDraw.Draw(mask).ellipse((0, 0, S - 1, S - 1), fill=255)
	out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
	out.paste(big, (0, 0), mask)
	ring = S * 8 // 128
	ImageDraw.Draw(out).ellipse((0, 0, S - 1, S - 1), outline=GOLD, width=ring)   # out to the edge, as CDC's
	return out.resize((128, 128), Image.LANCZOS)

def main(src, outdir):
	os.makedirs(outdir, exist_ok=True)
	im = Image.open(src).convert("RGB")
	made = {}
	for key, box in CROPS.items():
		sq = im.crop(box).resize((128, 128), Image.LANCZOS)
		rd = round_icon(im.crop(box))
		sq.save(f"{outdir}/{key}-icon-128.png")
		rd.save(f"{outdir}/{key}-minimap-128.png")
		tga(sq.resize((64, 64), Image.LANCZOS), f"{outdir}/{key}-icon.tga")
		tga(rd.resize((64, 64), Image.LANCZOS), f"{outdir}/{key}-minimap.tga")
		made[key] = (sq, rd)
	return made

if __name__ == "__main__":
	main(sys.argv[1], sys.argv[2])
