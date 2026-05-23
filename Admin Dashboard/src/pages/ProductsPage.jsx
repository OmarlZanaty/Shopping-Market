import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate, useOutletContext } from 'react-router-dom';
import { productApi } from '../services/api';
import toast from 'react-hot-toast';

export default function ProductsPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('');
  const [page, setPage] = useState(1);
  const [barcodeInput, setBarcodeInput] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['admin-products', search, category, page],
    queryFn: () => productApi.list({ search, category, page }).then(r => r.data),
  });

  const toggleMutation = useMutation({
    mutationFn: (id) => productApi.toggle(id),
    onSuccess: () => {
      qc.invalidateQueries(['admin-products']);
      toast.success(t('تم تحديث حالة المنتج', 'Product availability updated'));
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id) => productApi.delete(id),
    onSuccess: () => {
      qc.invalidateQueries(['admin-products']);
      toast.success(t('تم حذف المنتج', 'Product deleted'));
    },
  });

  const searchByBarcode = async () => {
    if (!barcodeInput.trim()) return;
    try {
      const { data } = await productApi.byBarcode(barcodeInput.trim());
      navigate(`/products/${data.id}/edit`);
    } catch {
      toast.error(t('المنتج غير موجود', 'Product not found'));
    }
  };

  const products = data?.results || [];

  return (
    <div className="p-6 space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('المنتجات', 'Products')}</h1>
          <p className="text-gray-500 text-sm">{data?.count || 0} {t('منتج', 'products')}</p>
        </div>
        <button
          onClick={() => navigate('/products/new')}
          className="bg-[#2E5E99] hover:bg-[#0D2440] text-white px-5 py-2.5 rounded-xl font-semibold text-sm transition-colors flex items-center gap-2"
        >
          + {t('إضافة منتج', 'Add Product')}
        </button>
      </div>

      {/* Search bar + barcode */}
      <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
        <div className="flex gap-3 flex-wrap">
          <input
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
            placeholder={t('🔍 ابحث بالاسم أو الوصف...', '🔍 Search by name or description...')}
            className="flex-1 min-w-48 border border-gray-200 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#2E5E99]"
          />
          <div className="flex gap-2">
            <input
              value={barcodeInput}
              onChange={e => setBarcodeInput(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && searchByBarcode()}
              placeholder={t('📦 باركود...', '📦 Barcode...')}
              className="border border-gray-200 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#F97316] w-36 font-mono"
            />
            <button
              onClick={searchByBarcode}
              className="bg-[#F97316] hover:bg-orange-600 text-white px-4 py-2.5 rounded-xl text-sm font-semibold transition-colors"
            >
              {t('بحث', 'Scan')}
            </button>
          </div>
        </div>
      </div>

      {/* Table */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        {isLoading ? (
          <div className="flex items-center justify-center h-48">
            <div className="animate-spin w-8 h-8 border-4 border-[#2E5E99] border-t-transparent rounded-full" />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100">
                <tr>
                  <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{t('المنتج', 'Product')}</th>
                  <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{t('الباركود', 'Barcode')}</th>
                  <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{t('السعر', 'Price')}</th>
                  <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{t('المخزون', 'Stock')}</th>
                  <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{t('الحالة', 'Status')}</th>
                  <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{t('الإجراءات', 'Actions')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {products.map(product => (
                  <tr key={product.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-[#E7F0FA] rounded-lg overflow-hidden flex-shrink-0">
                          {product.main_image_url
                            ? <img src={product.main_image_url} alt="" className="w-full h-full object-cover" />
                            : <div className="w-full h-full flex items-center justify-center text-lg">🛍️</div>
                          }
                        </div>
                        <div>
                          <div className="font-semibold text-[#0D2440]">
                            {lang === 'ar' ? product.name_ar : product.name_en}
                          </div>
                          <div className="text-xs text-gray-400">{product.sell_unit}</div>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 font-mono text-xs text-gray-500">{product.barcode || '—'}</td>
                    <td className="px-4 py-3">
                      <div className="font-bold text-[#2E5E99]">{product.current_price} EGP</div>
                      {product.discount_price && (
                        <div className="text-xs text-gray-400 line-through">{product.original_price}</div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`font-semibold ${product.quantity_in_stock <= 0 ? 'text-red-500' : product.quantity_in_stock <= 5 ? 'text-orange-500' : 'text-green-600'}`}>
                        {product.quantity_in_stock}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <button
                        onClick={() => toggleMutation.mutate(product.id)}
                        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors
                          ${product.is_available ? 'bg-[#2FBE8F]' : 'bg-gray-300'}`}
                      >
                        <span className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform
                          ${product.is_available ? 'translate-x-6' : 'translate-x-1'}`} />
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => navigate(`/products/${product.id}/edit`)}
                          className="text-[#2E5E99] hover:bg-[#E7F0FA] px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors"
                        >
                          {t('تعديل', 'Edit')}
                        </button>
                        <button
                          onClick={() => {
                            if (confirm(t('هل تريد حذف هذا المنتج؟', 'Delete this product?'))) {
                              deleteMutation.mutate(product.id);
                            }
                          }}
                          className="text-red-500 hover:bg-red-50 px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors"
                        >
                          {t('حذف', 'Delete')}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {products.length === 0 && (
              <div className="text-center py-16 text-gray-400">
                <div className="text-4xl mb-3">📦</div>
                <div>{t('لا توجد منتجات', 'No products found')}</div>
              </div>
            )}
          </div>
        )}

        {/* Pagination */}
        {data?.count > 20 && (
          <div className="px-4 py-3 border-t border-gray-100 flex items-center justify-between">
            <span className="text-sm text-gray-500">
              {t(`صفحة ${page} من ${Math.ceil(data.count / 20)}`, `Page ${page} of ${Math.ceil(data.count / 20)}`)}
            </span>
            <div className="flex gap-2">
              <button disabled={page === 1} onClick={() => setPage(p => p - 1)}
                className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">
                {t('السابق', 'Prev')}
              </button>
              <button disabled={page >= Math.ceil(data.count / 20)} onClick={() => setPage(p => p + 1)}
                className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">
                {t('التالي', 'Next')}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
