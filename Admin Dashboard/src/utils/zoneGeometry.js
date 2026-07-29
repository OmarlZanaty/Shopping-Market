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
