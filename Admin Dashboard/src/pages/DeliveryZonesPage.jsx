import React, { useEffect, useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import toast from 'react-hot-toast';
import { branchApi, zoneApi } from '../services/api';
import ZoneMapGoogle from '../components/shared/ZoneMapGoogle';
import ZoneMapLeaflet from '../components/shared/ZoneMapLeaflet';

/**
 * Delivery zones — draw the area a branch delivers to, instead of a radius.
 *
 * The map opens on the selected branch at street zoom: a zone is always drawn
 * around the market itself, so the nearby streets are what you need to see
 * first. Switching branch re-centres.
 *
 * Google Maps is used when VITE_GOOGLE_MAPS_API_KEY is set, OpenStreetMap
 * otherwise — the page must stay usable when the key is missing rather than
 * showing a blank panel.
 */

const unwrap = (res) => (res?.data?.success !== undefined ? res.data.data : res?.data);

const MAPS_KEY = import.meta.env.VITE_GOOGLE_MAPS_API_KEY || '';

// Only until a branch loads — never a fallback the admin actually draws on.
const CAIRO = [30.0444, 31.2357];
const STREET_ZOOM = 14;

const toGeoJSON = (latlngs) => {
  const ring = latlngs.map(([lat, lng]) => [lng, lat]);   // GeoJSON is [lng, lat]
  if (ring.length) ring.push(ring[0]);                     // rings must close
  return { type: 'Polygon', coordinates: [ring] };
};

const toLatLngs = (geometry) =>
  (geometry?.coordinates?.[0] || []).slice(0, -1).map(([lng, lat]) => [lat, lng]);

export default function DeliveryZonesPage() {
  const { lang } = useOutletContext() || { lang: 'ar' };
  const t = (ar, en) => (lang === 'ar' ? ar : en);
  const qc = useQueryClient();

  const [branchId, setBranchId] = useState(null);
  const [drawing, setDrawing] = useState(false);
  const [draft, setDraft] = useState([]);            // [[lat, lng], ...]
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

  const center = branch && branch.latitude != null
    ? [Number(branch.latitude), Number(branch.longitude)]
    : CAIRO;

  const invalidate = () => qc.invalidateQueries({ queryKey: ['delivery-zones', branchId] });

  const resetDraw = () => { setDrawing(false); setDraft([]); setEditingId(null); setName(''); };

  const saveZone = useMutation({
    mutationFn: ({ id, payload }) => (id ? zoneApi.update(id, payload) : zoneApi.create(payload)),
    onSuccess: () => { toast.success(t('تم حفظ المنطقة ✅', 'Zone saved ✅')); resetDraw(); invalidate(); },
    onError: (e) => toast.error(e?.response?.data?.message || t('فشل الحفظ', 'Save failed')),
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
    onSuccess: () => { toast.success(t('تم إنشاء المنطقة', 'Zone created')); invalidate(); },
    onError: (e) => toast.error(e?.response?.data?.message || t('فشل', 'Failed')),
  });

  const startNew = () => { setDraft([]); setEditingId(null); setName(''); setDrawing(true); };

  const startEdit = (zone) => {
    setDraft(toLatLngs(zone.geometry));
    setEditingId(zone.id);
    setName(zone.name_ar || '');
    setDrawing(true);
  };

  const moveVertex = (index, { lat, lng }) =>
    setDraft((points) => points.map((p, i) => (i === index ? [lat, lng] : p)));

  const submit = () => {
    if (draft.length < 3) return toast.error(t('ارسم 3 نقاط على الأقل', 'Draw at least 3 points'));
    if (!name.trim()) return toast.error(t('اكتب اسم المنطقة', 'Name the zone'));
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
  const radiusKm = Number(branch?.delivery_radius_km || 0);
  // A very large radius drawn as a circle swamps the map and helps nobody.
  const showRadius = !hasZones && radiusKm > 0 && radiusKm <= 50;

  const MapImpl = MAPS_KEY ? ZoneMapGoogle : ZoneMapLeaflet;
  const mapProps = {
    apiKey: MAPS_KEY,
    center,
    zoom: STREET_ZOOM,
    branch,
    zones,
    draft,
    drawing,
    editingId,
    showRadius,
    radiusKm,
    onMapClick: (point) => setDraft((d) => [...d, point]),
    onVertexMove: moveVertex,
  };

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
              <option key={b.id} value={b.id}>
                {lang === 'ar' ? b.name_ar : (b.name_en || b.name)}
              </option>
            ))}
          </select>

          {!drawing && (
            <>
              <button onClick={startNew}
                className="bg-[#2FBE8F] hover:bg-emerald-600 text-white px-4 py-2 rounded-xl text-sm font-bold">
                ✏️ {t('ارسم منطقة', 'Draw a zone')}
              </button>
              {radiusKm > 0 && radiusKm <= 50 && (
                <button onClick={() => fromRadius.mutate()} disabled={fromRadius.isPending}
                  className="border border-gray-200 hover:bg-gray-50 text-[#2E5E99] px-4 py-2 rounded-xl text-sm font-semibold disabled:opacity-40">
                  ⭕ {t('حوّل النطاق الحالي', 'Convert current radius')}
                </button>
              )}
            </>
          )}
        </div>
      </div>

      {!MAPS_KEY && (
        <div className="text-xs bg-amber-50 border border-amber-200 text-amber-800 rounded-xl px-3 py-2">
          {t('خرائط Google غير مفعّلة — أضف VITE_GOOGLE_MAPS_API_KEY لاستخدامها. الخريطة الحالية OpenStreetMap.',
             'Google Maps is not configured — set VITE_GOOGLE_MAPS_API_KEY to enable it. Showing OpenStreetMap.')}
        </div>
      )}

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
          <button onClick={resetDraw} className="text-sm px-3 py-1.5 rounded-xl text-gray-500 hover:bg-white">
            {t('إلغاء', 'Cancel')}
          </button>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-4">
        <div className="lg:col-span-3 rounded-2xl overflow-hidden border border-gray-100" style={{ height: '65vh' }}>
          <MapImpl {...mapProps} />
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
