import React, { useEffect } from 'react';
import { MapContainer, TileLayer, Polygon, Marker, Circle, useMapEvents, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { ringsToLatLngs } from '../../utils/zoneGeometry';

/**
 * OpenStreetMap fallback for the delivery-zone editor.
 *
 * Kept so the page still works when VITE_GOOGLE_MAPS_API_KEY is not set —
 * without it, a missing key would leave admins staring at a blank panel with
 * no way to draw. Same props and same interaction as the Google version.
 */

// Leaflet's default marker images break under Vite's bundler; div icons
// sidestep asset resolution entirely.
const FALLBACK_PIN =
  '<div style="font-size:26px;line-height:26px;transform:translate(-13px,-26px)">🏪</div>';

// A logo_url is admin-entered, so it is escaped before going anywhere near an
// HTML attribute rather than trusted.
const escapeAttr = (value) =>
  String(value).replace(/&/g, '&amp;').replace(/"/g, '&quot;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;');

// The branch is pinned with the store's own logo, so the marker reads as "this
// shop". A broken or missing logo falls back to the 🏪 pin.
const makeBranchIcon = (logoUrl) => L.divIcon({
  className: '',
  html: logoUrl
    ? `<div style="width:42px;height:42px;transform:translate(-21px,-21px)">
         <img src="${escapeAttr(logoUrl)}" alt=""
              style="width:42px;height:42px;border-radius:50%;object-fit:cover;background:#fff;border:2px solid #fff;box-shadow:0 1px 6px rgba(0,0,0,.35)"
              onerror="this.remove()" />
       </div>`
    : FALLBACK_PIN,
  iconSize: [42, 42],
});
const vertexIcon = L.divIcon({
  className: '',
  html: '<div style="width:11px;height:11px;border-radius:50%;background:#2FBE8F;border:2px solid #fff;box-shadow:0 0 3px rgba(0,0,0,.4);transform:translate(-5px,-5px)"></div>',
  iconSize: [11, 11],
});

function ClickCatcher({ active, onClick }) {
  useMapEvents({ click: (e) => active && onClick([e.latlng.lat, e.latlng.lng]) });
  return null;
}

function Recenter({ center, zoom }) {
  const map = useMap();
  useEffect(() => {
    if (center) map.setView(center, zoom);
  }, [center?.[0], center?.[1]]);
  return null;
}

export default function ZoneMapLeaflet({
  center, zoom = 14, branch, zones, draft, drawing, editingId,
  showRadius, radiusKm, onMapClick, onVertexMove, onVertexDelete,
}) {
  return (
    <MapContainer center={center} zoom={zoom} style={{ height: '100%', width: '100%' }}>
      <TileLayer
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        attribution="&copy; OpenStreetMap"
      />
      <Recenter center={center} zoom={zoom} />
      <ClickCatcher active={drawing} onClick={onMapClick} />

      {branch && (
        <Marker
          position={center}
          icon={makeBranchIcon(branch.store_logo_url)}
          title={branch.name_ar || branch.name}
          zIndexOffset={600}
        />
      )}

      {showRadius && (
        <Circle
          center={center}
          radius={Number(radiusKm || 0) * 1000}
          pathOptions={{ color: '#94a3b8', dashArray: '6', fillOpacity: 0.05 }}
        />
      )}

      {zones.filter((z) => z.id !== editingId).map((zone) => (
        <Polygon
          key={zone.id}
          positions={ringsToLatLngs(zone.geometry)}
          pathOptions={{
            color: zone.is_active ? '#2E5E99' : '#9ca3af',
            fillOpacity: zone.is_active ? 0.18 : 0.06,
          }}
        />
      ))}

      {draft.length >= 2 && (
        <Polygon positions={draft} pathOptions={{ color: '#2FBE8F', fillOpacity: 0.2 }} />
      )}

      {drawing && draft.map((point, i) => (
        <Marker
          key={i}
          position={point}
          icon={vertexIcon}
          draggable
          eventHandlers={{
            dragend: (e) => {
              const { lat, lng } = e.target.getLatLng();
              onVertexMove(i, { lat, lng });
            },
            // Clicking a point removes it — undo only reaches the last one.
            click: () => onVertexDelete && onVertexDelete(i),
          }}
        />
      ))}
    </MapContainer>
  );
}
