import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { branchApi } from '../services/api';
import toast from 'react-hot-toast';
import { apiError } from '../utils/apiError';

const EMPTY = { name: '', name_ar: '', address: '', phone: '', latitude: '', longitude: '', delivery_radius_km: '10', delivery_fee: '15', opening_time: '08:00', closing_time: '00:00' };

// Keys are Python weekdays — Monday is 0 — matching what the backend stores.
const DAYS = [
  ['0', 'الاثنين', 'Mon'], ['1', 'الثلاثاء', 'Tue'], ['2', 'الأربعاء', 'Wed'],
  ['3', 'الخميس', 'Thu'], ['4', 'الجمعة', 'Fri'], ['5', 'السبت', 'Sat'],
  ['6', 'الأحد', 'Sun'],
];

const BLANK_SCHEDULE = Object.fromEntries(
  DAYS.map(([key]) => [key, { open: '09:00', close: '23:00', closed: false }]),
);

export default function BranchesPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [schedule, setSchedule] = useState(BLANK_SCHEDULE);

  const { data, isLoading } = useQuery({ queryKey: ['branches'], queryFn: () => branchApi.list().then(r => r.data) });
  const saveMutation = useMutation({
    // operating_hours carries the whole week; the server keeps reading the
    // legacy opening_time/closing_time pair for branches that have none.
    mutationFn: (d) => {
      const payload = { ...d, operating_hours: { schedule } };
      return editing ? branchApi.update(editing.id, payload) : branchApi.create(payload);
    },
    onSuccess: () => { qc.invalidateQueries(['branches']); setShowForm(false); setEditing(null); setForm(EMPTY); setSchedule(BLANK_SCHEDULE); toast.success(t('تم الحفظ','Saved')); },
    onError: (e) => toast.error(apiError(e, t('فشل الحفظ','Save failed'))),
  });
  const deleteMutation = useMutation({
    mutationFn: (id) => branchApi.delete(id),
    onSuccess: () => { qc.invalidateQueries(['branches']); toast.success(t('تم الحذف','Deleted')); },
  });

  const branches = Array.isArray(data) ? data : (data?.results || []);
  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none';

  const openEdit = (b) => {
    setEditing(b);
    setForm({ name:b.name, name_ar:b.name_ar, address:b.address, phone:b.phone, latitude:b.latitude, longitude:b.longitude, delivery_radius_km:b.delivery_radius_km, delivery_fee:b.delivery_fee, opening_time:b.opening_time, closing_time:b.closing_time });
    // The serializer normalises legacy hours into `schedule`, so a branch that
    // predates per-day hours opens with its real times already filled in.
    setSchedule({ ...BLANK_SCHEDULE, ...(b.schedule || {}) });
    setShowForm(true);
  };

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('الفروع','Branches')}</h1>
        <button onClick={() => { setEditing(null); setForm(EMPTY); setSchedule(BLANK_SCHEDULE); setShowForm(true); }} className="bg-[#2E5E99] text-white px-5 py-2.5 rounded-xl font-semibold text-sm">+ {t('إضافة فرع','Add Branch')}</button>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {isLoading ? Array(2).fill(0).map((_, i) => <div key={i} className="bg-white rounded-2xl h-40 animate-pulse border border-gray-100" />) :
          branches.map(b => (
          <div key={b.id} className="bg-white rounded-2xl p-5 border border-gray-100 shadow-sm">
            <div className="flex items-start justify-between mb-3">
              <div><div className="font-bold text-[#0D2440] text-lg">{lang === 'ar' ? b.name_ar : b.name}</div><div className="text-sm text-gray-500">{b.address}</div></div>
              <div className="flex flex-col items-end gap-1">
                <span className={`text-xs font-semibold px-2 py-1 rounded-full ${b.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{b.is_active ? t('نشط','Active') : t('موقوف','Inactive')}</span>
                {/* What the customer's checkout is being judged against right now. */}
                {b.is_open_now !== undefined && (
                  <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${b.is_open_now ? 'bg-[#ECFDF5] text-[#2FBE8F]' : 'bg-red-50 text-red-500'}`}>
                    {b.is_open_now ? t('مفتوح الآن','Open now') : t('مغلق الآن','Closed now')}
                  </span>
                )}
              </div>
            </div>
            <div className="grid grid-cols-3 gap-2 text-center mb-4">
              <div className="bg-[#E7F0FA] rounded-xl p-2"><div className="font-bold text-[#2E5E99] text-sm">{b.delivery_fee} EGP</div><div className="text-xs text-gray-500">{t('رسوم التوصيل','Delivery Fee')}</div></div>
              <div className="bg-[#ECFDF5] rounded-xl p-2"><div className="font-bold text-[#2FBE8F] text-sm">{b.delivery_radius_km} km</div><div className="text-xs text-gray-500">{t('نطاق التوصيل','Radius')}</div></div>
              <div className="bg-[#FFF7ED] rounded-xl p-2"><div className="font-bold text-[#F97316] text-sm">{b.opening_time}–{b.closing_time}</div><div className="text-xs text-gray-500">{t('ساعات العمل','Hours')}</div></div>
            </div>
            <div className="flex gap-2">
              <button onClick={() => openEdit(b)} className="flex-1 text-[#2E5E99] bg-[#E7F0FA] hover:bg-[#dbeafe] rounded-xl py-2 text-xs font-semibold transition-colors">{t('تعديل','Edit')}</button>
              <button onClick={() => { if(confirm(t('حذف الفرع؟','Delete branch?'))) deleteMutation.mutate(b.id); }} className="flex-1 text-red-500 bg-red-50 hover:bg-red-100 rounded-xl py-2 text-xs font-semibold transition-colors">{t('حذف','Delete')}</button>
            </div>
          </div>
        ))}
      </div>
      {showForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-md shadow-xl max-h-[90vh] overflow-y-auto">
            <h3 className="font-bold text-[#0D2440] text-lg font-serif mb-4">{editing ? t('تعديل فرع','Edit Branch') : t('إضافة فرع','Add Branch')}</h3>
            <div className="space-y-3">
              {[['name','الاسم (إنجليزي)','Branch Name','ltr'],['name_ar','الاسم (عربي)','اسم الفرع','rtl'],['address','العنوان','Address','rtl'],['phone','الهاتف','Phone','ltr']].map(([k,ar,ph,dir]) => (
                <div key={k}><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t(ar,ph)}</label>
                  <input value={form[k]} onChange={e => setForm(f => ({...f,[k]:e.target.value}))} className={inp} placeholder={ph} dir={dir} /></div>
              ))}
              <div className="grid grid-cols-2 gap-3">
                {[['latitude','خط العرض','Latitude'],['longitude','خط الطول','Longitude'],['delivery_radius_km','نطاق التوصيل (km)','Delivery Radius'],['delivery_fee','رسوم التوصيل (EGP)','Delivery Fee'],['opening_time','وقت الفتح','Opening'],['closing_time','وقت الإغلاق','Closing']].map(([k,ar,en]) => (
                  <div key={k}><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t(ar,en)}</label>
                    <input value={form[k]} onChange={e => setForm(f => ({...f,[k]:e.target.value}))} className={inp} type={k.includes('time') ? 'time' : 'text'} /></div>
                ))}
              </div>

              {/* Per-day hours. The two time boxes above are the legacy pair the
                  backend still reads when no schedule is set; these seven rows
                  are what actually gates checkout. */}
              <div className="border-t border-gray-100 pt-3">
                <div className="text-xs font-bold text-[#0D2440] mb-2">
                  {t('مواعيد العمل — لكل يوم','Working hours — per day')}
                </div>
                <div className="space-y-1.5">
                  {DAYS.map(([key, ar, en]) => {
                    const day = schedule[key] || { open:'', close:'', closed:false };
                    const set = (patch) => setSchedule(s => ({ ...s, [key]: { ...day, ...patch } }));
                    return (
                      <div key={key} className="flex items-center gap-2">
                        <span className="w-16 text-xs font-semibold text-[#0D2440]">{t(ar,en)}</span>
                        <input type="time" value={day.open || ''} disabled={day.closed}
                               onChange={e => set({ open: e.target.value })}
                               className="border border-gray-200 rounded-lg px-2 py-1 text-xs disabled:opacity-40" />
                        <span className="text-xs text-gray-400">-</span>
                        <input type="time" value={day.close || ''} disabled={day.closed}
                               onChange={e => set({ close: e.target.value })}
                               className="border border-gray-200 rounded-lg px-2 py-1 text-xs disabled:opacity-40" />
                        <label className="flex items-center gap-1 text-xs text-gray-500 cursor-pointer ms-auto">
                          <input type="checkbox" checked={!!day.closed}
                                 onChange={e => set({ closed: e.target.checked })}
                                 className="w-3.5 h-3.5 accent-[#2E5E99]" />
                          {t('مغلق','Closed')}
                        </label>
                      </div>
                    );
                  })}
                </div>
                <button
                  onClick={() => {
                    const first = schedule['0'] || {};
                    setSchedule(Object.fromEntries(DAYS.map(([k]) => [k, { ...first }])));
                  }}
                  className="text-xs text-[#2E5E99] font-semibold mt-2"
                >
                  {t('طبّق مواعيد الاثنين على كل الأيام','Copy Monday to every day')}
                </button>
              </div>
            </div>
            <div className="flex gap-3 mt-5">
              <button onClick={() => setShowForm(false)} className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-semibold">{t('إلغاء','Cancel')}</button>
              <button onClick={() => saveMutation.mutate(form)} disabled={saveMutation.isPending || !form.name}
                className="flex-1 bg-[#2E5E99] text-white rounded-xl py-2.5 text-sm font-bold disabled:opacity-40">
                {saveMutation.isPending ? '...' : t('حفظ','Save')}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
