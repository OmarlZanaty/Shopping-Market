import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { analyticsApi } from '../../services/api';

export default function RatingsPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const [days, setDays] = useState(30);
  const { data, isLoading } = useQuery({ queryKey: ['ratings', days], queryFn: () => analyticsApi.ratings(days).then(r => r.data) });

  const summary = data?.summary || {};
  const byDriver = data?.by_driver || [];

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('تقرير التقييمات','Ratings Report')}</h1>
        <div className="flex gap-2">{[7,30,90].map(d => <button key={d} onClick={() => setDays(d)} className={`px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${days===d?'bg-[#0D2440] text-white':'bg-white border border-gray-200 text-gray-600'}`}>{d} {t('يوم','d')}</button>)}</div>
      </div>
      {isLoading ? <div className="flex items-center justify-center h-48"><div className="animate-spin w-8 h-8 border-4 border-[#FBBF24] border-t-transparent rounded-full" /></div> : (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {[{label:t('متوسط المنتجات','Avg Products'),val:(Number(summary.avg_product||0)).toFixed(1),icon:'🛍️',color:'bg-[#EFF6FF]'},
              {label:t('متوسط التوصيل','Avg Delivery'),val:(Number(summary.avg_delivery||0)).toFixed(1),icon:'🛵',color:'bg-[#ECFDF5]'},
              {label:t('إجمالي التقييمات','Total Ratings'),val:summary.total||0,icon:'⭐',color:'bg-[#FFFBEB]'},
              {label:t('تقييمات 1 نجمة','1-Star Ratings'),val:summary.one_star||0,icon:'⚠️',color:'bg-[#FFF0F3]'}].map(s => (
              <div key={s.label} className={`${s.color} rounded-2xl p-4 border border-gray-100`}>
                <div className="text-2xl mb-2">{s.icon}</div>
                <div className="font-bold text-[#0D2440] text-xl font-serif">{s.val}</div>
                <div className="text-gray-500 text-xs mt-1">{s.label}</div>
              </div>
            ))}
          </div>
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div className="p-4 border-b border-gray-100 font-bold text-[#0D2440] font-serif">{t('أداء المناديب (بالتقييمات)','Drivers by Rating')}</div>
            <div className="overflow-x-auto"><table className="w-full text-sm"><thead className="bg-gray-50 border-b border-gray-100"><tr>{[t('المندوب','Driver'),t('هاتفه','Phone'),t('متوسط التقييم','Avg Rating'),t('عدد التقييمات','Count'),t('تقييمات سيئة','Bad Reviews')].map(h => <th key={h} className="px-4 py-2.5 text-start text-xs font-semibold text-gray-500 uppercase">{h}</th>)}</tr></thead>
            <tbody className="divide-y divide-gray-50">{byDriver.map((d,i) => (
              <tr key={i} className={`hover:bg-gray-50 ${Number(d.avg_rating) < 3 ? 'bg-red-50' : ''}`}>
                <td className="px-4 py-3 font-semibold text-[#0D2440]">{d.agent_name||'—'}</td>
                <td className="px-4 py-3 text-xs text-gray-400">{d.agent_phone}</td>
                <td className="px-4 py-3"><div className="flex items-center gap-1">{'★'.repeat(Math.round(Number(d.avg_rating||0)))}<span className="text-xs text-gray-400 ms-1">({Number(d.avg_rating||0).toFixed(1)})</span></div></td>
                <td className="px-4 py-3 font-bold">{d.count}</td>
                <td className="px-4 py-3"><span className={`text-xs font-bold px-2 py-1 rounded-full ${d.bad>0?'bg-red-100 text-red-600':'bg-green-100 text-green-700'}`}>{d.bad}</span></td>
              </tr>
            ))}</tbody></table></div>
          </div>
        </>
      )}
    </div>
  );
}
