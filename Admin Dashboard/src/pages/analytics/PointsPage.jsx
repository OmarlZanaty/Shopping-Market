import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { analyticsApi } from '../../services/api';

export default function PointsPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const [days, setDays] = useState(30);
  const { data, isLoading } = useQuery({ queryKey: ['points', days], queryFn: () => analyticsApi.points(days).then(r => r.data) });

  const summary = data?.summary || {};
  const top = data?.top_earners || [];

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('نقاط الولاء','Loyalty Points')}</h1>
        <div className="flex gap-2">{[7,30,90].map(d => <button key={d} onClick={() => setDays(d)} className={`px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${days===d?'bg-[#0D2440] text-white':'bg-white border border-gray-200 text-gray-600'}`}>{d} {t('يوم','d')}</button>)}</div>
      </div>
      {isLoading ? <div className="flex items-center justify-center h-48"><div className="animate-spin w-8 h-8 border-4 border-[#FBBF24] border-t-transparent rounded-full" /></div> : (
        <>
          <div className="grid grid-cols-3 gap-4">
            {[{label:t('نقاط مكتسبة','Points Earned'),val:summary.total_earned||0,icon:'⬆️',color:'bg-[#ECFDF5]',text:'text-[#2FBE8F]'},
              {label:t('نقاط مستخدمة','Points Redeemed'),val:summary.total_redeemed||0,icon:'⬇️',color:'bg-[#FFF0F3]',text:'text-[#FB7185]'},
              {label:t('نقاط مكافأة','Bonus Points'),val:summary.total_bonus||0,icon:'🎁',color:'bg-[#FFFBEB]',text:'text-[#FBBF24]'}].map(s => (
              <div key={s.label} className={`${s.color} rounded-2xl p-5 border border-gray-100`}>
                <div className="text-2xl mb-2">{s.icon}</div>
                <div className={`text-3xl font-bold font-serif ${s.text}`}>{(s.val||0).toLocaleString()}</div>
                <div className="text-gray-500 text-sm mt-1">{s.label}</div>
              </div>
            ))}
          </div>
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div className="p-4 border-b border-gray-100 font-bold text-[#0D2440] font-serif">🏆 {t('أعلى 20 عميل بالنقاط','Top 20 Points Earners')}</div>
            <div className="divide-y divide-gray-50 max-h-96 overflow-y-auto">
              {top.map((u,i) => (
                <div key={i} className="px-4 py-3 flex items-center gap-3">
                  <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold ${i<3?'bg-[#FBBF24] text-white':'bg-gray-100 text-gray-600'}`}>{i+1}</div>
                  <div className="flex-1"><div className="font-semibold text-[#0D2440] text-sm">{u.full_name}</div><div className="text-xs text-gray-400">{u.phone}</div></div>
                  <div className="flex items-center gap-1"><span className="text-[#FBBF24]">⭐</span><span className="font-bold text-[#0D2440]">{u.loyalty_points?.toLocaleString()}</span></div>
                </div>
              ))}
              {!top.length && <div className="text-center py-8 text-gray-400 text-sm">{t('لا توجد بيانات','No data available')}</div>}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
