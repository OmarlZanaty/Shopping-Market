import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext, useNavigate } from 'react-router-dom';
import { userApi } from '../services/api';
import toast from 'react-hot-toast';

export default function DriversPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['drivers', search],
    queryFn: () => userApi.drivers({ search }).then(r => r.data),
  });

  const blockMutation = useMutation({
    mutationFn: (id) => userApi.block(id),
    onSuccess: () => { qc.invalidateQueries(['drivers']); toast.success(t('تم تحديث الحالة', 'Status updated')); },
  });

  const settleMutation = useMutation({
    mutationFn: ({ id, amount }) => userApi.settle(id, { amount }),
    onSuccess: () => { qc.invalidateQueries(['drivers']); toast.success(t('تمت التسوية', 'Settlement done')); },
  });

  const drivers = data?.results || [];

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('المناديب', 'Drivers')}</h1>
        <button onClick={() => navigate('/drivers/new')}
          className="bg-[#2E5E99] text-white px-5 py-2.5 rounded-xl font-semibold text-sm">
          + {t('إضافة مندوب', 'Add Driver')}
        </button>
      </div>
      <input value={search} onChange={e => setSearch(e.target.value)}
        placeholder={t('🔍 ابحث...', '🔍 Search drivers...')}
        className="w-full bg-white border border-gray-200 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#2E5E99]" />
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {drivers.map(driver => (
          <div key={driver.id} className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
            <div className="flex items-start justify-between mb-3">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-[#2E5E99] rounded-full flex items-center justify-center text-white font-bold text-lg">
                  {driver.full_name?.[0]}
                </div>
                <div>
                  <div className="font-bold text-[#0D2440]">{driver.full_name}</div>
                  <div className="text-sm text-gray-400">{driver.phone}</div>
                </div>
              </div>
              <div className="flex flex-col items-end gap-1">
                <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${driver.is_online ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
                  {driver.is_online ? t('متاح', 'Online') : t('غير متاح', 'Offline')}
                </span>
                <span className={`text-xs px-2 py-0.5 rounded-full ${driver.is_active ? 'bg-blue-100 text-blue-700' : 'bg-red-100 text-red-600'}`}>
                  {driver.is_active ? t('نشط', 'Active') : t('محظور', 'Blocked')}
                </span>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-2 text-center mb-4">
              <div className="bg-[#E7F0FA] rounded-xl p-2">
                <div className="font-bold text-[#2E5E99] text-sm">{driver.total_deliveries}</div>
                <div className="text-xs text-gray-500">{t('توصيلات', 'Deliveries')}</div>
              </div>
              <div className="bg-[#ECFDF5] rounded-xl p-2">
                <div className="font-bold text-[#2FBE8F] text-sm">⭐ {driver.rating}</div>
                <div className="text-xs text-gray-500">{t('تقييم', 'Rating')}</div>
              </div>
              <div className="bg-[#FFF7ED] rounded-xl p-2">
                <div className="font-bold text-[#F97316] text-sm">{driver.cash_on_hand} EGP</div>
                <div className="text-xs text-gray-500">{t('كاش', 'Cash')}</div>
              </div>
            </div>
            <div className="flex gap-2">
              <button onClick={() => blockMutation.mutate(driver.id)}
                className={`flex-1 py-2 rounded-xl text-xs font-semibold transition-colors ${driver.is_active ? 'bg-red-50 text-red-600 hover:bg-red-100' : 'bg-green-50 text-green-700 hover:bg-green-100'}`}>
                {driver.is_active ? t('إيقاف', 'Block') : t('تفعيل', 'Activate')}
              </button>
              {driver.cash_on_hand > 0 && (
                <button onClick={() => settleMutation.mutate({ id: driver.id, amount: driver.cash_on_hand })}
                  className="flex-1 py-2 bg-[#E7F0FA] text-[#2E5E99] rounded-xl text-xs font-semibold hover:bg-[#dbeafe] transition-colors">
                  {t('تسوية الحساب', 'Settle')}
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
