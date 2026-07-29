import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { GoogleMap, useJsApiLoader, Polygon, Marker, Circle } from '@react-google-maps/api';
import { ringsToLatLngs } from '../../utils/zoneGeometry';

/**
 * Google Maps implementation of the delivery-zone editor.
 *
 * Interaction is deliberately identical to the Leaflet fallback: click to drop
 * a vertex, drag a vertex to move it. Google's DrawingManager was not used —
 * it owns its own overlay lifecycle, which fights the "draft lives in React
 * state" model the page is built on, for no gain over a plain click handler.
 *
 * The map opens on the branch and at a close zoom, because zones are drawn
 * around the market itself and the first thing you need to see is the streets
 * next to it, not the governorate.
 */

const CONTAINER = { width: '100%', height: '100%' };

// Landmarks are how an admin actually knows where a boundary should run, so
// nothing is hidden. POI clicks used to steal vertex drops, but clickableIcons
// already handles that — styling the shops away as well only emptied the map
// in the small towns where the few shops are the only landmarks there are.
const MAP_OPTIONS = {
  streetViewControl: false,
  mapTypeControl: true,
  fullscreenControl: true,
  clickableIcons: false,          // stop POI clicks from stealing vertex drops
};

// Every ring, holes included — Google fills with the even-odd rule, so passing
// them all is what makes a hole actually read as a hole.
const toPaths = (geometry) =>
  ringsToLatLngs(geometry).map((ring) => ring.map(([lat, lng]) => ({ lat, lng })));

const LOGO_SIZE = 42;

export default function ZoneMapGoogle({
  apiKey, center, zoom = 14, branch, zones, draft, drawing, editingId,
  showRadius, radiusKm, onMapClick, onVertexMove, onVertexDelete,
}) {
  const { isLoaded, loadError } = useJsApiLoader({
    id: 'shoppingmarket-maps',
    googleMapsApiKey: apiKey,
  });
  const mapRef = useRef(null);

  const onLoad = useCallback((map) => { mapRef.current = map; }, []);

  // Recentre when the admin switches branch — the zone is always drawn around
  // the branch, so following the selection is the expected behaviour.
  useEffect(() => {
    if (mapRef.current && center) {
      mapRef.current.panTo({ lat: center[0], lng: center[1] });
    }
  }, [center?.[0], center?.[1]]);

  const draftPath = useMemo(() => draft.map(([lat, lng]) => ({ lat, lng })), [draft]);

  // A Google marker whose icon URL 404s renders nothing at all, so the logo is
  // loaded first and the 🏪 pin stays the fallback for stores without one.
  const logoUrl = branch?.store_logo_url || '';
  const [logoOk, setLogoOk] = useState(false);
  useEffect(() => {
    setLogoOk(false);
    if (!logoUrl) return undefined;
    const image = new Image();
    let alive = true;
    image.onload = () => { if (alive) setLogoOk(true); };
    image.src = logoUrl;
    return () => { alive = false; };
  }, [logoUrl]);

  if (loadError) {
    return (
      <div className="h-full flex items-center justify-center text-sm text-red-600 p-6 text-center">
        تعذّر تحميل خرائط Google — تأكد من صلاحية المفتاح وتفعيل Maps JavaScript API.
        <br />Google Maps failed to load — check the key and that Maps JavaScript API is enabled.
      </div>
    );
  }
  if (!isLoaded) {
    return (
      <div className="h-full flex items-center justify-center">
        <div className="animate-spin w-7 h-7 border-4 border-[#2E5E99] border-t-transparent rounded-full" />
      </div>
    );
  }

  return (
    <GoogleMap
      mapContainerStyle={CONTAINER}
      center={{ lat: center[0], lng: center[1] }}
      zoom={zoom}
      options={MAP_OPTIONS}
      onLoad={onLoad}
      onClick={(e) => drawing && onMapClick([e.latLng.lat(), e.latLng.lng()])}
    >
      {branch && (
        <Marker
          position={{ lat: center[0], lng: center[1] }}
          title={branch.name_ar || branch.name}
          {...(logoOk
            ? {
                icon: {
                  url: branch.store_logo_url,
                  scaledSize: new window.google.maps.Size(LOGO_SIZE, LOGO_SIZE),
                  anchor: new window.google.maps.Point(LOGO_SIZE / 2, LOGO_SIZE / 2),
                },
              }
            : {
                label: { text: '🏪', fontSize: '22px' },
                icon: { path: window.google.maps.SymbolPath.CIRCLE, scale: 0 },
              })}
          zIndex={6}
        />
      )}

      {showRadius && (
        <Circle
          center={{ lat: center[0], lng: center[1] }}
          radius={Number(radiusKm || 0) * 1000}
          options={{ strokeColor: '#94a3b8', strokeOpacity: 0.8, fillOpacity: 0.05, clickable: false }}
        />
      )}

      {zones.filter((z) => z.id !== editingId).map((zone) => (
        <Polygon
          key={zone.id}
          paths={toPaths(zone.geometry)}
          options={{
            strokeColor: zone.is_active ? '#2E5E99' : '#9ca3af',
            fillColor: zone.is_active ? '#2E5E99' : '#9ca3af',
            fillOpacity: zone.is_active ? 0.18 : 0.06,
            clickable: false,
          }}
        />
      ))}

      {draftPath.length >= 2 && (
        <Polygon
          paths={draftPath}
          options={{
            strokeColor: '#2FBE8F', fillColor: '#2FBE8F',
            fillOpacity: 0.2, clickable: false,
          }}
        />
      )}

      {drawing && draftPath.map((point, i) => (
        <Marker
          key={i}
          position={point}
          draggable
          title="حذف النقطة / click to delete"
          onDragEnd={(e) => onVertexMove(i, { lat: e.latLng.lat(), lng: e.latLng.lng() })}
          onClick={() => onVertexDelete?.(i)}
          icon={{
            path: window.google.maps.SymbolPath.CIRCLE,
            scale: 6,
            fillColor: '#2FBE8F',
            fillOpacity: 1,
            strokeColor: '#ffffff',
            strokeWeight: 2,
          }}
          zIndex={10}
        />
      ))}
    </GoogleMap>
  );
}
