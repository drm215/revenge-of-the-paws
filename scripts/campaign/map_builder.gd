class_name MapBuilder
extends RefCounted

## For maps without real boundaries (outside the US): turns territory sites into a Voronoi map,
## one cell per site, neighbors = shared borders.

const BOUNDARY_SEGMENTS := 40
const RELAX_PASSES := 2


## Evens out real-world geography so dense downtowns don't become slivers: each site keeps its
## direction and distance *rank* from home, then a few Lloyd passes even out cell sizes.
static func spread(territories: Array[Territory], home: int) -> void:
	var origin := territories[home].site
	var order := range(territories.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return territories[a].site.distance_squared_to(origin) < territories[b].site.distance_squared_to(origin))
	var last := float(territories.size() - 1)
	for rank in order.size():
		var t := territories[order[rank]]
		var dir := (t.site - origin).normalized() if rank > 0 else Vector2.ZERO
		t.site = dir * sqrt(rank / last) * 10.0
	for pass_index in RELAX_PASSES:
		build(territories)
		for i in territories.size():
			if i != home:
				territories[i].site = _centroid(territories[i].parts[0])


static func build(territories: Array[Territory]) -> void:
	var n := territories.size()
	var center := Vector2.ZERO
	for t in territories:
		center += t.site
	center /= n
	var radius := 0.0
	for t in territories:
		radius = maxf(radius, t.site.distance_to(center))
	var spacing := radius / sqrt(n)
	radius += spacing * 0.9

	# Organic outer edge instead of a hard circle.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(territories[0].id)
	var boundary := PackedVector2Array()
	for k in BOUNDARY_SEGMENTS:
		var wobble := 1.0 + rng.randf_range(-0.06, 0.06)
		boundary.append(center + Vector2.from_angle(TAU * k / BOUNDARY_SEGMENTS) * radius * wobble)

	for i in n:
		var poly := boundary
		for j in n:
			if i != j:
				poly = _clip_half_plane(poly, territories[i].site, territories[j].site)
		territories[i].parts = [poly]
		territories[i].neighbors.clear()

	var eps := spacing * 0.002
	for i in n:
		for j in range(i + 1, n):
			if _shares_border(territories[i], territories[j], eps, spacing * 0.05):
				territories[i].neighbors.append(j)
				territories[j].neighbors.append(i)


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var area := 0.0
	var c := Vector2.ZERO
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var cross := p.cross(q)
		area += cross
		c += (p + q) * cross
	return c / (3.0 * area) if absf(area) > 1e-9 else poly[0]


## Keeps the part of `poly` closer to `a` than to `b` (Sutherland–Hodgman against the bisector).
static func _clip_half_plane(poly: PackedVector2Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var normal := b - a
	var mid := (a + b) * 0.5
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var dp := (p - mid).dot(normal)
		var dq := (q - mid).dot(normal)
		if dp <= 0.0:
			out.append(p)
		if (dp <= 0.0) != (dq <= 0.0):
			out.append(p + (q - p) * (dp / (dp - dq)))
	return out


## True if some edge of a's cell lies on the a/b bisector and is long enough to count as a border.
static func _shares_border(a: Territory, b: Territory, eps: float, min_len: float) -> bool:
	var poly := a.parts[0]
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		if p.distance_to(q) < min_len:
			continue
		if absf(p.distance_to(a.site) - p.distance_to(b.site)) < eps \
				and absf(q.distance_to(a.site) - q.distance_to(b.site)) < eps:
			return true
	return false
