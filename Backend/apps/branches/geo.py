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
    return geometry
