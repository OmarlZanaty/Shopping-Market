"""
Point-in-polygon for delivery zones.

Deliberately dependency-free. shapely would work, but it needs GEOS binaries in
the production image, and the whole job here is "is this one point inside one of
a handful of polygons" — a ray-casting test in pure Python answers that in
microseconds. Revisit only if zones ever reach the thousands, at which point
PostGIS (not shapely) is the right move.

Coordinates are GeoJSON order throughout: [longitude, latitude].
"""
import math

EARTH_RADIUS_KM = 6371.0088


def haversine_km(lat1, lng1, lat2, lng2):
    """Great-circle distance in kilometres."""
    lat1, lng1, lat2, lng2 = map(math.radians, (float(lat1), float(lng1), float(lat2), float(lng2)))
    dlat = lat2 - lat1
    dlng = lng2 - lng1
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def rings_of(geometry):
    """Yield each linear ring of a GeoJSON Polygon or MultiPolygon.

    Yields (ring, is_hole). A Polygon's first ring is its outline and the rest
    are holes; a MultiPolygon repeats that per part.
    """
    if not isinstance(geometry, dict):
        return
    gtype = geometry.get('type')
    coords = geometry.get('coordinates') or []
    if gtype == 'Polygon':
        polygons = [coords]
    elif gtype == 'MultiPolygon':
        polygons = coords
    else:
        return
    for polygon in polygons:
        for index, ring in enumerate(polygon):
            if ring and len(ring) >= 3:
                yield ring, index > 0


def bbox_of(geometry):
    """(min_lng, min_lat, max_lng, max_lat), or None for an empty geometry."""
    min_lng = min_lat = float('inf')
    max_lng = max_lat = float('-inf')
    found = False
    for ring, _ in rings_of(geometry):
        for point in ring:
            lng, lat = float(point[0]), float(point[1])
            min_lng, max_lng = min(min_lng, lng), max(max_lng, lng)
            min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
            found = True
    if not found:
        return None
    return [min_lng, min_lat, max_lng, max_lat]


def in_bbox(lat, lng, bbox):
    if not bbox or len(bbox) != 4:
        return True  # unknown bbox — fall through to the exact test
    min_lng, min_lat, max_lng, max_lat = bbox
    return min_lng <= lng <= max_lng and min_lat <= lat <= max_lat


def _ring_contains(ring, lat, lng):
    """Ray casting: does this ring enclose the point?

    A point exactly on an edge is treated as inside — a customer standing on a
    zone border should be served, not rejected on a floating-point tie.
    """
    inside = False
    count = len(ring)
    j = count - 1
    for i in range(count):
        xi, yi = float(ring[i][0]), float(ring[i][1])
        xj, yj = float(ring[j][0]), float(ring[j][1])

        # On-edge check (within a ~1cm tolerance at these latitudes).
        if _on_segment(lng, lat, xi, yi, xj, yj):
            return True

        if (yi > lat) != (yj > lat):
            x_cross = (xj - xi) * (lat - yi) / (yj - yi) + xi
            if lng < x_cross:
                inside = not inside
        j = i
    return inside


def _on_segment(px, py, ax, ay, bx, by, tolerance=1e-9):
    cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    if abs(cross) > tolerance:
        return False
    return min(ax, bx) - tolerance <= px <= max(ax, bx) + tolerance and \
        min(ay, by) - tolerance <= py <= max(ay, by) + tolerance


def contains_point(geometry, lat, lng):
    """Is (lat, lng) inside this GeoJSON Polygon/MultiPolygon, holes excluded?"""
    lat, lng = float(lat), float(lng)
    inside = False
    for ring, is_hole in rings_of(geometry):
        if _ring_contains(ring, lat, lng):
            if is_hole:
                return False
            inside = True
    return inside


def circle_to_polygon(lat, lng, radius_km, segments=64):
    """A circle as a GeoJSON Polygon.

    Used to convert a branch's legacy delivery_radius_km into a real zone, so
    the migration from circles to shapes is one click in the dashboard.
    """
    lat, lng, radius_km = float(lat), float(lng), float(radius_km)
    lat_rad = math.radians(lat)
    km_per_deg_lat = 110.574
    km_per_deg_lng = 111.320 * math.cos(lat_rad) or 1e-9

    ring = []
    for i in range(segments):
        theta = 2 * math.pi * i / segments
        ring.append([
            lng + (radius_km / km_per_deg_lng) * math.cos(theta),
            lat + (radius_km / km_per_deg_lat) * math.sin(theta),
        ])
    ring.append(ring[0])  # GeoJSON rings must close
    return {'type': 'Polygon', 'coordinates': [ring]}


def _orient(ax, ay, bx, by, cx, cy):
    """Sign of the cross product: >0 left turn, <0 right turn, 0 collinear."""
    value = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    if abs(value) < 1e-12:
        return 0
    return 1 if value > 0 else -1


def _segments_cross(p1, p2, p3, p4):
    """Do segments p1p2 and p3p4 properly cross, or overlap while collinear?"""
    d1 = _orient(p3[0], p3[1], p4[0], p4[1], p1[0], p1[1])
    d2 = _orient(p3[0], p3[1], p4[0], p4[1], p2[0], p2[1])
    d3 = _orient(p1[0], p1[1], p2[0], p2[1], p3[0], p3[1])
    d4 = _orient(p1[0], p1[1], p2[0], p2[1], p4[0], p4[1])
    if d1 * d2 < 0 and d3 * d4 < 0:
        return True
    # A ring that doubles back along itself is as unanswerable for the
    # containment test as a bow tie, so collinear overlap counts as crossing.
    if d1 == d2 == d3 == d4 == 0:
        return (_on_segment(p3[0], p3[1], p1[0], p1[1], p2[0], p2[1])
                or _on_segment(p4[0], p4[1], p1[0], p1[1], p2[0], p2[1])
                or _on_segment(p1[0], p1[1], p3[0], p3[1], p4[0], p4[1]))
    return False


# Past this the O(n²) pair scan stops paying for itself; such a ring comes from
# an imported boundary, not from someone clicking a map.
MAX_VALIDATED_POINTS = 400

# ~1e-10 deg² is far under a square metre — anything smaller has no interior.
MIN_RING_AREA_DEG2 = 1e-10


def _open_ring(ring):
    points = [(float(p[0]), float(p[1])) for p in ring]
    if len(points) > 1 and points[0] == points[-1]:
        points = points[:-1]
    return points


def ring_self_intersects(ring):
    """Does this ring cross itself? (bow tie, figure eight, doubled edge)"""
    points = _open_ring(ring)
    count = len(points)
    if count < 4 or count > MAX_VALIDATED_POINTS:
        return False
    for i in range(count):
        a1, a2 = points[i], points[(i + 1) % count]
        for j in range(i + 1, count):
            # Neighbouring segments legitimately share an endpoint.
            if (j + 1) % count == i or j == (i + 1) % count:
                continue
            if _segments_cross(a1, a2, points[j], points[(j + 1) % count]):
                return True
    return False


def ring_area_deg2(ring):
    """Unsigned shoelace area, in square degrees. Only used to spot a ring with
    no real interior: repeated clicks, or every point on one line."""
    points = _open_ring(ring)
    count = len(points)
    total = 0.0
    for i in range(count):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % count]
        total += x1 * y2 - x2 * y1
    return abs(total) / 2


def validate_geometry(geometry):
    """Return a cleaned GeoJSON geometry or raise ValueError.

    Rejects anything the containment test cannot answer, so a malformed shape
    fails at save time in the dashboard rather than silently refusing every
    customer at checkout.
    """
    if not isinstance(geometry, dict):
        raise ValueError('geometry must be a GeoJSON object')
    gtype = geometry.get('type')
    if gtype not in ('Polygon', 'MultiPolygon'):
        raise ValueError('geometry.type must be Polygon or MultiPolygon')

    rings = list(rings_of(geometry))
    if not rings:
        raise ValueError('geometry has no usable ring (need at least 3 points)')

    for ring, _ in rings:
        for point in ring:
            if not isinstance(point, (list, tuple)) or len(point) < 2:
                raise ValueError('every coordinate must be [longitude, latitude]')
            lng, lat = float(point[0]), float(point[1])
            if not (-180 <= lng <= 180) or not (-90 <= lat <= 90):
                raise ValueError(f'coordinate out of range: [{lng}, {lat}]')

        # A bow tie or a zero-area sliver saves happily but answers "is this
        # customer inside?" nonsensically, so refuse it at the door.
        if ring_area_deg2(ring) < MIN_RING_AREA_DEG2:
            raise ValueError('zone has no area — the points are on one line or repeated')
        if ring_self_intersects(ring):
            raise ValueError('zone edges cross each other — untangle the shape')

    return geometry
