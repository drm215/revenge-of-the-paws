extends SceneTree

## Draws the loading-screen splash (art/splash.png): the title over a pack of animals facing the
## horde, in the game's own sprites, fonts and palette. Run from the project folder:
##   godot --path . --rendering-driver opengl3 --script tools/make_splash.gd

const SIZE := Vector2i(720, 1280)
const OUT := "res://art/splash.png"
const PACK := ["dog", "black_bear", "horned_owl", "cat"]
const HORDE := ["runner", "shambler", "brute", "bloater"]

var _viewport := SubViewport.new()
var _frames := 0


func _init() -> void:
	_viewport.size = SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var page := Control.new()
	page.size = Vector2(SIZE)
	_viewport.add_child(page)

	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.size = Vector2(SIZE)
	page.add_child(bg)
	# A dim ground strip where the two sides meet.
	var ground := ColorRect.new()
	ground.color = Retro.NIGHT
	ground.position = Vector2(0, 700)
	ground.size = Vector2(SIZE.x, 250)
	page.add_child(ground)

	var lines := [["REVENGE", Retro.GOLD], ["OF THE", Retro.MIST], ["PAWS", Retro.GOLD]]
	for k in lines.size():
		var title := Label.new()
		title.text = lines[k][0]
		title.add_theme_font_override("font", Retro.title_font())
		title.add_theme_font_size_override("font_size", 40 if k == 1 else 76)
		title.add_theme_color_override("font_color", lines[k][1])
		title.add_theme_color_override("font_outline_color", Color.BLACK)
		title.add_theme_constant_override("outline_size", 12)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.size = Vector2(SIZE.x, 100)
		title.position = Vector2(0, [250, 360, 430][k])
		page.add_child(title)

	var tagline := Label.new()
	tagline.text = "Animals vs. zombies, in your own neighborhood."
	tagline.add_theme_font_override("font", Retro.body_font())
	tagline.add_theme_font_size_override("font_size", 26)
	tagline.add_theme_color_override("font_color", Retro.FOG)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.size = Vector2(SIZE.x, 40)
	tagline.position = Vector2(0, 580)
	page.add_child(tagline)

	_side(page, PACK, 6, false)
	_side(page, HORDE, SIZE.x - 6 - 4 * 86, true)
	_viewport.get_texture()  # render target ready
	process_frame.connect(_tick)


## Four sprites stepping toward the middle; the horde is mirrored to face the pack.
func _side(page: Control, ids: Array, x: float, mirror: bool) -> void:
	for k in ids.size():
		var sprite := TextureRect.new()
		sprite.texture = load("res://art/pixel/%s.png" % ids[k])
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.flip_h = mirror
		var big := 210.0 if ids[k] in ["black_bear", "brute"] else 160.0
		sprite.size = Vector2(big, big)
		var slot := k if not mirror else ids.size() - 1 - k
		sprite.position = Vector2(x + slot * 86 - (big - 160) / 2, 905 - big + (k % 2) * 30)
		page.add_child(sprite)


func _tick() -> void:
	_frames += 1
	if _frames == 6:
		_viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
		print("saved ", OUT)
		quit()
