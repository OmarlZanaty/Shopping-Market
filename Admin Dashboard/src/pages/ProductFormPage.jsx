import React, { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext, useNavigate, useParams } from 'react-router-dom';
import { productApi, categoryApi } from '../services/api';
import toast from 'react-hot-toast';

const SELL_UNITS = [
  { value: 'piece', ar: 'قطعة', en: 'Piece' },
  { value: 'kg', ar: 'كيلو', en: 'Kilogram' },
  { value: 'gram', ar: 'جرام', en: 'Gram' },
  { value: 'box', ar: 'علبة', en: 'Box' },
  { value: 'carton', ar: 'كرتونة', en: 'Carton' },
  { value: 'liter', ar: 'لتر', en: 'Liter' },
  { value: 'pack', ar: 'باكت', en: 'Pack' },
];

export default function ProductFormPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const navigate = useNavigate();
  const { id } = useParams();
  const isEdit = !!id;
  const qc = useQueryClient();
  const [activeTab, setActiveTab] = useState('basic');
  const [imageFile, setImageFile] = useState(null);
  const [imagePreview, setImagePreview] = useState('');
  const [form, setForm] = useState({
    name_ar: '', name_en: '', description_ar: '', description_en: '',
    barcode: '', original_price: '', discount_price: '', discount_start: '', discount_end: '',
    quantity_in_stock: '', low_stock_threshold: '5', sell_unit: 'piece',
    min_order_quantity: '1', max_order_quantity: '', is_available: true, is_featured: false,
    category_ids: [], alternative_ids: [], related_ids: [],
  });

  const { data: categoriesData } = useQuery({ queryKey: ['admin-categories'], queryFn: () => categoryApi.list().then(r => r.data) });
  const { data: productData } = useQuery({ queryKey: ['product-edit', id], queryFn: () => productApi.get(id).then(r => r.data), enabled: isEdit });

  useEffect(() => {
    if (productData && isEdit) {
      setForm({
        name_ar: productData.name_ar || '', name_en: productData.name_en || '',
        description_ar: productData.description_ar || '', description_en: productData.description_en || '',
        barcode: productData.barcode || '', original_price: productData.original_price || '',
        discount_price: productData.discount_price || '',
        discount_start: productData.discount_start ? productData.discount_start.slice(0,16) : '',
        discount_end: productData.discount_end ? productData.discount_end.slice(0,16) : '',
        quantity_in_stock: productData.quantity_in_stock || '', low_stock_threshold: productData.low_stock_threshold || '5',
        sell_unit: productData.sell_unit || 'piece', min_order_quantity: productData.min_order_quantity || '1',
        max_order_quantity: productData.max_order_quantity || '', is_available: productData.is_available ?? true,
        is_featured: productData.is_featured ?? false,
        category_ids: (productData.categories || []).map(c => c.id),
        alternative_ids: (productData.alternatives || []).map(p => p.id), related_ids: (productData.related || []).map(p => p.id),
      });
      if (productData.main_image_url) setImagePreview(productData.main_image_url);
    }
  }, [productData, isEdit]);

  const saveMutation = useMutation({
    mutationFn: (data) => {
      const fd = new FormData();
      Object.entries(data).forEach(([k, v]) => {
        if (Array.isArray(v)) v.forEach(item => fd.append(k, item));
        else if (v !== null && v !== undefined && v !== '') fd.append(k, v);
      });
      if (imageFile) fd.append('main_image', imageFile);
      return isEdit ? productApi.update(id, fd) : productApi.create(fd);
    },
    onSuccess: () => { qc.invalidateQueries(['admin-products']); toast.success(t(isEdit ? 'تم التحديث' : 'تم إضافة المنتج', isEdit ? 'Updated' : 'Added')); navigate('/products'); },
    onError: (e) => {
      const d = e.response?.data;
      let msg = '';
      if (Array.isArray(d?.errors) && d.errors.length) {
        msg = d.errors.map(x => x.field ? `${x.field}: ${x.message}` : x.message).join('\n');
      } else if (d?.message && d.message !== 'Request error') {
        msg = d.message;
      } else if (d && typeof d === 'object') {
        const first = Object.values(d).flat().find(v => typeof v === 'string');
        if (first) msg = first;
      }
      toast.error(msg || t('حدث خطأ', 'Error'));
    },
  });

  const handleImageChange = (e) => {
    const file = e.target.files?.[0]; if (!file) return;
    setImageFile(file);
    const reader = new FileReader(); reader.onload = () => setImagePreview(reader.result); reader.readAsDataURL(file);
  };

  // ── Image gallery (extra images, edit mode only) ──
  const { data: galleryData } = useQuery({
    queryKey: ['product-images', id],
    queryFn: () => productApi.listImages(id).then(r => r.data),
    enabled: isEdit,
  });
  const gallery = Array.isArray(galleryData) ? galleryData : [];

  const addImagesMutation = useMutation({
    mutationFn: (files) => {
      const fd = new FormData();
      Array.from(files).forEach(f => fd.append('images', f));
      return productApi.addImages(id, fd);
    },
    onSuccess: () => { qc.invalidateQueries(['product-images', id]); toast.success(t('تمت إضافة الصور', 'Images added')); },
    onError: () => toast.error(t('تعذّر رفع الصور', 'Upload failed')),
  });
  const deleteImageMutation = useMutation({
    mutationFn: (imageId) => productApi.deleteImage(id, imageId),
    onSuccess: () => { qc.invalidateQueries(['product-images', id]); },
    onError: () => toast.error(t('تعذّر الحذف', 'Delete failed')),
  });

  const handleGalleryAdd = (e) => {
    const files = e.target.files;
    if (files && files.length) addImagesMutation.mutate(files);
    e.target.value = '';
  };

  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none transition-colors';
  const lbl = 'text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5';
  const categories = Array.isArray(categoriesData) ? categoriesData : (categoriesData?.results || []);
  const TABS = [
    { key: 'basic', ar: 'البيانات', en: 'Basic' }, { key: 'pricing', ar: 'السعر', en: 'Pricing' },
    { key: 'stock', ar: 'المخزون', en: 'Stock' }, { key: 'cats', ar: 'الأقسام', en: 'Categories' },
  ];

  return (
    <div className="p-6 max-w-3xl mx-auto">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => navigate('/products')} className="w-9 h-9 bg-white border border-gray-200 rounded-xl flex items-center justify-center hover:bg-gray-50">←</button>
        <h1 className="text-xl font-bold text-[#0D2440] font-serif">{isEdit ? t('تعديل المنتج', 'Edit Product') : t('إضافة منتج جديد', 'Add New Product')}</h1>
      </div>
      <div className="flex gap-1 mb-6 bg-gray-100 p-1 rounded-2xl">
        {TABS.map(tab => (
          <button key={tab.key} onClick={() => setActiveTab(tab.key)}
            className={`flex-1 py-2 px-3 rounded-xl text-xs font-semibold transition-all ${activeTab === tab.key ? 'bg-white text-[#0D2440] shadow-sm' : 'text-gray-500'}`}>
            {lang === 'ar' ? tab.ar : tab.en}
          </button>
        ))}
      </div>
      <div className="space-y-4">
        {activeTab === 'basic' && (
          <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm space-y-4">
            <div>
              <label className={lbl}>{t('صورة المنتج', 'Product Image')}</label>
              <div className="flex items-center gap-4">
                <div className="w-24 h-24 bg-[#E7F0FA] rounded-2xl overflow-hidden flex items-center justify-center flex-shrink-0">
                  {imagePreview ? <img src={imagePreview} alt="" className="w-full h-full object-cover" /> : <span className="text-3xl">🛍️</span>}
                </div>
                <div>
                  <label className="cursor-pointer bg-[#2E5E99] text-white px-4 py-2 rounded-xl text-sm font-semibold hover:bg-[#0D2440] transition-colors">
                    {t('اختر صورة', 'Choose Image')}<input type="file" accept="image/*" className="hidden" onChange={handleImageChange} />
                  </label>
                  <p className="text-xs text-gray-400 mt-1">{t('يتم ضغط الصورة تلقائياً', 'Auto-compressed')}</p>
                </div>
              </div>
            </div>

            {/* Extra images gallery — available after the product exists */}
            <div>
              <label className={lbl}>{t('صور إضافية', 'Additional Images')}</label>
              {!isEdit ? (
                <p className="text-xs text-gray-400">{t('احفظ المنتج أولاً لإضافة صور إضافية', 'Save the product first to add more images')}</p>
              ) : (
                <div className="flex flex-wrap items-center gap-3">
                  {gallery.map(img => (
                    <div key={img.id} className="relative w-20 h-20 rounded-xl overflow-hidden border border-gray-200 group">
                      <img src={img.image_url_full || img.image_url} alt="" className="w-full h-full object-cover" />
                      <button type="button" onClick={() => deleteImageMutation.mutate(img.id)}
                        className="absolute top-0.5 right-0.5 bg-red-500 text-white w-5 h-5 rounded-full text-xs leading-none flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">×</button>
                    </div>
                  ))}
                  <label className="cursor-pointer w-20 h-20 rounded-xl border-2 border-dashed border-gray-300 flex items-center justify-center text-2xl text-gray-400 hover:border-[#2E5E99] hover:text-[#2E5E99] transition-colors">
                    {addImagesMutation.isPending ? '…' : '+'}
                    <input type="file" accept="image/*" multiple className="hidden" onChange={handleGalleryAdd} />
                  </label>
                </div>
              )}
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>{t('الاسم بالعربية', 'Name Arabic')} *</label><input value={form.name_ar} onChange={e => setForm(f => ({...f, name_ar: e.target.value}))} placeholder="طماطم طازجة" className={inp} dir="rtl" /></div>
              <div><label className={lbl}>{t('الاسم بالإنجليزية', 'Name English')} *</label><input value={form.name_en} onChange={e => setForm(f => ({...f, name_en: e.target.value}))} placeholder="Fresh Tomatoes" className={inp} dir="ltr" /></div>
              <div className="col-span-2"><label className={lbl}>{t('الباركود', 'Barcode')}</label><input value={form.barcode} onChange={e => setForm(f => ({...f, barcode: e.target.value}))} placeholder="6001234567890" className={`${inp} font-mono`} /></div>
              <div><label className={lbl}>{t('الوصف عربي', 'Description Arabic')}</label><textarea value={form.description_ar} onChange={e => setForm(f => ({...f, description_ar: e.target.value}))} rows={3} className={`${inp} resize-none`} dir="rtl" /></div>
              <div><label className={lbl}>{t('الوصف إنجليزي', 'Description English')}</label><textarea value={form.description_en} onChange={e => setForm(f => ({...f, description_en: e.target.value}))} rows={3} className={`${inp} resize-none`} dir="ltr" /></div>
            </div>
            <div className="flex gap-6">
              {[{key:'is_available',ar:'متاح للبيع',en:'Available',color:'bg-[#2FBE8F]'},{key:'is_featured',ar:'منتج مميز',en:'Featured',color:'bg-[#FBBF24]'}].map(tgl => (
                <label key={tgl.key} className="flex items-center gap-3 cursor-pointer">
                  <button type="button" onClick={() => setForm(f => ({...f, [tgl.key]: !f[tgl.key]}))}
                    className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${form[tgl.key] ? tgl.color : 'bg-gray-200'}`}>
                    <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${form[tgl.key] ? 'translate-x-6' : 'translate-x-1'}`} />
                  </button>
                  <span className="text-sm font-medium text-[#0D2440]">{lang === 'ar' ? tgl.ar : tgl.en}</span>
                </label>
              ))}
            </div>
          </div>
        )}
        {activeTab === 'pricing' && (
          <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>{t('السعر الأصلي', 'Original Price')} *</label><input type="number" step="0.01" value={form.original_price} onChange={e => setForm(f => ({...f, original_price: e.target.value}))} placeholder="0.00" className={inp} /></div>
              <div><label className={lbl}>{t('سعر الخصم', 'Discount Price')}</label><input type="number" step="0.01" value={form.discount_price} onChange={e => setForm(f => ({...f, discount_price: e.target.value}))} placeholder="0.00" className={inp} /></div>
            </div>
            {form.original_price && form.discount_price && Number(form.discount_price) < Number(form.original_price) && (
              <div className="bg-[#ECFDF5] border border-[#a7f3d0] rounded-xl p-3 flex items-center gap-3">
                <span className="text-2xl">🏷️</span>
                <div className="font-bold text-[#065f46] text-sm">خصم {Math.round((1-Number(form.discount_price)/Number(form.original_price))*100)}% · وفر {(Number(form.original_price)-Number(form.discount_price)).toFixed(2)} EGP</div>
              </div>
            )}
            {form.discount_price && (
              <div className="border-2 border-dashed border-[#FBBF24] rounded-xl p-4 space-y-3">
                <p className="text-xs font-semibold text-[#b45309] uppercase">⏰ {t('جدولة الخصم', 'Schedule Discount')}</p>
                <div className="grid grid-cols-2 gap-3">
                  <div><label className={lbl}>{t('بداية', 'Start')}</label><input type="datetime-local" value={form.discount_start} onChange={e => setForm(f => ({...f, discount_start: e.target.value}))} className={inp} /></div>
                  <div><label className={lbl}>{t('نهاية', 'End')}</label><input type="datetime-local" value={form.discount_end} onChange={e => setForm(f => ({...f, discount_end: e.target.value}))} className={inp} /></div>
                </div>
              </div>
            )}
          </div>
        )}
        {activeTab === 'stock' && (
          <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>{t('الكمية', 'Stock Qty')}</label><input type="number" value={form.quantity_in_stock} onChange={e => setForm(f => ({...f, quantity_in_stock: e.target.value}))} placeholder="0" className={inp} /></div>
              <div><label className={lbl}>{t('حد التنبيه', 'Alert Threshold')}</label><input type="number" value={form.low_stock_threshold} onChange={e => setForm(f => ({...f, low_stock_threshold: e.target.value}))} placeholder="5" className={inp} /></div>
            </div>
            <div>
              <label className={lbl}>{t('وحدة البيع', 'Sell Unit')}</label>
              <div className="grid grid-cols-4 gap-2">
                {SELL_UNITS.map(u => (
                  <button key={u.value} type="button" onClick={() => setForm(f => ({...f, sell_unit: u.value}))}
                    className={`py-2.5 rounded-xl text-sm font-semibold border-2 transition-all ${form.sell_unit === u.value ? 'border-[#2E5E99] bg-[#E7F0FA] text-[#2E5E99]' : 'border-gray-100 text-gray-500'}`}>
                    {lang === 'ar' ? u.ar : u.en}
                  </button>
                ))}
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>{t('أقل طلب', 'Min Qty')}</label><input type="number" step="0.1" value={form.min_order_quantity} onChange={e => setForm(f => ({...f, min_order_quantity: e.target.value}))} placeholder="1" className={inp} /></div>
              <div><label className={lbl}>{t('أقصى طلب', 'Max Qty')}</label><input type="number" step="0.1" value={form.max_order_quantity} onChange={e => setForm(f => ({...f, max_order_quantity: e.target.value}))} placeholder={t('بلا حد', 'No limit')} className={inp} /></div>
            </div>
          </div>
        )}
        {activeTab === 'cats' && (
          <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm">
            <p className="text-xs text-gray-500 mb-4">{t('اختر أقساماً متعددة في نفس الوقت', 'Select multiple categories simultaneously')}</p>
            <div className="grid grid-cols-2 gap-2">
              {categories.map(cat => (
                <label key={cat.id} className={`flex items-center gap-3 p-3 border-2 rounded-xl cursor-pointer transition-all hover:border-[#2E5E99] ${form.category_ids.includes(cat.id) ? 'border-[#2E5E99] bg-[#E7F0FA]' : 'border-gray-100'}`}>
                  <input type="checkbox" checked={form.category_ids.includes(cat.id)} onChange={() => setForm(f => ({...f, category_ids: f.category_ids.includes(cat.id) ? f.category_ids.filter(c => c !== cat.id) : [...f.category_ids, cat.id]}))} className="w-4 h-4 accent-[#2E5E99]" />
                  <span className="text-xl">{cat.icon}</span>
                  <span className="text-sm font-medium text-[#0D2440]">{lang === 'ar' ? cat.name_ar : cat.name_en}</span>
                </label>
              ))}
            </div>
            {form.category_ids.length > 0 && <div className="mt-3 p-3 bg-[#E7F0FA] rounded-xl text-xs font-semibold text-[#2E5E99]">✓ {form.category_ids.length} {t('قسم محدد', 'selected')}</div>}
          </div>
        )}
        <div className="flex gap-3 pt-2">
          <button onClick={() => navigate('/products')} className="px-6 py-3 border-2 border-gray-200 rounded-xl text-sm font-semibold hover:bg-gray-50 transition-colors">{t('إلغاء', 'Cancel')}</button>
          <button onClick={() => saveMutation.mutate(form)} disabled={saveMutation.isPending || !form.name_ar || !form.original_price}
            className="flex-1 bg-[#0D2440] hover:bg-[#2E5E99] text-white py-3 rounded-xl text-sm font-bold disabled:opacity-40 transition-colors">
            {saveMutation.isPending ? '...' : `✅ ${isEdit ? t('حفظ', 'Save') : t('إضافة', 'Add')}`}
          </button>
        </div>
      </div>
    </div>
  );
}
