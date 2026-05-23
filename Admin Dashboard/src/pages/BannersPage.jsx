import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { bannerApi } from '../services/api';
import toast from 'react-hot-toast';

const POSITIONS = [['home_main','البانر الرئيسي','Home Main'],['home_secondary','البانر الثانوي','Secondary'],['category','بانر قسم','Category'],['popup','نافذة منبثقة','Popup']];
const EMPTY = { title_ar:'', title_en:'', subtitle_ar:'', subtitle_en:'', position:'home_main', link_type:'none', sort_order:'0', is_active:true, start_date:'', end_date:'' };

export default function BannersPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [imageFile, setImageFile] = useState(null);

  const { data, isLoading } = useQuery({ queryKey: ['admin-banners'], queryFn: () => bannerApi.list().then(r => r.data) });
  const saveMutation = useMutation({
    mutationFn: (d) => { const fd = new FormData(); Object.entries(d).forEach(([k,v]) => { if(v!==null && v!==undefined && v!=='') fd.append(k,v); }); if(imageFile) fd.append('image', imageFile); return editing ? bannerApi.update(editing.id, fd) : bannerApi.create(fd); },
    onSuccess: () => { qc.invalidateQueries(['admin-banners']); setShowForm(false); setEditing(null); setForm(EMPTY); setImageFile(null); toast.success(t('تم الحفظ','Saved')); },
  });
  const deleteMutation = useMutation({ mutationFn: (id) => bannerApi.delete(id), onSuccess: () => { qc.invalidateQueries(['admin-banners']); toast.success(t('تم الحذف','Deleted')); } });

  const banners = Array.isArray(data) ? data : (data?.results || []);
  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none';

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('الإعلانات','Banners')}</h1>
        <button onClick={() => { setEditing(null); setForm(EMPTY); setImageFile(null); setShowForm(true); }} className="bg-[#2E5E99] text-white px-5 py-2.5 rounded-xl font-semibold text-sm">+ {t('إضافة إعلان','Add Banner')}</button>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {isLoading ? Array(4).fill(0).map((_, i) => <div key={i} className="bg-white rounded-2xl h-36 animate-pulse border border-gray-100" />) :
          banners.map(b => (
          <div key={b.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            {b.image_url && <div className="h-28 bg-[#E7F0FA] overflow-hidden"><img src={b.image_url} alt="" className="w-full h-full object-cover" /></div>}
            {!b.image_url && <div className="h-28 bg-gradient-to-br from-[#0D2440] to-[#2E5E99] flex items-center justify-center"><div><div className="text-white font-bold text-lg text-center">{b.title_ar}</div><div className="text-[#7BA4D0] text-xs text-center">{b.subtitle_ar}</div></div></div>}
            <div className="p-4 flex items-center justify-between">
              <div><div className="font-semibold text-[#0D2440] text-sm">{lang === 'ar' ? b.title_ar : b.title_en}</div>
                <div className="flex gap-2 mt-1">
                  <span className="text-xs bg-[#E7F0FA] text-[#2E5E99] px-2 py-0.5 rounded-full font-semibold">{b.position}</span>
                  <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${b.is_currently_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{b.is_currently_active ? t('نشط','Active') : t('موقوف','Inactive')}</span>
                </div>
                <div className="text-xs text-gray-400 mt-1">👁 {b.view_count} · 🖱 {b.click_count} · CTR: {b.ctr}%</div>
              </div>
              <div className="flex gap-1">
                <button onClick={() => { setEditing(b); setForm({ title_ar:b.title_ar, title_en:b.title_en, subtitle_ar:b.subtitle_ar||'', subtitle_en:b.subtitle_en||'', position:b.position, link_type:b.link_type, sort_order:String(b.sort_order), is_active:b.is_active, start_date:b.start_date?b.start_date.slice(0,16):'', end_date:b.end_date?b.end_date.slice(0,16):'' }); setShowForm(true); }} className="text-[#2E5E99] hover:bg-[#E7F0FA] px-3 py-1.5 rounded-lg text-xs font-semibold">{t('تعديل','Edit')}</button>
                <button onClick={() => { if(confirm(t('حذف الإعلان؟','Delete banner?'))) deleteMutation.mutate(b.id); }} className="text-red-500 hover:bg-red-50 px-3 py-1.5 rounded-lg text-xs font-semibold">{t('حذف','Delete')}</button>
              </div>
            </div>
          </div>
        ))}
      </div>
      {showForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-lg shadow-xl max-h-[90vh] overflow-y-auto">
            <h3 className="font-bold text-[#0D2440] text-lg font-serif mb-4">{editing ? t('تعديل إعلان','Edit Banner') : t('إضافة إعلان','Add Banner')}</h3>
            <div className="space-y-3">
              <div><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('رفع صورة','Upload Image')}</label>
                <label className="cursor-pointer flex items-center gap-3 border-2 border-dashed border-[#7BA4D0] rounded-xl p-4 hover:border-[#2E5E99] transition-colors">
                  <span className="text-2xl">🖼️</span>
                  <span className="text-sm text-gray-500">{imageFile ? imageFile.name : t('اختر صورة الإعلان','Choose banner image')}</span>
                  <input type="file" accept="image/*" className="hidden" onChange={e => setImageFile(e.target.files?.[0])} />
                </label>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('العنوان عربي','Title Arabic')}</label><input value={form.title_ar} onChange={e => setForm(f => ({...f,title_ar:e.target.value}))} className={inp} dir="rtl" /></div>
                <div><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('العنوان إنجليزي','Title English')}</label><input value={form.title_en} onChange={e => setForm(f => ({...f,title_en:e.target.value}))} className={inp} dir="ltr" /></div>
              </div>
              <div><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('الموقع','Position')}</label>
                <select value={form.position} onChange={e => setForm(f => ({...f,position:e.target.value}))} className={inp}>
                  {POSITIONS.map(([v,ar,en]) => <option key={v} value={v}>{lang==='ar'?ar:en}</option>)}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('تاريخ البداية','Start Date')}</label><input type="datetime-local" value={form.start_date} onChange={e => setForm(f => ({...f,start_date:e.target.value}))} className={inp} /></div>
                <div><label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('تاريخ النهاية','End Date')}</label><input type="datetime-local" value={form.end_date} onChange={e => setForm(f => ({...f,end_date:e.target.value}))} className={inp} /></div>
              </div>
              <label className="flex items-center gap-3 cursor-pointer">
                <button type="button" onClick={() => setForm(f => ({...f,is_active:!f.is_active}))} className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${form.is_active ? 'bg-[#2FBE8F]' : 'bg-gray-200'}`}>
                  <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${form.is_active ? 'translate-x-6' : 'translate-x-1'}`} />
                </button>
                <span className="text-sm font-medium text-[#0D2440]">{t('إعلان نشط','Active Banner')}</span>
              </label>
            </div>
            <div className="flex gap-3 mt-5">
              <button onClick={() => setShowForm(false)} className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-semibold">{t('إلغاء','Cancel')}</button>
              <button onClick={() => saveMutation.mutate(form)} disabled={saveMutation.isPending || !form.title_ar}
                className="flex-1 bg-[#2E5E99] text-white rounded-xl py-2.5 text-sm font-bold disabled:opacity-40">
                {saveMutation.isPending ? '...' : t('حفظ','Save')}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
