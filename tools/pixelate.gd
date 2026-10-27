extends SceneTree

## Turns the vector portraits in art/units/*.svg into 8-bit style sprites in art/pixel/*.png:
## snap to a small retro palette, shrink to a tiny grid by majority vote (ink lines get a bonus so
## eyes and outlines survive), then add a 1-pixel outline.
##   godot --headless --path . --script res://tools/pixelate.gd

const SRC := "res://art/units/"
const DST := "res://art/pixel/"
const SIZE := 40
const INK_WEIGHT := 1.8
const OUTLINE := Color("181425")

## ENDESGA 32 by Endesga (free pixel-art palette): retro-limited but with usable greens and browns.
const PALETTE := [
	"be4a2f", "d77643", "ead4aa", "e4a672", "b86f50", "733e39", "3e2731", "a22633", "e43b44", "f77622",
	"feae34", "fee761", "63c74d", "3e8948", "265c42", "193c3e", "124e89", "0099db", "2ce8f5", "ffffff",
	"c0cbdc", "8b9bb4", "5a6988", "3a4466", "262b44", "181425", "ff0044", "68386c", "b55088", "f6757a",
	"e8b796", "c28569",
]

var _palette: Array[Color] = []
var _cache := {}


func _init() -> void:
	for h in PALETTE:
		_palette.append(Color(h))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	var n := 0
	for f in DirAccess.get_files_at(SRC):
		if not f.ends_with(".svg"):
			continue
		var img := Image.new()
		img.load_svg_from_string(FileAccess.get_file_as_string(SRC + f), 1.0)
		_pixelate(img).save_png(ProjectSettings.globalize_path(DST + f.get_basename() + ".png"))
		n += 1
	print("pixelated %d sprites -> %s" % [n, DST])
	quit()


func _pixelate(src: Image) -> Image:
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var block := float(w) / SIZE
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var solid := []
	solid.resize(SIZE * SIZE)
	for by in SIZE:
		for bx in SIZE:
			# Majority vote over the source block; transparent counts as a "color" too.
			var votes := {}
			var y0 := int(by * block)
			var x0 := int(bx * block)
			for y in range(y0, int((by + 1) * block)):
				for x in range(x0, int((bx + 1) * block)):
					var c := img.get_pixel(x, y)
					var key: Variant = null
					var weight := 1.0
					if c.a >= 0.5:
						var snapped := _nearest(c)
						key = snapped.to_rgba32()
						if snapped == OUTLINE:
							weight = INK_WEIGHT
					votes[key] = votes.get(key, 0.0) + weight
			var best: Variant = null
			var best_v := -1.0
			for k in votes:
				if votes[k] > best_v:
					best_v = votes[k]
					best = k
			solid[by * SIZE + bx] = best != null
			if best != null:
				out.set_pixel(bx, by, Color.hex(best))
	for y in SIZE:
		for x in SIZE:
			if solid[y * SIZE + x]:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and solid[ny * SIZE + nx]:
					out.set_pixel(x, y, OUTLINE)
					break
	return out


func _nearest(c: Color) -> Color:
	var key := Color8(c.r8 & 0xF8, c.g8 & 0xF8, c.b8 & 0xF8).to_rgba32()
	if _cache.has(key):
		return _cache[key]
	var best := _palette[0]
	var best_d := INF
	for p in _palette:
		# "Redmean" weighting: cheap and closer to how eyes judge color distance than plain RGB.
		var rm := (c.r + p.r) * 0.5
		var dr := c.r - p.r
		var dg := c.g - p.g
		var db := c.b - p.b
		var d := (2.0 + rm) * dr * dr + 4.0 * dg * dg + (3.0 - rm) * db * db
		if d < best_d:
			best_d = d
			best = p
	_cache[key] = best
	return best
