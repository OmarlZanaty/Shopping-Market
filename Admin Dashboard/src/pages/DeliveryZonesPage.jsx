import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { MapContainer, TileLayer, Polygon, Marker, Circle, useMapEvents, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { branchApi, zoneApi } from '../services/api';
import { useOutletContext } from 'react-router-dom';
import toast from 'react-hot-toast';

/**
 * Delivery zones — draw the area a branch delivers to, instead of a radius.
 *
 * Drawing is hand-rolled rather than pulling in leaflet-draw: the whole
 * interaction is "click to drop points, drag to adjust, close the ring", which
 * is less code than configuring a plugin and keeps the bundle as it was.
 *
 * The map opens on the selected branch, since a zone is always drawn around
 * the market's own location.
 */

const unwrap = (res) => (res?.data?.success !== undefined ? res.data.data : res?.data);

// Leaflet's default marker images break under Vite's bundler; a div icon
// sidesteps the asset resolution entirely.
const branchIcon = L.divIcon({
  className: '',
  html: '<div style="font-size:26px;line-height:26px;transform:translate(-13px,-26px)">🏪</div>',
  iconSize: [26, 26],
});
const vertexIcon = L.divIcon({
  className: '',
  html: '<div style="width:11px;height:11px;border-radius:50%;background:#2FBE8F;border:2px solid #fff;box-shadow:0 0 3px rgba(0,0,0,.4);transform:translate(-5px,-5px)"></div>',
  iconSize: [11, 11],
});

// GeoJSON is [lng, lat]; Leaflet is [lat, lng]. Keeping the conversion in two
// named helpers avoids the silent lat/lng swap this API invites.
const toLatLngs = (geometry) =>
  (geometry?.coordinates?.[0] || []).slice(0, -1).map(([lng, lat]) => [lat, lng]);

const toGeoJSON = (latlngs) => {
  const ring = latlngs.map(([lat, lng]) => [lng, lat]);
  if (ring.length) ring.push(ring[0]); // GeoJSON rings must close
  return { type: 'Polygon', coordinates: [ring] };
};

function ClickCatcher({ active, onClick }) {
  useMapEvents({ click: (e) => active && onClick([e.latlng.lat, e.latlng.lng]) });
  return null;
}

function Recenter({ center }) {
  const map = useMap();
  useEffect(() => {
    if (center) map.setView(center, map.getZoom() < 11 ? 12 : map.getZoom());
  }, [center?.[0], center?.[1]]);
  return null;
}

export default function DeliveryZonesPage() {
  const { lang } = useOutletContext() || { lang: 'ar' };
  const t = (ar, en) => (lang === 'ar' ? ar : en);
  const qc = useQueryClient();

  const [branchId, setBranchId] = useState(null);
  const [drawing, setDrawing] = useState(false);
  const [draft, setDraft] = useState([]);          // [[lat,lng], ...]
  const [editingId, setEditingId] = useState(null);
  const [name, setName] = useState('');

  const { data: branches = [] } = useQuery({
    queryKey: ['admin-branches'],
    queryFn: () => branchApi.list().then(unwrap),
  });

  useEffect(() => {
    if (!branchId && branches.length) setBranchId(branches[0].id);
  }, [branches, branchId]);

  const branch = useMemo(
    () => branches.find((b) => b.id === Number(branchId)),
    [branches, branchId],
  );

  const { data: zones = [] } = useQuery({
    queryKey: ['delivery-zones', branchId],
    queryFn: () => zoneApi.list(branchId).then(unwrap),
    enabled: !!branchId,
  });

  const center = branch
    ? [Number(branch.latitude), Number(branch.longitude)]
    : [30.0444, 31.2357]; // Cairo, only until a branch loads

  const invalidate = () => qc.invalidateQueries({ queryKey: ['delivery-zones', branchId] });

  const saveZone = useMutation({
    mutationFn: ({ id, payload }) => (id ? zoneApi.update(id, payload) : zoneApi.create(payload)),
    onSuccess: () => {
      toast.success(t('تم حفظ المنطقة ✅', 'Zone saved ✅'));
      resetDraw();
      invalidate();
    },
    onError: (e) =>
      toast.error(e?.response?.data?.message || t('فشل الحفظ', 'Save failed')),
  });

  const removeZone = useMutation({
    mutationFn: (id) => zoneApi.delete(id),
    onSuccess: () => { toast.success(t('تم الحذف', 'Deleted')); invalidate(); },
  });

  const toggleZone = useMutation({
    mutationFn: ({ id, is_active }) => zoneApi.update(id, { is_active }),
    onSuccess: invalidate,
  });

  const fromRadius = useMutation({
    mutationFn: () => zoneApi.fromRadius(branchId),
    onSuccess: () => {
      toast.success(t('تم إنشاء منطقة من نطاق الكيلومترات', 'Zone created from the radius'));
      invalidate();
    },
  });

  const resetDraw = () => {
    setDrawing(false);
    setDraft([]);
    setEditingId(null);
    setName('');
  };

  const startNew = () => {
    setDraft([]);
    setEditingId(null);
    setName('');
    setDrawing(true);
  };

  const startEdit = (zone) => {
    setDraft(toLatLngs(zone.geometry));
    setEditingId(zone.id);
    setName(zone.name_ar || '');
    setDrawing(true);
  };

  const moveVertex = (index, latlng) => {
    setDraft((points) => points.map((p, i) => (i === index ? [latlng.lat, latlng.lng] : p)));
  };

  const submit = () => {
    if (draft.length < 3) {
      toast.error(t('ارسم 3 نقاط على الأقل', 'Draw at least 3 points'));
      return;
    }
    if (!name.trim()) {
      toast.error(t('اكتب اسم المنطقة', 'Name the zone'));
      return;
    }
    saveZone.mutate({
      id: editingId,
      payload: {
        branch: Number(branchId),
        name_ar: name.trim(),
        name_en: name.trim(),
        geometry: toGeoJSON(draft),
      },
    });
  };

  const hasZones = zones.some((z) => z.is_active);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-bold text-[#0D2440]">
            🗺️ {t('مناطق التوصيل', 'Delivery Zones')}
          </h1>
          <p className="text-xs text-gray-500 mt-1">
            {hasZones
              ? t('المناطق المرسومة تحل محل نطاق الكيلومترات لهذا الفرع.',
                  'Drawn zones replace the km radius for this branch.')
              : t('لا توجد مناطق — الفرع يستخدم نطاق الكيلومترات الحالي.',
                  'No zones yet — this branch still uses its km radius.')}
          </p>
        </div>

        <div className="flex gap-2 flex-wrap">
          <select
            value={branchId || ''}
            onChange={(e) => { setBranchId(Number(e.target.value)); resetDraw(); }}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm"
          >
            {branches.map((b) => (
              <option key={b.id} value={b.id}>{lang === 'ar' ? b.name_ar : (b.name_en || b.name)}</option>
            ))}
          </select>

          {!drawing && (
            <>
              <button onClick={startNew}
                className="bg-[#2FBE8F] hover:bg-emerald-600 text-white px-4 py-2 rounded-xl text-sm font-bold">
                ✏️ {t('ارسم منطقة', 'Draw a zone')}
              </button>
              <button onClick={() => fromRadius.mutate()} disabled={fromRadius.isPending}
                className="border border-gray-200 hover:bg-gray-50 text-[#2E5E99] px-4 py-2 rounded-xl text-sm font-semibold disabled:opacity-40">
                ⭕ {t('حوّل النطاق الحالي لمنطقة', 'Convert current radius')}
              </button>
            </>
          )}
        </div>
      </div>

      {drawing && (
        <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-4 flex items-center gap-3 flex-wrap">
          <span className="text-sm text-emerald-900 font-semibold">
            {t('اضغط على الخريطة لإضافة نقاط. اسحب أي نقطة لتعديلها.',
               'Click the map to add points. Drag a point to adjust it.')}
          </span>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t('اسم المنطقة', 'Zone name')}
            className="border border-emerald-200 rounded-xl px-3 py-1.5 text-sm flex-1 min-w-[160px]"
          />
          <span className="text-xs text-emerald-700">{draft.length} {t('نقطة', 'points')}</span>
          <button onClick={() => setDraft((p) => p.slice(0, -1))} disabled={!draft.length}
            className="text-sm px-3 py-1.5 rounded-xl border border-emerald-200 disabled:opacity-40">
            ↩️ {t('تراجع', 'Undo')}
          </button>
          <button onClick={submit} disabled={saveZone.isPending}
            className="bg-[#2FBE8F] hover:bg-emerald-600 text-white px-4 py-1.5 rounded-xl text-sm font-bold disabled:opacity-40">
            ✅ {t('حفظ', 'Save')}
          </button>
          <button onClick={resetDraw}
            className="text-sm px-3 py-1.5 rounded-xl text-gray-500 hover:bg-white">
            {t('إلغاء', 'Cancel')}
          </button>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-4">
        <div className="lg:col-span-3 rounded-2xl overflow-hidden border border-gray-100" style={{ height: '65vh' }}>
          <MapContainer center={center} zoom={12} style={{ height: '100%', width: '100%' }}>
            <TileLayer
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              attribution="&copy; OpenStreetMap"
            />
            <Recenter center={center} />
            <ClickCatcher active={drawing} onClick={(p) => setDraft((d) => [...d, p])} />

            {branch && (
              <>
                <Marker position={center} icon={branchIcon} />
                {/* The radius still in force when no zone covers this branch. */}
                {!hasZones && (
                  <Circle
                    center={center}
                    radius={Number(branch.delivery_radius_km || 0) * 1000}
                    pathOptions={{ color: '#94a3b8', dashArray: '6', fillOpacity: 0.05 }}
                  />
                )}
              </>
            )}

            {zones.filter((z) => z.id !== editingId).map((zone) => (
              <Polygon
                key={zone.id}
                positions={toLatLngs(zone.geometry)}
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
                eventHandlers={{ dragend: (e) => moveVertex(i, e.target.getLatLng()) }}
              />
            ))}
          </MapContainer>
        </div>

        <div className="space-y-2">
          <div className="text-sm font-bold text-[#0D2440]">
            {t('المناطق', 'Zones')} ({zones.length})
          </div>
          {zones.length === 0 && (
            <div className="text-xs text-gray-400 border border-dashed border-gray-200 rounded-xl p-4 text-center">
              {t('لا توجد مناطق لهذا الفرع', 'No zones for this branch')}
            </div>
          )}
          {zones.map((zone) => (
            <div key={zone.id} className="border border-gray-100 rounded-xl px-3 py-2.5 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span className={`font-semibold ${zone.is_active ? 'text-[#0D2440]' : 'text-gray-400 line-through'}`}>
                  {zone.name_ar}
                </span>
                <span className="text-[10px] text-gray-400">
                  {zone.source === 'circle' ? t('من النطاق', 'from radius') : t('مرسومة', 'drawn')}
                </span>
              </div>
              <div className="flex gap-3 mt-1.5 text-xs">
                <button onClick={() => startEdit(zone)} className="text-[#2E5E99] font-semibold">
                  {t('تعديل', 'Edit')}
                </button>
                <button
                  onClick={() => toggleZone.mutate({ id: zone.id, is_active: !zone.is_active })}
                  className="text-amber-600 font-semibold">
                  {zone.is_active ? t('إيقاف', 'Disable') : t('تفعيل', 'Enable')}
                </button>
                <button
                  onClick={() => window.confirm(t('حذف هذه المنطقة؟', 'Delete this zone?')) && removeZone.mutate(zone.id)}
                  className="text-red-500 font-semibold">
                  {t('حذف', 'Delete')}
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
