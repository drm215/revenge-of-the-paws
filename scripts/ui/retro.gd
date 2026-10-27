class_name Retro
extends RefCounted

## The shared 8-bit look: ENDESGA 32 colors, crisp pixel fonts, square boxes with chunky borders.
## Fonts (SIL Open Font License, see fonts/): Press Start 2P for titles/buttons, Pixelify Sans for text.

const INK := Color("181425")
const NIGHT := Color("262b44")
const SLATE := Color("3a4466")
const STEEL := Color("5a6988")
const FOG := Color("8b9bb4")
const MIST := Color("c0cbdc")
const WHITE := Color("ffffff")
const GOLD := Color("feae34")
const YELLOW := Color("fee761")
const ORANGE := Color("f77622")
const RED := Color("e43b44")
const DARK_RED := Color("a22633")
const GREEN := Color("63c74d")
const FOREST := Color("3e8948")
const PINE := Color("265c42")
const SWAMP := Color("193c3e")
const CYAN := Color("2ce8f5")
const SKY := Color("0099db")
const PURPLE := Color("b55088")
const PLUM := Color("68386c")
const DIRT := Color("3e2731")
const SAND := Color("ead4aa")
const PINK := Color("f6757a")

const TITLE_FONT := "res://fonts/PressStart2P-Regular.ttf"
const BODY_FONT := "res://fonts/PixelifySans.ttf"
const BORDER := 4
## One knob for every text size in the game (sizes in code are written at 1.0).
const TEXT_SCALE := 1.35
## Pixelify Sans is a variable font; a heavier weight keeps thin pixel strokes readable.
const BODY_WEIGHT := 600

static var _title_font: FontFile
static var _body_font: FontVariation


static func title_font() -> FontFile:
	if _title_font == null:
		_title_font = _crisp(TITLE_FONT)
	return _title_font


static func body_font() -> Font:
	if _body_font == null:
		_body_font = FontVariation.new()
		_body_font.base_font = _crisp(BODY_FONT)
		_body_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): BODY_WEIGHT}
	return _body_font


## A font size scaled by TEXT_SCALE.
static func px(font_size: float) -> int:
	return roundi(font_size * TEXT_SCALE)


## Pixel fonts must not be smoothed, or the blocky edges turn to mush.
static func _crisp(path: String) -> FontFile:
	var f: FontFile = load(path)
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	return f


## A square box with a chunky border; `lip` thickens the bottom edge like an old console button.
static func box(bg: Color, border := SLATE, width := BORDER, lip := 0, margin := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.border_width_bottom = width + lip
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	return s


const TAP_SLOP := 16.0


## Makes a ScrollContainer drag-scrollable on touch screens: every tappable thing added inside it
## passes input up (MOUSE_FILTER_PASS) instead of swallowing the drag. Call before adding it to
## the tree. Text fields keep their own input.
static func touch_scroll(scroll: ScrollContainer) -> void:
	var fix := func(n: Node) -> void:
		if n is Control and not n is LineEdit and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP 				and scroll.is_ancestor_of(n):
			(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.tree_entered.connect(func() -> void: scroll.get_tree().node_added.connect(fix))
	scroll.tree_exiting.connect(func() -> void: scroll.get_tree().node_added.disconnect(fix))


## Calls `action` when `control` is tapped: pressed and released without dragging, so a swipe to
## scroll a list never selects whatever it started on.
static func on_tap(control: Control, action: Callable) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			return
		# A tap on a button inside the card (Duty, Trinket, ...) belongs to that button only.
		var under := control.get_viewport().gui_get_hovered_control()
		if under != control and under is BaseButton and control.is_ancestor_of(under):
			control.remove_meta("tap_from")
			return
		if event.pressed:
			control.set_meta("tap_from", event.global_position)
		elif control.has_meta("tap_from"):
			var start: Vector2 = control.get_meta("tap_from")
			control.remove_meta("tap_from")
			if event.global_position.distance_to(start) < TAP_SLOP:
				action.call())


## Styles a label as an arcade title (Press Start 2P).
static func title(label: Label, font_size := 16, color := GOLD) -> Label:
	label.add_theme_font_override("font", title_font())
	label.add_theme_font_size_override("font_size", px(font_size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", INK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


## A plain pixel-text label (Pixelify Sans).
static func text(label: Label, font_size := 22, color := MIST) -> Label:
	label.add_theme_font_size_override("font_size", px(font_size))
	label.add_theme_color_override("font_color", color)
	return label


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = px(24)

	t.set_color("font_color", "Label", MIST)

	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", px(16))
	t.set_stylebox("normal", "Button", box(SLATE, STEEL, BORDER, 4))
	t.set_stylebox("hover", "Button", box(STEEL, FOG, BORDER, 4))
	t.set_stylebox("pressed", "Button", box(GOLD, YELLOW, BORDER, 1))
	t.set_stylebox("hover_pressed", "Button", box(GOLD, YELLOW, BORDER, 1))
	t.set_stylebox("disabled", "Button", box(NIGHT, SLATE, BORDER, 4))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", STEEL)

	t.set_stylebox("normal", "LineEdit", box(INK, STEEL))
	t.set_stylebox("focus", "LineEdit", box(INK, GOLD))
	t.set_font("font", "LineEdit", title_font())
	t.set_font_size("font_size", "LineEdit", px(22))
	t.set_color("font_color", "LineEdit", WHITE)
	t.set_color("font_placeholder_color", "LineEdit", STEEL)
	t.set_color("caret_color", "LineEdit", GOLD)

	t.set_stylebox("panel", "PanelContainer", box(NIGHT, SLATE))
	t.set_stylebox("background", "ProgressBar", box(INK, INK, 2, 0, 0))
	t.set_color("default_color", "RichTextLabel", MIST)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", title_font())

	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(INK, INK, 0, 0, 2))
		t.set_stylebox("grabber", bar, box(STEEL, STEEL, 0, 0, 4))
		t.set_stylebox("grabber_highlight", bar, box(FOG, FOG, 0, 0, 4))
		t.set_stylebox("grabber_pressed", bar, box(GOLD, GOLD, 0, 0, 4))
	return t
