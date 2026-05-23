import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { analyticsApi } from '../../services/api';

export default function DriversAnalyticsPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const [days, setDays] = useState(30);

  const { data: drivers, isLoading } = useQuery({ queryKey: ['driver-analytics', days], queryFn: () => analyticsApi.drivers(days).then(r => r.data) });

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div><h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('أداء المناديب','Driver Performance')}</h1></div>
        <div className="flex gap-2">
          {[7,14,30,90].map(d => <button key={d} onClick={() => setDays(d)} className={`px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${days===d ? 'bg-[#0D2440] text-white' : 'bg-white border border-gray-200 text-gray-600'}`}>{d} {t('يوم','d')}</button>)}
        </div>
      </div>
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        {isLoading ? <div className="flex items-center justify-center h-48"><div className="animate-spin w-8 h-8 border-4 border-[#2E5E99] border-t-transparent rounded-full" /></div> : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100"><tr>
                {[t('المندوب','Driver'),t('الطلبات','Orders'),t('التقييم','Rating'),t('متوسط التوصيل','Avg Delivery'),t('الإيرادات','Revenue'),t('الكاش','Cash'),t('الحالة','Status')].map(h => <th key={h} className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{h}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-gray-50">
                {(drivers || []).map(d => (
                  <tr key={d.driver_id} className="hover:bg-gray-50">
                    <td className="px-4 py-3"><div className="flex items-center gap-2"><div className="w-8 h-8 bg-[#2E5E99] rounded-full flex items-center justify-center text-white font-bold text-sm">{d.name?.[0]}</div><div><div className="font-semibold text-[#0D2440]">{d.name}</div><div className="text-xs text-gray-400">{d.phone}</div></div></div></td>
                    <td className="px-4 py-3 font-bold text-[#0D2440]">{d.orders_completed}</td>
                    <td className="px-4 py-3"><div className="flex items-center gap-1"><span className="text-[#FBBF24]">⭐</span><span className="font-bold">{d.avg_rating}</span><span className="text-xs text-gray-400">({d.ratings_count})</span></div></td>
                    <td className="px-4 py-3">{d.avg_delivery_minutes} {t('دقيقة','min')}</td>
                    <td className="px-4 py-3 font-bold text-[#2FBE8F]">{d.total_revenue_delivered} EGP</td>
                    <td className="px-4 py-3"><span className={`font-bold ${Number(d.cash_on_hand) > 0 ? 'text-[#F97316]' : 'text-gray-400'}`}>{d.cash_on_hand} EGP</span></td>
                    <td className="px-4 py-3"><span className={`text-xs font-semibold px-2 py-1 rounded-full ${d.is_online ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{d.is_online ? t('متاح','Online') : t('غير متاح','Offline')}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
