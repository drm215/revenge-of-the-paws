class_name MapView
extends Control

## Draws the campaign map (territory cells, ownership, threat, lairs) and reports taps on territories.
## Drag to pan; pinch or mouse wheel to zoom. Three layers, so an idle map costs next to nothing:
## _shapes keeps its drawing and just moves when panned, _pulse redraws at PULSE_INTERVAL while
## anything glows, and _labels redraws when the view changes. Call refresh() after the game changes.

signal territory_selected(index: int)

const OWNED := Retro.FOREST
const HOME := Retro.GREEN
const ATTACKABLE := Color("9a4a2a")
const ATTACKABLE_EASY := Color("eeaa44")  # the lowest level you can attack right now
const ATTACKABLE_HARD := Color("6e2412")  # the highest
const INFESTED := Color("4f3446")
const INFESTED_DEEP := Color("2c1f2e")
const UNDER_ATTACK := Retro.RED
const BORDER := Retro.INK
const SELECTED := Retro.YELLOW
const LAIR := Color("f6a0e0")
const BEATEN_LAIR := Color("a08aa0")  # a beaten legend's lair: its name, greyed
const CUT_OFF := Color("2a4a33")  # held but cut off from home
const NEST := Color("b8203a")
const MIN_ZOOM := 0.3
const MAX_ZOOM := 16.0  # relative to the framed front line, which shrinks as the map grows
const TAP_SLOP := 12.0
const MIN_LABEL_PX := 64.0  # smaller areas only get a label once zoomed in
const LABEL_GAP := 3.0  # px kept clear around each label; crowded labels wait for a closer zoom
const LABEL_MARGIN := 120.0  # labels this far off screen can still reach into view; beyond it they're skipped
const PULSE_INTERVAL := 0.05  # seconds between redraws of what glows
const OUTLINE_RETRY := 5.0  # seconds before asking again for outlines that didn't arrive
const LIBERATION_SEC := 3.2  # how long a liberation plays
const WAVE_SEC := 1.1  # of that, how long the green takes to cross the territory
const WAVE_POINTS := 36
const HORDE_FRONT := Color("e8324a")  # the horde's tide: a bright edge, dark behind it
const HORDE_BODY := Color("5a1626")
const MARCHERS := ["shambler", "runner", "shambler", "brute"]
const FIREWORK_COLORS: Array[Color] = [Retro.GOLD, Retro.GREEN, Retro.CYAN, Retro.PINK, Retro.YELLOW]

var campaign: Campaign
var selected := -1
var pings := {}  # territory ids teammates pinged recently -> who (Chat.recent_pings)

var _fit_scale := 1.0
var _fit_offset := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO  # screen-space shift on top of the fitted view
var _time := 0.0
var _press_pos := Vector2.ZERO
var _dragging := false
var _touches := {}  # finger index -> position, for pinch
var _draw_order: Array[int] = []  # biggest areas first, so enclaves inside them stay visible
var _bboxes: Array[Rect2] = []  # per territory, map space
var _label_hits: Array = []  # [screen Rect2, territory index] for each name drawn, for taps
var _full_bounds := Rect2()  # whole map, map space
var _icons := {}  # animal id -> texture, for survivors waiting to be rescued
var _parts: Array = []  # per territory: its rings as {closed (outline), points and tris (fill; no tris if it won't triangulate)}
var _shapes := Node2D.new()  # fills and borders, in map space
var _pulse := Node2D.new()  # glowing outlines and nest marks
var _labels := Node2D.new()  # names, threat, markers, in screen space
var _shapes_scale := 0.0  # the scale _shapes was drawn at; its borders are redrawn to keep their width
var _pulse_wait := 0.0
var _fills_pulse := false  # a counterattack or cut-off land glows
var _outlines_pulse := false  # lairs, pings or nests glow
# What glows, worked out once per refresh() so the pulse (20 times a second) never scans the map.
var _glowing_fills: Array[int] = []  # under attack or cut off: their fill pulses, on the _pulse layer
var _lairs: Array[int] = []
var _warlord_lands: Array[int] = []
var _pinged: Array[int] = []
var _nests: Array[int] = []
var _label_rank := {}  # territory -> 0 home/selected, 1 lair/warlord/dungeon, 2 actionable, 3 unheld, 4 held
const REBORDER_DELAY := 0.15  # seconds after a zoom stops before borders are redrawn at their width
var _reborder_wait := -1.0
var _loading := Label.new()  # shown while this map's outlines are being fetched
var _shades := {}  # territory index -> its fill, for those that can be attacked
var _wave_at := -1  # the territory being liberated on screen right now
var _wave_time := 0.0
var _wave_from := Vector2.ZERO
var _wave_near := 0.0  # distance from the wave's start to the territory's nearest and farthest points
var _wave_far := 0.0
var _wave_front := HOME
var _wave_body := OWNED
var _wave_was := ATTACKABLE  # how the territory looks until the tide reaches it
var _pan_tween: Tween


func _init() -> void:
	for layer: Node2D in [_shapes, _pulse, _labels]:
		add_child(layer)
	_shapes.draw.connect(_draw_shapes)
	_pulse.draw.connect(_draw_pulse)
	_labels.draw.connect(_draw_labels)
	Retro.text(_loading, 19, Retro.MIST)
	_loading.position = Vector2(12, 6)
	_loading.visible = false
	add_child(_loading)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel survivor icons
	resized.connect(_fit)
	if campaign:
		campaign.fill_outlines()  # files that arrived since this map was last on screen
	_fit()
	refresh()
	_load_outlines()


## Plays a territory being freed: green rolls over it from `from` (a map point), fireworks go off
## over it, and the pet (with anyone just rescued) runs across.
func play_liberation(i: int, from: Vector2, rescued: String) -> void:
	_start_wave(i, from, HOME, OWNED, ATTACKABLE)
	var runners: Array[String] = []
	if campaign.profile and campaign.profile.has_pet():
		runners.append(campaign.profile.pet_species)
	if rescued != "":
		runners.append(rescued)
	var site := _to_screen(campaign.territories[i].site)
	for k in runners.size():
		_run_across(runners[k], site + Vector2(0, 14), k)
	for k in 4:
		_firework(site, 0.5 + k * 0.5, k)


## A colored tide rolling over territory `i` from `from` (a map point), over how it looked before.
func _start_wave(i: int, from: Vector2, front: Color, body: Color, was: Color) -> void:
	_wave_at = i
	_wave_time = 0.0
	_wave_from = from
	_wave_front = front
	_wave_body = body
	_wave_was = was
	_wave_near = INF
	_wave_far = 0.0
	for ring in campaign.territories[i].parts:
		for p in ring:
			var d := p.distance_to(from)
			_wave_near = minf(_wave_near, d)
			_wave_far = maxf(_wave_far, d)
	if _wave_far <= 0.0:
		_wave_at = -1  # no outline here yet: the rest of the moment still plays
	_shapes.queue_redraw()


## The horde's move on territory `i`: zombies march in from `from`. Land it spreads into or takes
## is washed over in red; land it attacks flashes, and goes on pulsing as usual.
func play_horde(i: int, from: Vector2, kind: String) -> void:
	if kind == "fell":
		_start_wave(i, from, HORDE_FRONT, HORDE_BODY, OWNED)
	elif kind == "spread":
		_start_wave(i, from, HORDE_FRONT, HORDE_BODY, _fill(i))
	else:
		_edge_flash()
	var start := _to_screen(from)
	var end := _to_screen(campaign.territories[i].site)
	for k in MARCHERS.size():
		_march(MARCHERS[k], start, end, k)


## An alarm's red flash over the map.
func _edge_flash() -> void:
	var flash := ColorRect.new()
	flash.color = Color(HORDE_FRONT, 0.5)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 2
	add_child(flash)
	var fade := flash.create_tween().set_loops(2)
	fade.tween_property(flash, "color:a", 0.05, 0.3)
	fade.tween_property(flash, "color:a", 0.5, 0.2)
	flash.create_tween().tween_interval(1.0)
	var end := flash.create_tween()
	end.tween_interval(1.0)
	end.tween_callback(flash.queue_free)


## One zombie staggering from `start` to `end`, a little behind the one before it.
func _march(id: String, start: Vector2, end: Vector2, order: int) -> void:
	var path := "res://art/pixel/%s.png" % id
	if not ResourceLoader.exists(path):
		return
	var sprite := TextureRect.new()
	sprite.texture = load(path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.size = Vector2(44, 44)
	sprite.flip_h = end.x < start.x
	sprite.z_index = 3
	sprite.modulate.a = 0.0
	add_child(sprite)
	var spot := Vector2([-16, 18, 2, -24][order % 4], [10, -12, 20, -18][order % 4]) - sprite.size / 2.0
	sprite.position = start + spot
	var walk := sprite.create_tween()
	walk.tween_interval(order * 0.13)
	walk.tween_property(sprite, "modulate:a", 1.0, 0.1)
	walk.tween_method(func(t: float) -> void:
		sprite.position = start.lerp(end, t) + spot + Vector2(0, -absf(sin(t * TAU * 2.5)) * 8.0), 0.0, 1.0, 1.15)
	walk.tween_property(sprite, "modulate:a", 0.0, 0.2)
	walk.tween_callback(sprite.queue_free)


## The view glides over until territory `i` is in the middle.
func pan_to(i: int, seconds: float) -> void:
	if _pan_tween:
		_pan_tween.kill()
	var held := _pan
	_pan = Vector2.ZERO
	var target := size / 2.0 - _to_screen(campaign.territories[i].site)
	_pan = held
	_pan_tween = create_tween()
	_pan_tween.tween_method(func(p: Vector2) -> void:
		_pan = p
		_clamp_pan(), held, target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## The tide so far: everything of the territory within its reach, with a bright front.
func _draw_wave() -> void:
	var reach: float = lerpf(_wave_near, _wave_far, clampf(_wave_time / WAVE_SEC, 0.0, 1.0))
	var band := (_wave_far - _wave_near) * 0.12
	for part: Dictionary in _parts[_wave_at]:
		_draw_within(part.points, reach, _wave_front)
		_draw_within(part.points, maxf(0.001, reach - band), _wave_body)


## The part of a ring within `radius` of the wave's start. A sliver that can't be drawn is left out.
func _draw_within(points: PackedVector2Array, radius: float, color: Color) -> void:
	var colors := PackedColorArray([color])
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(points, _circle(_wave_from, radius)):
		var tris := Geometry2D.triangulate_polygon(piece)
		if not tris.is_empty():
			RenderingServer.canvas_item_add_triangle_array(_pulse.get_canvas_item(), tris, piece, colors)


func _circle(center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in WAVE_POINTS:
		out.append(center + Vector2.from_angle(TAU * k / WAVE_POINTS) * radius)
	return out


## An animal bounding across the freed land.
func _run_across(id: String, at: Vector2, order: int) -> void:
	var path := "res://art/pixel/%s.png" % id
	if not ResourceLoader.exists(path):
		return
	var sprite := TextureRect.new()
	sprite.texture = load(path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.size = Vector2(56, 56)
	sprite.z_index = 3
	sprite.modulate.a = 0.0
	add_child(sprite)
	var start := at + Vector2(-130 - order * 54, -44)
	sprite.position = start
	var run := sprite.create_tween()
	run.tween_interval(0.25 + order * 0.15)
	run.tween_property(sprite, "modulate:a", 1.0, 0.1)
	run.tween_method(func(t: float) -> void:
		sprite.position = start + Vector2(260.0 * t, -absf(sin(t * TAU * 3.0)) * 22.0), 0.0, 1.0, 1.5)
	run.tween_property(sprite, "modulate:a", 0.0, 0.15)
	run.tween_callback(sprite.queue_free)


## A burst of pixels over the freed land, `delay` seconds from now.
func _firework(site: Vector2, delay: float, order: int) -> void:
	await get_tree().create_timer(delay).timeout
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play("firework", 0.12, -4.0)
	var bits := CPUParticles2D.new()
	bits.one_shot = true
	bits.explosiveness = 1.0
	bits.amount = 34
	bits.lifetime = 0.9
	bits.direction = Vector2.UP
	bits.spread = 180.0
	bits.gravity = Vector2(0, 170)
	bits.initial_velocity_min = 70.0
	bits.initial_velocity_max = 190.0
	bits.scale_amount_min = 3.0
	bits.scale_amount_max = 7.0
	bits.color = FIREWORK_COLORS[order % FIREWORK_COLORS.size()]
	bits.z_index = 4
	bits.position = site + Vector2([-90, 80, -30, 40][order % 4], [-70, -110, -140, -60][order % 4])
	bits.finished.connect(bits.queue_free)
	add_child(bits)
	bits.emitting = true


## First time on this ground: fetch the outlines. Names and markers show until they arrive.
func _load_outlines() -> void:
	if campaign == null:
		return
	var missing := campaign.missing_outlines()
	while not missing.is_empty():
		_loading.text = "Loading the map..."
		_loading.visible = true
		var waiting := [missing.size()]
		for shard in missing:
			var fetch := func() -> void:
				await ZctaDB.download(shard, self)
				waiting[0] -= 1
			fetch.call()
		while waiting[0] > 0:
			await get_tree().process_frame
		campaign.fill_outlines()
		_parts.clear()
		_fit()
		refresh()
		missing = campaign.missing_outlines()
		if not missing.is_empty():
			_loading.text = "Can't load the map right now. Trying again..."
			await get_tree().create_timer(OUTLINE_RETRY).timeout
	_loading.visible = false


func _process(delta: float) -> void:
	_time += delta
	if _wave_at >= 0:
		_wave_time += delta
		_pulse.queue_redraw()
		if _wave_time >= WAVE_SEC:
			_wave_at = -1
			_shapes.queue_redraw()
	if _reborder_wait >= 0.0:
		_reborder_wait -= delta
		if _reborder_wait < 0.0:
			_shapes_scale = _view_scale()
			_shapes.queue_redraw()
	_pulse_wait -= delta
	if _pulse_wait > 0.0:
		return
	_pulse_wait = PULSE_INTERVAL
	if _outlines_pulse or _fills_pulse:
		_pulse.queue_redraw()  # only what glows: the map under it stays drawn


## The game changed (ownership, selection, pings): draw it all again.
func refresh() -> void:
	for list: Array[int] in [_glowing_fills, _lairs, _warlord_lands, _pinged, _nests]:
		list.clear()
	_label_rank.clear()
	if campaign:
		_update_shades()
		for i in campaign.territories.size():
			var t := campaign.territories[i]
			if i == campaign.under_attack or campaign.is_cut_off(i):
				_glowing_fills.append(i)
			if _is_lair(i):
				_lairs.append(i)
			if _has_warlord(i):
				_warlord_lands.append(i)
			if pings.has(t.id):
				_pinged.append(i)
			if campaign.is_nest(i):
				_nests.append(i)
			if i in campaign.homes:
				_label_rank[i] = 0
			elif _is_lair(i) or i in _warlord_lands or t.dungeon != "":
				_label_rank[i] = 1
			elif campaign.is_actionable(i):
				_label_rank[i] = 2
			else:
				_label_rank[i] = 4 if t.owned else 3
	_fills_pulse = not _glowing_fills.is_empty()
	_outlines_pulse = not (_lairs.is_empty() and _warlord_lands.is_empty() and _pinged.is_empty() and _nests.is_empty())
	for layer: Node2D in [_shapes, _pulse, _labels]:
		layer.queue_redraw()


## Land you can attack shades from pale (the lowest level in reach) to dark (the highest).
func _update_shades() -> void:
	_shades.clear()
	var levels := {}
	var low := 1 << 30
	var high := 0
	for i in campaign.territories.size():
		if campaign.can_attack(i):
			levels[i] = campaign.territory_level(i)
			low = mini(low, levels[i])
			high = maxi(high, levels[i])
	for i: int in levels:
		_shades[i] = ATTACKABLE_EASY.lerp(ATTACKABLE_HARD, float(levels[i] - low) / (high - low)) if high > low else ATTACKABLE


func _has_warlord(i: int) -> bool:
	return campaign._is_occupied(i)


func _is_lair(i: int) -> bool:
	return campaign.territories[i].boss != "" and not campaign.territories[i].owned


## Centers the view on a territory (used when something needs the player's attention).
func focus(i: int) -> void:
	_pan = Vector2.ZERO
	_pan = size / 2.0 - _to_screen(campaign.territories[i].site)
	_clamp_pan()


func _fit() -> void:
	if campaign == null or size.x <= 0:
		return
	_build_geometry()
	# Frame the front line (what you hold and can attack); zoom out to see the whole map.
	var bounds := Rect2(campaign.territories[0].site, Vector2.ZERO)
	for i in campaign.territories.size():
		if campaign.territories[i].owned or campaign.can_attack(i):
			bounds = bounds.merge(_bboxes[i])
	_fit_scale = minf(size.x / bounds.size.x, size.y / bounds.size.y) * 0.96
	_fit_offset = size / 2.0 - bounds.get_center() * _fit_scale
	_clamp_pan()


## What never changes during a game's map screen: bounds, draw order, and every ring ready to draw.
func _build_geometry() -> void:
	if _parts.size() == campaign.territories.size():
		return
	_parts.clear()
	_bboxes.clear()
	_full_bounds = Rect2(campaign.territories[0].site, Vector2.ZERO)
	for t in campaign.territories:
		var box := Rect2(t.site, Vector2.ZERO)
		var rings: Array = []
		for ring in t.parts:
			for p in ring:
				box = box.expand(p)
			var closed := ring.duplicate()
			closed.append(ring[0])
			rings.append({"closed": closed, "points": ring, "tris": Geometry2D.triangulate_polygon(ring)})
		_parts.append(rings)
		_bboxes.append(box)
		_full_bounds = _full_bounds.merge(box)
	_draw_order.assign(range(campaign.territories.size()))
	_draw_order.sort_custom(func(a: int, b: int) -> bool:
		return campaign.territories[a].area > campaign.territories[b].area)


func _view_scale() -> float:
	return _fit_scale * _zoom


func _to_screen(p: Vector2) -> Vector2:
	return ((p * _fit_scale + _fit_offset) - size / 2.0) * _zoom + size / 2.0 + _pan


func _to_map(screen: Vector2) -> Vector2:
	return (((screen - _pan - size / 2.0) / _zoom) + size / 2.0 - _fit_offset) / _fit_scale


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _to_map(screen_pos)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_pan += screen_pos - _to_screen(before)
	_clamp_pan()


## Keep the middle of the view somewhere over the map, wherever it has grown to.
func _clamp_pan() -> void:
	var saved := _pan
	_pan = Vector2.ZERO
	var r := Rect2(_to_screen(_full_bounds.position), Vector2.ZERO).expand(_to_screen(_full_bounds.end))
	_pan = saved
	var mid := size / 2.0
	_pan = _pan.clamp(mid - r.end, mid - r.position)
	_view_changed()


## Panning only moves the shapes; zooming redraws them too, so their borders keep their width.
func _view_changed() -> void:
	_shapes.position = _to_screen(Vector2.ZERO)
	_shapes.scale = Vector2.ONE * _view_scale()
	if _shapes_scale == 0.0:
		_shapes_scale = _view_scale()
		_shapes.queue_redraw()
	elif not is_equal_approx(_shapes_scale, _view_scale()):
		_reborder_wait = REBORDER_DELAY  # mid-pinch the drawing just scales; borders catch up after
	_pulse.queue_redraw()
	_labels.queue_redraw()


func _draw_shapes() -> void:
	if campaign == null or _parts.is_empty():
		return
	var item := _shapes.get_canvas_item()
	var width := 2.0 / _shapes_scale
	for i in _draw_order:
		var color := PackedColorArray([_fill(i)])
		for part: Dictionary in _parts[i]:
			if not part.tris.is_empty():
				RenderingServer.canvas_item_add_triangle_array(item, part.tris, part.points, color)
			_shapes.draw_polyline(part.closed, BORDER, width, false)


func _draw_pulse() -> void:
	if campaign == null or _parts.is_empty():
		return
	_pulse.draw_set_transform(_shapes.position, 0.0, _shapes.scale)
	for i in _glowing_fills:
		if i == _wave_at:
			continue
		var color := PackedColorArray([_glow_fill(i)])
		for part: Dictionary in _parts[i]:
			if not part.tris.is_empty():
				RenderingServer.canvas_item_add_triangle_array(_pulse.get_canvas_item(), part.tris, part.points, color)
		_outline(i, BORDER, 2.0)
	if _wave_at >= 0:
		_draw_wave()
	for i in _lairs:
		_outline(i, LAIR.lerp(Color.BLACK, 0.4 + 0.3 * sin(_time * 3.0)), 3.0)
	for i in _warlord_lands:
		_outline(i, HORDE_FRONT.lerp(Color.BLACK, 0.3 + 0.3 * sin(_time * 5.0)), 4.0)
	for i in _pinged:
		_outline(i, Retro.CYAN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 6.0)), 5.0)
	if selected >= 0:
		_outline(selected, SELECTED, 4.0)
	_pulse.draw_set_transform(Vector2.ZERO)
	for i in _nests:
		# A pulsing red blot marks a nest the horde spreads from.
		var at := _to_screen(campaign.territories[i].site) + Vector2(-34, -22)
		_pulse.draw_circle(at, 11, BORDER)
		_pulse.draw_circle(at, 8, NEST.lerp(Color.BLACK, 0.3 + 0.3 * sin(_time * 4.0)))
		_pulse.draw_circle(at, 3, BORDER)


func _draw_labels() -> void:
	if campaign == null or _parts.is_empty():
		return
	var font := Retro.pixel_font()
	var view := Rect2(Vector2.ZERO, size).grow(LABEL_MARGIN)
	var font_size := _label_size()
	var placed: Array[Rect2] = []  # labels already drawn; one that would overlap them is skipped
	_label_hits.clear()
	for i in _label_order():
		var t := campaign.territories[i]
		var c := _to_screen(t.site)
		if not view.has_point(c):
			continue
		var is_lair := _is_lair(i)
		var label := t.label if t.label.length() <= 13 else t.label.left(12) + "…"
		var color := Color.WHITE
		if i == campaign.home:
			_labels.draw_rect(Rect2(c + Vector2(-8, -26), Vector2(16, 16)), SELECTED)
			_labels.draw_rect(Rect2(c + Vector2(-8, -26), Vector2(16, 16)), BORDER, false, 3.0)
			label = "HOME"
		elif campaign.home_owner(i) != "":
			_labels.draw_rect(Rect2(c + Vector2(-8, -26), Vector2(16, 16)), Retro.CYAN)
			_labels.draw_rect(Rect2(c + Vector2(-8, -26), Vector2(16, 16)), BORDER, false, 3.0)
			label = campaign.home_owner(i).to_upper()
			color = Retro.CYAN
		elif is_lair:
			label = GameData.LEGENDS[t.boss].name
			color = LAIR
		if t.dungeon != "" and not is_lair:
			# A dark doorway in the ground (beside a home's marker, which keeps its name).
			var is_home := i in campaign.homes
			if not is_home:
				label = GameData.dungeon(t.dungeon).name
				color = Retro.CYAN
			var door := _door(c, is_home)
			_labels.draw_rect(door.grow(3), Retro.CYAN)
			_labels.draw_rect(door, Color.BLACK)
		if t.boss != "" and GameData.LEGENDS.has(t.boss):
			# Every lair found shows its legend: bold while it lives, greyed once it's beaten.
			if not is_lair:
				label = GameData.LEGENDS[t.boss].name
				color = BEATEN_LAIR
			_lair_badge(c, t.boss, is_lair)
		var warlord := i in _warlord_lands
		if warlord:
			label = String(campaign.warlord_at(i).name)
			color = Color("ff5a6e")
			_labels.draw_texture_rect(_icon("warlord"), Rect2(c + Vector2(-24, -56), Vector2(48, 48)), false)
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_box := Rect2(c.x - text_w / 2.0, c.y + 4 - font_size, text_w, font_size * 1.3).grow(LABEL_GAP)
		var must_show := i in campaign.homes or i == selected or t.boss != "" or warlord or t.dungeon != ""
		if must_show or not placed.any(func(r: Rect2) -> bool: return r.intersects(label_box)):
			placed.append(label_box)
			_label_hits.append([label_box, i])
			_text(font, c + Vector2(0, 4), label, font_size, color)
		if t.cache != "" and campaign.loot_at(i) != "":
			# A little treasure chest marks a trinket cache.
			var box := Rect2(c + Vector2(26, -30), Vector2(18, 14))
			_labels.draw_rect(box.grow(2), BORDER)
			_labels.draw_rect(box, Retro.GOLD)
			_labels.draw_rect(Rect2(box.position + Vector2(0, 5), Vector2(18, 3)), Color("b86f50"))
		var survivor := campaign.pending_recruit(i)
		if survivor != "":
			_labels.draw_texture_rect(_icon(survivor), Rect2(c + Vector2(-20, -48), Vector2(40, 40)), false)


## Territories big enough on screen to label, most important first: home and the selection, lairs,
## what you can attack, other unheld areas, then what you hold; bigger areas first within each.
func _label_order() -> Array[int]:
	var rank := {}
	var area := {}
	var order: Array[int] = []
	for i in campaign.territories.size():
		var on_screen := _bboxes[i].size * _fit_scale * _zoom
		var r: int = 0 if i == selected else _label_rank.get(i, 4)
		if r > 1 and maxf(on_screen.x, on_screen.y) < MIN_LABEL_PX:
			continue
		rank[i] = r
		area[i] = on_screen.x * on_screen.y
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return rank[a] < rank[b] if rank[a] != rank[b] else area[a] > area[b])
	return order


## A lair's mark above its name: the legend on a round badge, ringed in lair pink while it
## lives, small and grey once it's beaten.
func _lair_badge(c: Vector2, legend_id: String, alive: bool) -> void:
	var r := 30.0 if alive else 21.0
	var at := c + Vector2(0, -r - 14)
	var ring := LAIR if alive else BEATEN_LAIR  # (the lair's outline pulses; labels draw once)
	_labels.draw_circle(at, r + 3, BORDER)
	_labels.draw_circle(at, r, ring)
	_labels.draw_circle(at, r - 4, Color("2a1f33") if alive else Color("3a3440"))
	if ResourceLoader.exists("res://art/pixel/%s.png" % legend_id):
		var side := r * 2.3
		_labels.draw_texture_rect(_icon(legend_id), Rect2(at - Vector2(side, side) / 2.0, Vector2(side, side)), false,
			Color(1.35, 1.35, 1.35) if alive else Color(0.6, 0.6, 0.65, 0.9))


func _icon(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = load("res://art/pixel/%s.png" % id)
	return _icons[id]


func _text(font: Font, center: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := 220.0
	var pos := center + Vector2(-w / 2, 0)
	_labels.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, 6, Color.BLACK)
	_labels.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)


## A territory's outline, `width` px wide on screen. _draw_pulse has set the map-space transform.
func _outline(i: int, color: Color, width: float) -> void:
	for part: Dictionary in _parts[i]:
		_pulse.draw_polyline(part.closed, color, width / _view_scale(), false)


func _fill(i: int) -> Color:
	var t := campaign.territories[i]
	if i == _wave_at:
		return _wave_was  # as it was: the tide rolls over this
	if i == campaign.under_attack:
		return OWNED.lerp(UNDER_ATTACK, 0.5)  # (it pulses on the _pulse layer: _glow_fill)
	if t.owned:
		if campaign.is_cut_off(i):
			return CUT_OFF.lerp(INFESTED, 0.25)
		return HOME if i in campaign.homes else OWNED
	if campaign.can_attack(i):
		return _shades.get(i, ATTACKABLE)
	return INFESTED.lerp(INFESTED_DEEP, float(t.threat) / GameData.MAX_THREAT)


## The pulsing fill of land under attack or cut off, drawn over its steady one.
func _glow_fill(i: int) -> Color:
	if i == campaign.under_attack:
		return OWNED.lerp(UNDER_ATTACK, 0.5 + 0.5 * sin(_time * 5.0))
	return CUT_OFF.lerp(INFESTED, 0.25 + 0.25 * sin(_time * 2.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.size() == 2:
		# Pinch: zoom by the change in finger spread, around the midpoint.
		var other: Vector2 = _touches[_touches.keys().filter(func(k: int) -> bool: return k != event.index)[0]]
		var before: float = (_touches[event.index] as Vector2).distance_to(other)
		_touches[event.index] = event.position
		var after: float = event.position.distance_to(other)
		if before > 1.0:
			_zoom_at((event.position + other) / 2.0, after / before)
		_dragging = true
		accept_event()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_press_pos = event.position
			_dragging = false
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if not _dragging and _touches.size() <= 1:
				_select_at(event.position)
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _touches.size() >= 2:
			return
		if not _dragging and event.position.distance_to(_press_pos) > TAP_SLOP:
			_dragging = true
		if _dragging:
			_pan += event.relative
			_clamp_pan()
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		accept_event()


const DUNGEON_TAP_SLOP := 12.0
const SMALL_AREA := 30.0  # px across on screen: smaller areas are hard to hit, so...
const SMALL_TAP_SLOP := 22.0  # ...a tap this close to one picks it


## The doorway drawn for a dungeon whose territory's site is at screen point `c`.
func _door(c: Vector2, beside_home: bool) -> Rect2:
	return Rect2(c + (Vector2(14, -32) if beside_home else Vector2(-11, -34)), Vector2(22, 24))


## Where a dungeon shows on screen: its doorway, and its name under it (a home keeps its own).
func _dungeon_marker(i: int) -> Rect2:
	var c := _to_screen(campaign.territories[i].site)
	var is_home := i in campaign.homes
	var box := _door(c, is_home)
	if not is_home:
		var size := _label_size()
		var w := Retro.pixel_font().get_string_size(GameData.dungeon(campaign.territories[i].dungeon).name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		box = box.merge(Rect2(c.x - w / 2.0, c.y + 4 - size, w, size * 1.3))
	return box


func _label_size() -> int:
	return Retro.px(clampf(16 * sqrt(_zoom), 16, 26))


func _select_at(screen_pos: Vector2) -> void:
	var i := territory_at(screen_pos)
	if i >= 0:
		selected = i
		refresh()
		territory_selected.emit(i)


## What a tap at `screen_pos` means, forgivingly: a dungeon's doorway or name; else a tiny area
## close by (fingers are wider than a few pixels); else a name drawn there; else the area under it.
func territory_at(screen_pos: Vector2) -> int:
	for i in campaign.territories.size():
		if campaign.territories[i].dungeon != "" and not _is_lair(i) and _dungeon_marker(i).grow(DUNGEON_TAP_SLOP).has_point(screen_pos):
			return i
	var p := _to_map(screen_pos)
	var under := -1
	for n in range(_draw_order.size() - 1, -1, -1):  # smallest first: enclaves win over what surrounds them
		var i := _draw_order[n]
		for ring in campaign.territories[i].parts:
			if Geometry2D.is_point_in_polygon(p, ring):
				under = i
				break
		if under >= 0:
			break
	if under >= 0 and _is_small(under):
		return under  # zoomed out, everything is small: the one under the finger
	var tiny := -1
	var tiny_d := SMALL_TAP_SLOP
	for i in campaign.territories.size():
		if not _is_small(i):
			continue
		var d := _distance_to_rect(screen_pos, _screen_box(i))
		if d < tiny_d:
			tiny_d = d
			tiny = i
	if tiny >= 0 and tiny_d == 0.0:
		return tiny
	for k in range(_label_hits.size() - 1, -1, -1):  # the last drawn is on top
		if _label_hits[k][0].has_point(screen_pos):
			return _label_hits[k][1]
	return tiny if tiny >= 0 else under


func _screen_box(i: int) -> Rect2:
	return Rect2(_to_screen(_bboxes[i].position), _bboxes[i].size * _view_scale())


func _is_small(i: int) -> bool:
	var box := _screen_box(i)
	return maxf(box.size.x, box.size.y) <= SMALL_AREA


func _distance_to_rect(pt: Vector2, r: Rect2) -> float:
	return Vector2(maxf(maxf(r.position.x - pt.x, 0.0), pt.x - r.end.x), maxf(maxf(r.position.y - pt.y, 0.0), pt.y - r.end.y)).length()
