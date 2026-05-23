import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { api } from '../services/api';
import toast from 'react-hot-toast';

export default function MediaLibraryPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [uploading, setUploading] = useState(false);
  const [search, setSearch] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['media-library', search],
    queryFn: () => api.get('/products/admin/media/', { params: { search } }).then(r => r.data),
  });

  const uploadMutation = useMutation({
    mutationFn: async (file) => {
      const fd = new FormData();
      fd.append('image', file);
      fd.append('name', file.name);
      return api.post('/products/admin/media/', fd, { headers: { 'Content-Type': 'multipart/form-data' } });
    },
    onSuccess: () => { qc.invalidateQueries(['media-library']); toast.success(t('تم رفع الصورة', 'Image uploaded')); },
    onError: () => toast.error(t('فشل الرفع', 'Upload failed')),
  });

  const deleteMutation = useMutation({
    mutationFn: (id) => api.delete(`/products/admin/media/${id}/`),
    onSuccess: () => { qc.invalidateQueries(['media-library']); toast.success(t('تم الحذف', 'Deleted')); },
  });

  const media = data?.results || (Array.isArray(data) ? data : []);

  const handleDrop = (e) => {
    e.preventDefault();
    const files = e.dataTransfer?.files || e.target?.files;
    if (!files) return;
    Array.from(files).forEach(file => uploadMutation.mutate(file));
  };

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('مكتبة الوسائط', 'Media Library')}</h1>
          <p className="text-gray-500 text-sm">{t('ارفع صورة مرة واحدة واستخدمها في عدة منتجات', 'Upload once, use across multiple products')}</p>
        </div>
      </div>

      {/* Upload drop zone */}
      <label onDrop={handleDrop} onDragOver={e => e.preventDefault()}
        className="block border-2 border-dashed border-[#7BA4D0] rounded-2xl p-8 text-center cursor-pointer hover:border-[#2E5E99] hover:bg-[#E7F0FA] transition-all group">
        <div className="text-4xl mb-3 group-hover:scale-110 transition-transform">📁</div>
        <div className="font-bold text-[#0D2440]">{t('اسحب الصور هنا أو اضغط للرفع', 'Drag images here or click to upload')}</div>
        <div className="text-sm text-gray-400 mt-1">{t('JPG, PNG, WebP — يتم ضغط الصور تلقائياً', 'JPG, PNG, WebP — auto-compressed')}</div>
        {uploadMutation.isPending && <div className="mt-3 text-[#2E5E99] font-semibold text-sm">{t('جاري الرفع...', 'Uploading...')}</div>}
        <input type="file" accept="image/*" multiple className="hidden" onChange={handleDrop} />
      </label>

      {/* Search */}
      <input value={search} onChange={e => setSearch(e.target.value)} placeholder={t('🔍 ابحث في المكتبة...', '🔍 Search library...')}
        className="w-full bg-white border border-gray-200 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#2E5E99]" />

      {/* Grid */}
      {isLoading ? (
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
          {Array(12).fill(0).map((_, i) => <div key={i} className="aspect-square bg-gray-100 rounded-xl animate-pulse" />)}
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
          {media.map(item => (
            <div key={item.id} className="group relative aspect-square bg-[#E7F0FA] rounded-xl overflow-hidden border border-gray-100 hover:border-[#2E5E99] transition-all cursor-pointer">
              <img src={item.image_url || item.image} alt={item.name} className="w-full h-full object-cover" />
              <div className="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-end">
                <div className="p-2 w-full">
                  <div className="text-white text-xs font-semibold truncate">{item.name}</div>
                  <div className="flex gap-1 mt-1">
                    <button onClick={() => navigator.clipboard.writeText(item.image_url || item.image).then(() => toast.success(t('تم النسخ', 'Copied!')))}
                      className="flex-1 bg-[#2E5E99] text-white rounded py-1 text-xs font-semibold">{t('نسخ', 'Copy')}</button>
                    <button onClick={() => { if(confirm(t('حذف؟','Delete?'))) deleteMutation.mutate(item.id); }}
                      className="bg-red-500 text-white rounded px-2 py-1 text-xs font-semibold">✕</button>
                  </div>
                </div>
              </div>
              {item.use_count > 0 && (
                <div className="absolute top-1.5 right-1.5 bg-[#2E5E99] text-white text-xs rounded-full w-5 h-5 flex items-center justify-center font-bold">
                  {item.use_count}
                </div>
              )}
            </div>
          ))}
          {media.length === 0 && (
            <div className="col-span-6 text-center py-16 text-gray-400">
              <div className="text-4xl mb-3">🖼️</div>
              <div>{t('لا توجد صور في المكتبة', 'No images in library')}</div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
