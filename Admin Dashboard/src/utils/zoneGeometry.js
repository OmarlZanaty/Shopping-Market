/**
 * GeoJSON helpers for the delivery-zone editor.
 *
 * Zones come back as either a Polygon or a MultiPolygon (imported boundaries
 * are often several disjoint parts). Everything here works in [lat, lng] on the
 * React side and converts to GeoJSON's [lng, lat] only at the edges, so a map
 * component never has to think about the ordering.
 */

const isRing = (value) =>
  Array.isArray(value) && Array.isArray(value[0]) && typeof value[0][0] === 'number';

/** Every polygon of a geometry, as arrays of rings: [[outer, ...holes], ...]. */
export const polygonsOf = (geometry) => {
  const coords = geometry?.coordinates;
  if (!Array.isArray(coords)) return [];
  if (geometry.type === 'MultiPolygon') return coords.filter(Array.isArray);
  if (geometry.type === 'Polygon') return [coords.filter(isRing)];
  return [];
};

const ringToLatLngs = (ring) =>
  (ring || [])
    .filter((p) => Array.isArray(p) && p.length >= 2)
    .map(([lng, lat]) => [Number(lat), Number(lng)]);

const closed = (ring) => {
  if (ring.length < 2) return ring;
  const [first] = ring;
  const last = ring[ring.length - 1];
  return first[0] === last[0] && first[1] === last[1] ? ring.slice(0, -1) : ring;
};

/** Every ring of the geometry as [lat, lng] paths — what the maps draw. */
export const ringsToLatLngs = (geometry) =>
  polygonsOf(geometry).flatMap((polygon) =>
    polygon.map((ring) => closed(ringToLatLngs(ring))).filter((r) => r.length >= 3),
  );

/**
 * The ring the admin edits: the outer ring of the first polygon.
 *
 * A MultiPolygon's other parts and any holes are left alone — `buildGeometry`
 * puts them back untouched, so editing one part never silently discards the
 * rest (which is exactly what the old `coordinates[0]` shortcut did).
 */
export const editableRing = (geometry) => {
  const [first] = polygonsOf(geometry);
  return first ? closed(ringToLatLngs(first[0])) : [];
};

/** True when this zone has parts or holes the editor is not showing. */
export const hasExtraParts = (geometry) => {
  const polygons = polygonsOf(geometry);
  return polygons.length > 1 || (polygons[0]?.length || 0) > 1;
};

// ── Draft validation ─────────────────────────────────────────────────────────
// Mirrors apps/branches/geo.py: the server refuses a ring that crosses itself
// or encloses nothing, because the point-in-polygon test cannot answer either.
// Checking here too turns a 400 into a message while the shape is still on
// screen and fixable.

const orient = (a, b, c) => {
  const value = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  return Math.abs(value) < 1e-12 ? 0 : Math.sign(value);
};

const segmentsCross = (p1, p2, p3, p4) => {
  const d1 = orient(p3, p4, p1);
  const d2 = orient(p3, p4, p2);
  const d3 = orient(p1, p2, p3);
  const d4 = orient(p1, p2, p4);
  return d1 * d2 < 0 && d3 * d4 < 0;
};

/** Does this [lat, lng] ring cross itself? (bow tie, figure eight) */
export const ringSelfIntersects = (latlngs) => {
  const points = closed(latlngs || []);
  const count = points.length;
  if (count < 4) return false;
  for (let i = 0; i < count; i += 1) {
    const a1 = points[i];
    const a2 = points[(i + 1) % count];
    for (let j = i + 1; j < count; j += 1) {
      // Neighbouring segments legitimately share an endpoint.
      if ((j + 1) % count === i || j === (i + 1) % count) continue;
      if (segmentsCross(a1, a2, points[j], points[(j + 1) % count])) return true;
    }
  }
  return false;
};

/** Unsigned shoelace area in square degrees — spots a ring with no interior. */
export const ringArea = (latlngs) => {
  const points = closed(latlngs || []);
  let total = 0;
  for (let i = 0; i < points.length; i += 1) {
    const [y1, x1] = points[i];
    const [y2, x2] = points[(i + 1) % points.length];
    total += x1 * y2 - x2 * y1;
  }
  return Math.abs(total) / 2;
};

// Same threshold the server uses — far under a square metre.
export const MIN_RING_AREA = 1e-10;

const toGeoJSONRing = (latlngs) => {
  const ring = latlngs.map(([lat, lng]) => [Number(lng), Number(lat)]);
  if (ring.length) ring.push(ring[0]); // GeoJSON rings must close
  return ring;
};

/**
 * Rebuild a geometry from the edited outer ring, keeping everything else.
 *
 * `original` is the geometry that was loaded for editing; omit it for a new
 * zone and you get a plain Polygon.
 */
export const buildGeometry = (latlngs, original) => {
  const ring = toGeoJSONRing(latlngs);
  const polygons = polygonsOf(original);
  if (!polygons.length) return { type: 'Polygon', coordinates: [ring] };

  const rebuilt = polygons.map((polygon, index) =>
    index === 0 ? [ring, ...polygon.slice(1)] : polygon,
  );
  return original.type === 'MultiPolygon'
    ? { type: 'MultiPolygon', coordinates: rebuilt }
    : { type: 'Polygon', coordinates: rebuilt[0] };
};
