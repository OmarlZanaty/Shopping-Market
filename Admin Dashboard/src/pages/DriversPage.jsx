import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext, useNavigate } from 'react-router-dom';
import { userApi } from '../services/api';
import toast from 'react-hot-toast';

export default function DriversPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => (lang === 'ar' ? ar : en);
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(null); // { id, name } or null

  const { data, isLoading } = useQuery({
    queryKey: ['drivers', search],
    queryFn: () => userApi.drivers({ search }).then((r) => r.data),
  });

  const blockMutation = useMutation({
    mutationFn: (id) => userApi.block(id),
    onSuccess: () => {
      qc.invalidateQueries(['drivers']);
      toast.success(t('تم تحديث الحالة', 'Status updated'));
    },
  });

  const settleMutation = useMutation({
    mutationFn: ({ id, amount }) => userApi.settle(id, { amount }),
    onSuccess: () => {
      qc.invalidateQueries(['drivers']);
      toast.success(t('تمت التسوية', 'Settlement done'));
    },
  });

  // Hard-delete (permanent DB removal). The account fully disappears.
  const deleteMutation = useMutation({
    mutationFn: (id) => userApi.delete(id, { hard: true }),
    onSuccess: (resp) => {
      qc.invalidateQueries(['drivers']);
      const msg = resp?.data?.message || t('تم حذف الحساب نهائياً', 'Account permanently deleted');
      toast.success(msg);
      setConfirmDelete(null);
    },
    onError: (e) => {
      const msg = e.response?.data?.message || e.message
        || t('تعذر الحذف', 'Could not delete');
      toast.error(msg, { duration: 5000 });
    },
  });

  const drivers = data?.results || data?.data || [];

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('المناديب', 'Drivers')}</h1>
        <button onClick={() => navigate('/drivers/new')}
          className="bg-[#2E5E99] text-white px-5 py-2.5 rounded-xl font-semibold text-sm">
          + {t('إضافة مندوب', 'Add Driver')}
        </button>
      </div>

      <input value={search} onChange={(e) => setSearch(e.target.value)}
        placeholder={t('🔍 ابحث...', '🔍 Search drivers...')}
        className="w-full bg-white border border-gray-200 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#2E5E99]" />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {drivers.map((driver) => (
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

            <div className="grid grid-cols-2 gap-2">
              <button onClick={() => navigate(`/drivers/${driver.id}/edit`)}
                className="py-2 bg-gray-50 text-[#0D2440] rounded-xl text-xs font-semibold hover:bg-gray-100 transition-colors">
                ✏️ {t('تعديل', 'Edit')}
              </button>
              <button onClick={() => blockMutation.mutate(driver.id)}
                className={`py-2 rounded-xl text-xs font-semibold transition-colors ${
                  driver.is_active
                    ? 'bg-orange-50 text-orange-600 hover:bg-orange-100'
                    : 'bg-green-50 text-green-700 hover:bg-green-100'}`}>
                {driver.is_active ? `🛑 ${t('إيقاف', 'Block')}` : `▶️ ${t('تفعيل', 'Activate')}`}
              </button>

              {driver.cash_on_hand > 0 && (
                <button onClick={() => settleMutation.mutate({ id: driver.id, amount: driver.cash_on_hand })}
                  className="py-2 bg-[#E7F0FA] text-[#2E5E99] rounded-xl text-xs font-semibold hover:bg-[#dbeafe] transition-colors">
                  💰 {t('تسوية', 'Settle')}
                </button>
              )}
              <button onClick={() => setConfirmDelete({ id: driver.id, name: driver.full_name })}
                className={`${driver.cash_on_hand > 0 ? '' : 'col-span-2'} py-2 bg-red-50 text-red-600 rounded-xl text-xs font-semibold hover:bg-red-100 transition-colors`}>
                🗑️ {t('حذف', 'Delete')}
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* ── Confirm delete modal ───────────────────────────────────────── */}
      {confirmDelete && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
          onClick={() => !deleteMutation.isPending && setConfirmDelete(null)}>
          <div className="bg-white rounded-2xl p-6 max-w-md w-full shadow-2xl"
            onClick={(e) => e.stopPropagation()}>
            <div className="text-center mb-4">
              <div className="w-14 h-14 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-3">
                <span className="text-3xl">🗑️</span>
              </div>
              <h3 className="text-lg font-bold text-[#0D2440]">{t('تأكيد الحذف', 'Confirm Delete')}</h3>
              <p className="text-sm text-gray-600 mt-2">
                {t(
                  `هل تريد فعلاً حذف الموظف "${confirmDelete.name}" نهائياً؟ سيتم حذف الحساب بالكامل ولن يظهر مرة أخرى. لا يمكن التراجع عن هذا الإجراء.`,
                  `Permanently delete staff "${confirmDelete.name}"? The account will be completely removed and cannot be recovered.`,
                )}
              </p>
            </div>
            <div className="flex gap-3">
              <button onClick={() => setConfirmDelete(null)}
                disabled={deleteMutation.isPending}
                className="flex-1 px-4 py-2.5 border-2 border-gray-200 rounded-xl text-sm font-semibold hover:bg-gray-50 disabled:opacity-40">
                {t('إلغاء', 'Cancel')}
              </button>
              <button onClick={() => deleteMutation.mutate(confirmDelete.id)}
                disabled={deleteMutation.isPending}
                className="flex-1 px-4 py-2.5 bg-red-600 hover:bg-red-700 text-white rounded-xl text-sm font-bold disabled:opacity-40 flex items-center justify-center gap-2">
                {deleteMutation.isPending
                  ? <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />{t('جاري الحذف...', 'Deleting...')}</>
                  : t('حذف', 'Delete')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
