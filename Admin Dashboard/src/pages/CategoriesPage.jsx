import React, { useState, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { categoryApi } from '../services/api';
import toast from 'react-hot-toast';

export default function CategoriesPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ name_ar: '', name_en: '', icon: '', sort_order: '0' });
  const [imageFile, setImageFile] = useState(null);
  const [imagePreview, setImagePreview] = useState('');
  const fileRef = useRef();

  const { data, isLoading } = useQuery({ queryKey: ['admin-categories'], queryFn: () => categoryApi.list().then(r => r.data) });

  const saveMutation = useMutation({
    mutationFn: (d) => {
      const payload = { ...d };
      if (imageFile) payload.image = imageFile;
      return editing ? categoryApi.update(editing.id, payload) : categoryApi.create(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries(['admin-categories']);
      setShowForm(false);
      setEditing(null);
      setForm({ name_ar: '', name_en: '', icon: '', sort_order: '0' });
      setImageFile(null);
      setImagePreview('');
      toast.success(t('تم الحفظ', 'Saved'));
    },
    onError: (e) => toast.error(e?.response?.data?.message || t('حدث خطأ', 'Error')),
  });

  const deleteMutation = useMutation({
    mutationFn: (id) => categoryApi.delete(id),
    onSuccess: () => { qc.invalidateQueries(['admin-categories']); toast.success(t('تم الحذف', 'Deleted')); },
  });

  const cats = Array.isArray(data) ? data : (data?.results || []);
  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none';

  const openEdit = (cat) => {
    setEditing(cat);
    setForm({ name_ar: cat.name_ar, name_en: cat.name_en, icon: cat.icon || '', sort_order: String(cat.sort_order) });
    setImageFile(null);
    setImagePreview(cat.image_url || '');
    setShowForm(true);
  };

  const openAdd = () => {
    setEditing(null);
    setForm({ name_ar: '', name_en: '', icon: '', sort_order: '0' });
    setImageFile(null);
    setImagePreview('');
    setShowForm(true);
  };

  const handleImageChange = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setImagePreview(URL.createObjectURL(file));
    e.target.value = '';
  };

  const catIcon = (cat) => {
    if (cat.image_url) return <img src={cat.image_url} alt="" className="w-full h-full object-cover rounded-xl" />;
    if (cat.icon) return <span className="text-2xl">{cat.icon}</span>;
    return <span className="text-2xl">🛍️</span>;
  };

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('الأقسام', 'Categories')}</h1>
        <button onClick={openAdd} className="bg-[#2E5E99] text-white px-5 py-2.5 rounded-xl font-semibold text-sm">
          + {t('إضافة قسم', 'Add Category')}
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {isLoading ? Array(6).fill(0).map((_, i) => <div key={i} className="bg-white rounded-2xl h-24 animate-pulse border border-gray-100" />) :
          cats.map(cat => (
            <div key={cat.id} className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm flex items-center gap-3">
              <div className="w-12 h-12 bg-[#E7F0FA] rounded-xl flex items-center justify-center flex-shrink-0 overflow-hidden">
                {catIcon(cat)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="font-bold text-[#0D2440]">{lang === 'ar' ? cat.name_ar : cat.name_en}</div>
                <div className="text-xs text-gray-400">{cat.product_count || 0} {t('منتج', 'products')}</div>
              </div>
              <div className="flex gap-1">
                <button onClick={() => openEdit(cat)} className="text-[#2E5E99] hover:bg-[#E7F0FA] px-3 py-1.5 rounded-lg text-xs font-semibold">{t('تعديل', 'Edit')}</button>
                <button onClick={() => { if (confirm(t('حذف القسم؟', 'Delete?'))) deleteMutation.mutate(cat.id); }} className="text-red-500 hover:bg-red-50 px-3 py-1.5 rounded-lg text-xs font-semibold">{t('حذف', 'Delete')}</button>
              </div>
            </div>
          ))}
      </div>

      {showForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl">
            <h3 className="font-bold text-[#0D2440] text-lg font-serif mb-4">
              {editing ? t('تعديل قسم', 'Edit Category') : t('إضافة قسم', 'Add Category')}
            </h3>
            <div className="space-y-3">
              {/* Image upload */}
              <div>
                <label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('صورة القسم', 'Category Image')}</label>
                <div className="flex items-center gap-3">
                  <div
                    onClick={() => fileRef.current?.click()}
                    className="w-16 h-16 rounded-xl border-2 border-dashed border-gray-200 flex items-center justify-center cursor-pointer hover:border-[#2E5E99] overflow-hidden flex-shrink-0 bg-gray-50"
                  >
                    {imagePreview
                      ? <img src={imagePreview} alt="" className="w-full h-full object-cover" />
                      : <span className="text-2xl">{form.icon || '🖼️'}</span>
                    }
                  </div>
                  <div className="flex-1">
                    <button onClick={() => fileRef.current?.click()} className="text-[#2E5E99] text-xs font-semibold border border-[#2E5E99] rounded-lg px-3 py-1.5">
                      {t('اختر صورة', 'Choose Image')}
                    </button>
                    {imagePreview && (
                      <button onClick={() => { setImageFile(null); setImagePreview(''); }} className="text-red-400 text-xs ml-2">
                        {t('إزالة', 'Remove')}
                      </button>
                    )}
                    <p className="text-[10px] text-gray-400 mt-1">{t('PNG, JPG, WebP', 'PNG, JPG, WebP')}</p>
                  </div>
                </div>
                <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={handleImageChange} />
              </div>

              {/* Emoji icon (optional fallback) */}
              <div>
                <label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('أيقون (إيموجي)', 'Icon (Emoji)')}</label>
                <input value={form.icon} onChange={e => setForm(f => ({ ...f, icon: e.target.value }))} className={inp} placeholder="🛍️" />
              </div>

              <div>
                <label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('الاسم عربي', 'Name Arabic')}</label>
                <input value={form.name_ar} onChange={e => setForm(f => ({ ...f, name_ar: e.target.value }))} className={inp} placeholder="خضروات" dir="rtl" />
              </div>
              <div>
                <label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('الاسم إنجليزي', 'Name English')}</label>
                <input value={form.name_en} onChange={e => setForm(f => ({ ...f, name_en: e.target.value }))} className={inp} placeholder="Vegetables" dir="ltr" />
              </div>
              <div>
                <label className="text-xs font-semibold text-gray-500 uppercase mb-1 block">{t('الترتيب', 'Sort Order')}</label>
                <input type="number" value={form.sort_order} onChange={e => setForm(f => ({ ...f, sort_order: e.target.value }))} className={inp} />
              </div>
            </div>

            <div className="flex gap-3 mt-5">
              <button onClick={() => setShowForm(false)} className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-semibold">{t('إلغاء', 'Cancel')}</button>
              <button onClick={() => saveMutation.mutate(form)} disabled={saveMutation.isPending || !form.name_ar}
                className="flex-1 bg-[#2E5E99] text-white rounded-xl py-2.5 text-sm font-bold disabled:opacity-40">
                {saveMutation.isPending ? '...' : t('حفظ', 'Save')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
