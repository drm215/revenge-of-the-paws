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
const INFESTED := Color("4f3446")
const INFESTED_DEEP := Color("2c1f2e")
const UNDER_ATTACK := Retro.RED
const BORDER := Retro.INK
const SELECTED := Retro.YELLOW
const THREAT_PIP := Retro.RED
const LAIR := Color("f6a0e0")
const CUT_OFF := Color("2a4a33")  # held but cut off from home
const NEST := Color("b8203a")
const MIN_ZOOM := 0.3
const MAX_ZOOM := 4.0
const TAP_SLOP := 12.0
const MIN_LABEL_PX := 64.0  # smaller areas only get a label once zoomed in
const LABEL_GAP := 3.0  # px kept clear around each label; crowded labels wait for a closer zoom
const LABEL_MARGIN := 120.0  # labels this far off screen can still reach into view; beyond it they're skipped
const PULSE_INTERVAL := 0.05  # seconds between redraws of what glows
const OUTLINE_RETRY := 5.0  # seconds before asking again for outlines that didn't arrive

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
var _loading := Label.new()  # shown while this map's outlines are being fetched


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
	_pulse_wait -= delta
	if _pulse_wait > 0.0:
		return
	_pulse_wait = PULSE_INTERVAL
	if _outlines_pulse:
		_pulse.queue_redraw()
	if _fills_pulse:
		_shapes.queue_redraw()


## The game changed (ownership, selection, pings): draw it all again.
func refresh() -> void:
	_fills_pulse = false
	_outlines_pulse = not pings.is_empty()
	if campaign:
		_fills_pulse = campaign.under_attack >= 0
		for i in campaign.territories.size():
			_fills_pulse = _fills_pulse or campaign.is_cut_off(i)
			_outlines_pulse = _outlines_pulse or campaign.is_nest(i) or _is_lair(i)
	for layer: Node2D in [_shapes, _pulse, _labels]:
		layer.queue_redraw()


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
	if not is_equal_approx(_shapes_scale, _view_scale()):
		_shapes_scale = _view_scale()
		_shapes.queue_redraw()
	_pulse.queue_redraw()
	_labels.queue_redraw()


func _draw_shapes() -> void:
	if campaign == null or _parts.is_empty():
		return
	var item := _shapes.get_canvas_item()
	var width := 2.0 / _view_scale()
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
	for i in campaign.territories.size():
		if _is_lair(i):
			_outline(i, LAIR.lerp(Color.BLACK, 0.4 + 0.3 * sin(_time * 3.0)), 3.0)
	for i in campaign.territories.size():
		if pings.has(campaign.territories[i].id):
			_outline(i, Retro.CYAN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 6.0)), 5.0)
	if selected >= 0:
		_outline(selected, SELECTED, 4.0)
	_pulse.draw_set_transform(Vector2.ZERO)
	for i in campaign.territories.size():
		if campaign.is_nest(i):
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
	var font_size := Retro.px(clampf(16 * sqrt(_zoom), 16, 26))
	var placed: Array[Rect2] = []  # labels already drawn; one that would overlap them is skipped
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
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_box := Rect2(c.x - text_w / 2.0, c.y + 4 - font_size, text_w, font_size * 1.3).grow(LABEL_GAP)
		var must_show := i in campaign.homes or i == selected or is_lair
		if must_show or not placed.any(func(r: Rect2) -> bool: return r.intersects(label_box)):
			placed.append(label_box)
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
		if not t.owned:
			if t.threat > GameData.MAX_THREAT:
				_text(font, c + Vector2(0, 36), "+%d" % (t.threat - GameData.MAX_THREAT), Retro.px(12), THREAT_PIP)
			for k in mini(t.threat, GameData.MAX_THREAT):
				var pip := c + Vector2((k - (mini(t.threat, GameData.MAX_THREAT) - 1) / 2.0) * 10 - 3, 10)
				_labels.draw_rect(Rect2(pip - Vector2(1, 1), Vector2(8, 8)), BORDER)
				_labels.draw_rect(Rect2(pip, Vector2(6, 6)), THREAT_PIP)


## Territories big enough on screen to label, most important first: home and the selection, lairs,
## what you can attack, other unheld areas, then what you hold; bigger areas first within each.
func _label_order() -> Array[int]:
	var rank := {}
	var area := {}
	var order: Array[int] = []
	for i in campaign.territories.size():
		var t := campaign.territories[i]
		var is_lair := _is_lair(i)
		var on_screen := _bboxes[i].size * _fit_scale * _zoom
		if i in campaign.homes or i == selected:
			rank[i] = 0
		elif is_lair:
			rank[i] = 1
		elif maxf(on_screen.x, on_screen.y) < MIN_LABEL_PX:
			continue
		elif campaign.is_actionable(i):
			rank[i] = 2
		else:
			rank[i] = 4 if t.owned else 3
		area[i] = on_screen.x * on_screen.y
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return rank[a] < rank[b] if rank[a] != rank[b] else area[a] > area[b])
	return order


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
	if i == campaign.under_attack:
		return OWNED.lerp(UNDER_ATTACK, 0.5 + 0.5 * sin(_time * 5.0))
	if t.owned:
		if campaign.is_cut_off(i):
			return CUT_OFF.lerp(INFESTED, 0.25 + 0.25 * sin(_time * 2.0))
		return HOME if i in campaign.homes else OWNED
	if campaign.can_attack(i):
		return ATTACKABLE
	return INFESTED.lerp(INFESTED_DEEP, float(t.threat) / GameData.MAX_THREAT)


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


func _select_at(screen_pos: Vector2) -> void:
	var p := _to_map(screen_pos)
	for n in range(_draw_order.size() - 1, -1, -1):  # smallest first: enclaves win over what surrounds them
		var i := _draw_order[n]
		for ring in campaign.territories[i].parts:
			if Geometry2D.is_point_in_polygon(p, ring):
				selected = i
				refresh()
				territory_selected.emit(i)
				return
