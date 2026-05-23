import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { analyticsApi } from '../../services/api';

export default function InventoryAnalyticsPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const { data, isLoading } = useQuery({ queryKey: ['inventory'], queryFn: () => analyticsApi.inventory().then(r => r.data) });

  return (
    <div className="p-6 space-y-5">
      <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('تقرير المخزون','Inventory Report')}</h1>
      {isLoading ? <div className="flex items-center justify-center h-48"><div className="animate-spin w-8 h-8 border-4 border-[#2E5E99] border-t-transparent rounded-full" /></div> : (
        <>
          <div className="grid grid-cols-3 gap-4">
            {[{label:t('إجمالي المنتجات','Total Products'),val:data?.total_products||0,color:'bg-[#EFF6FF]',text:'text-[#2E5E99]'},
              {label:t('منتجات نشطة','Active'),val:data?.active_products||0,color:'bg-[#ECFDF5]',text:'text-[#2FBE8F]'},
              {label:t('مخزون منخفض','Low Stock'),val:data?.low_stock?.length||0,color:'bg-[#FFF7ED]',text:'text-[#F97316]'}].map(s => (
              <div key={s.label} className={`${s.color} rounded-2xl p-5 border border-gray-100`}>
                <div className={`text-3xl font-bold font-serif ${s.text}`}>{s.val}</div>
                <div className="text-gray-500 text-sm mt-1">{s.label}</div>
              </div>
            ))}
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
            <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
              <div className="p-4 border-b border-gray-100 font-bold text-[#0D2440] font-serif flex items-center gap-2"><span className="text-[#F97316]">⚠️</span> {t('مخزون منخفض','Low Stock')} ({data?.low_stock?.length||0})</div>
              <div className="divide-y divide-gray-50 max-h-80 overflow-y-auto">
                {(data?.low_stock||[]).map((p, i) => <div key={i} className="px-4 py-3 flex items-center justify-between">
                  <div><div className="font-medium text-[#0D2440] text-sm">{lang==='ar'?p.name_ar:p.name_en}</div><div className="text-xs text-gray-400 font-mono">{p.barcode}</div></div>
                  <div className="text-right"><div className={`font-bold text-sm ${p.quantity_in_stock <= 2 ? 'text-red-500' : 'text-[#F97316]'}`}>{p.quantity_in_stock} {t('قطعة','pcs')}</div><div className="text-xs text-gray-400">{t('حد التنبيه','threshold')}: {p.low_stock_threshold}</div></div>
                </div>)}
                {!(data?.low_stock?.length) && <div className="text-center py-8 text-gray-400 text-sm">✅ {t('لا مخزون منخفض','No low stock')}</div>}
              </div>
            </div>
            <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
              <div className="p-4 border-b border-gray-100 font-bold text-[#0D2440] font-serif flex items-center gap-2"><span className="text-red-500">❌</span> {t('نفد المخزون','Out of Stock')} ({data?.out_of_stock?.length||0})</div>
              <div className="divide-y divide-gray-50 max-h-80 overflow-y-auto">
                {(data?.out_of_stock||[]).map((p, i) => <div key={i} className="px-4 py-3 flex items-center justify-between">
                  <div><div className="font-medium text-[#0D2440] text-sm">{lang==='ar'?p.name_ar:p.name_en}</div><div className="text-xs text-gray-400 font-mono">{p.barcode}</div></div>
                  <span className="text-xs bg-red-100 text-red-600 font-bold px-2 py-1 rounded-full">{t('نفذ','Out')}</span>
                </div>)}
                {!(data?.out_of_stock?.length) && <div className="text-center py-8 text-gray-400 text-sm">✅ {t('جميع المنتجات متوفرة','All products in stock')}</div>}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
