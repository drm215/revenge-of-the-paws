class_name MapView
extends Control

## Draws the campaign map (territory cells, ownership, threat, lairs) and reports taps on territories.
## Drag to pan; pinch or mouse wheel to zoom.

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
const MIN_ZOOM := 0.3
const MAX_ZOOM := 4.0
const TAP_SLOP := 12.0
const MIN_LABEL_PX := 64.0  # smaller areas only get a label once zoomed in
const LABEL_GAP := 3.0  # px kept clear around each label; crowded labels wait for a closer zoom

var campaign: Campaign
var selected := -1

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
var _fillable := {}  # Vector2i(territory, part) -> whether the ring triangulates cleanly


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel survivor icons
	resized.connect(_fit)
	_fit()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()  # pulsing counterattack + lair glow


## Centers the view on a territory (used when something needs the player's attention).
func focus(i: int) -> void:
	_pan = Vector2.ZERO
	_pan = size / 2.0 - _to_screen(campaign.territories[i].site)
	_clamp_pan()


func _fit() -> void:
	if campaign == null or size.x <= 0:
		return
	# Frame the front line (what you hold and can attack); zoom out to see the whole map.
	var bounds := Rect2(campaign.territories[0].site, Vector2.ZERO)
	_full_bounds = bounds
	for i in campaign.territories.size():
		var t := campaign.territories[i]
		var active := t.owned or campaign.can_attack(i)
		for ring in t.parts:
			for p in ring:
				_full_bounds = _full_bounds.expand(p)
				if active:
					bounds = bounds.expand(p)
	_draw_order.assign(range(campaign.territories.size()))
	_draw_order.sort_custom(func(a: int, b: int) -> bool:
		return campaign.territories[a].area > campaign.territories[b].area)
	_fillable.clear()
	_bboxes.clear()
	for t in campaign.territories:
		var box := Rect2(t.site, Vector2.ZERO)
		for ring in t.parts:
			for p in ring:
				box = box.expand(p)
		_bboxes.append(box)
	for i in campaign.territories.size():
		for k in campaign.territories[i].parts.size():
			_fillable[Vector2i(i, k)] = not Geometry2D.triangulate_polygon(campaign.territories[i].parts[k]).is_empty()
	_fit_scale = minf(size.x / bounds.size.x, size.y / bounds.size.y) * 0.96
	_fit_offset = size / 2.0 - bounds.get_center() * _fit_scale
	_clamp_pan()


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
	queue_redraw()


func _draw() -> void:
	if campaign == null:
		return
	var font := Retro.body_font()
	for i in _draw_order:
		for k in campaign.territories[i].parts.size():
			var poly := _screen_ring(i, k)
			if _fillable.get(Vector2i(i, k), false):
				draw_colored_polygon(poly, _fill(i))
			poly.append(poly[0])
			draw_polyline(poly, BORDER, 2.0, false)

	for i in campaign.territories.size():
		if campaign.territories[i].boss != "" and not campaign.territories[i].owned:
			_outline(i, LAIR.lerp(Color.BLACK, 0.4 + 0.3 * sin(_time * 3.0)), 3.0)
	if selected >= 0:
		_outline(selected, SELECTED, 4.0)

	var font_size := Retro.px(clampf(16 * sqrt(_zoom), 16, 26))
	var placed: Array[Rect2] = []  # labels already drawn; one that would overlap them is skipped
	for i in _label_order():
		var t := campaign.territories[i]
		var c := _to_screen(t.site)
		var is_lair := t.boss != "" and not t.owned
		var label := t.label if t.label.length() <= 13 else t.label.left(12) + "…"
		var color := Color.WHITE
		if i == campaign.home:
			draw_rect(Rect2(c + Vector2(-8, -26), Vector2(16, 16)), SELECTED)
			draw_rect(Rect2(c + Vector2(-8, -26), Vector2(16, 16)), BORDER, false, 3.0)
			label = "HOME"
		elif is_lair:
			label = GameData.LEGENDS[t.boss].name
			color = LAIR
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_box := Rect2(c.x - text_w / 2.0, c.y + 4 - font_size, text_w, font_size * 1.3).grow(LABEL_GAP)
		var must_show := i == campaign.home or i == selected or is_lair
		if must_show or not placed.any(func(r: Rect2) -> bool: return r.intersects(label_box)):
			placed.append(label_box)
			_text(font, c + Vector2(0, 4), label, font_size, color)
		if t.cache != "" and campaign.loot_at(i) != "":
			# A little treasure chest marks a trinket cache.
			var box := Rect2(c + Vector2(26, -30), Vector2(18, 14))
			draw_rect(box.grow(2), BORDER)
			draw_rect(box, Retro.GOLD)
			draw_rect(Rect2(box.position + Vector2(0, 5), Vector2(18, 3)), Color("b86f50"))
		var survivor := campaign.pending_recruit(i)
		if survivor != "":
			draw_texture_rect(_icon(survivor), Rect2(c + Vector2(-20, -48), Vector2(40, 40)), false)
		if not t.owned:
			if t.threat > GameData.MAX_THREAT:
				_text(font, c + Vector2(0, 36), "+%d" % (t.threat - GameData.MAX_THREAT), Retro.px(12), THREAT_PIP)
			for k in mini(t.threat, GameData.MAX_THREAT):
				var pip := c + Vector2((k - (mini(t.threat, GameData.MAX_THREAT) - 1) / 2.0) * 10 - 3, 10)
				draw_rect(Rect2(pip - Vector2(1, 1), Vector2(8, 8)), BORDER)
				draw_rect(Rect2(pip, Vector2(6, 6)), THREAT_PIP)


## Territories big enough on screen to label, most important first: home and the selection, lairs,
## what you can attack, other unheld areas, then what you hold; bigger areas first within each.
func _label_order() -> Array[int]:
	var rank := {}
	var area := {}
	var order: Array[int] = []
	for i in campaign.territories.size():
		var t := campaign.territories[i]
		var is_lair := t.boss != "" and not t.owned
		var on_screen := _bboxes[i].size * _fit_scale * _zoom
		if i == campaign.home or i == selected:
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
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, 6, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)


func _screen_ring(i: int, k: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in campaign.territories[i].parts[k]:
		out.append(_to_screen(p))
	return out


func _outline(i: int, color: Color, width: float) -> void:
	for k in campaign.territories[i].parts.size():
		var poly := _screen_ring(i, k)
		poly.append(poly[0])
		draw_polyline(poly, color, width, false)


func _fill(i: int) -> Color:
	var t := campaign.territories[i]
	if i == campaign.under_attack:
		return OWNED.lerp(UNDER_ATTACK, 0.5 + 0.5 * sin(_time * 5.0))
	if t.owned:
		return HOME if i == campaign.home else OWNED
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
				queue_redraw()
				territory_selected.emit(i)
				return
