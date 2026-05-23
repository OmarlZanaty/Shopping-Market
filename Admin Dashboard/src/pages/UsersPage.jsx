import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { userApi } from '../services/api';
import toast from 'react-hot-toast';

export default function UsersPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);

  const { data, isLoading } = useQuery({
    queryKey: ['customers', search, page],
    queryFn: () => userApi.list({ search, role: 'customer', page }).then(r => r.data),
  });
  const blockMutation = useMutation({
    mutationFn: (id) => userApi.block(id),
    onSuccess: () => { qc.invalidateQueries(['customers']); toast.success(t('تم تحديث الحالة','Status updated')); },
  });

  const users = data?.results || [];
  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div><h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('العملاء','Customers')}</h1><p className="text-gray-500 text-sm">{data?.count || 0} {t('عميل','customers')}</p></div>
      </div>
      <input value={search} onChange={e => { setSearch(e.target.value); setPage(1); }} placeholder={t('🔍 ابحث بالاسم أو الهاتف...','🔍 Search...')}
        className="w-full bg-white border border-gray-200 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#2E5E99]" />
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        {isLoading ? <div className="flex items-center justify-center h-48"><div className="animate-spin w-8 h-8 border-4 border-[#2E5E99] border-t-transparent rounded-full" /></div> : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100">
                <tr>{[t('العميل','Customer'), t('الهاتف','Phone'), t('الرصيد','Wallet'), t('النقاط','Points'), t('الطلبات','Orders'), t('الحالة','Status'), t('إجراءات','Actions')].map(h => <th key={h} className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{h}</th>)}</tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {users.map(user => (
                  <tr key={user.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3"><div className="flex items-center gap-2"><div className="w-8 h-8 bg-[#E7F0FA] rounded-full flex items-center justify-center text-[#2E5E99] font-bold text-sm">{user.full_name?.[0]}</div><span className="font-medium text-[#0D2440]">{user.full_name}</span></div></td>
                    <td className="px-4 py-3 font-mono text-xs text-gray-600">{user.phone}</td>
                    <td className="px-4 py-3 text-[#2FBE8F] font-semibold">{user.wallet_balance} EGP</td>
                    <td className="px-4 py-3"><span className="bg-[#FFF7ED] text-[#F97316] font-bold text-xs px-2 py-1 rounded-full">⭐ {user.loyalty_points}</span></td>
                    <td className="px-4 py-3 text-center font-semibold">{user.order_streak || 0}</td>
                    <td className="px-4 py-3"><span className={`text-xs font-semibold px-2 py-1 rounded-full ${user.is_active ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-600'}`}>{user.is_active ? t('نشط','Active') : t('محظور','Blocked')}</span></td>
                    <td className="px-4 py-3"><button onClick={() => blockMutation.mutate(user.id)} className={`text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors ${user.is_active ? 'text-orange-600 hover:bg-orange-50' : 'text-green-600 hover:bg-green-50'}`}>{user.is_active ? t('حظر','Block') : t('تفعيل','Activate')}</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
            {users.length === 0 && <div className="text-center py-12 text-gray-400"><div className="text-4xl mb-2">👥</div><div>{t('لا يوجد عملاء','No customers found')}</div></div>}
          </div>
        )}
        {data?.count > 20 && (
          <div className="px-4 py-3 border-t border-gray-100 flex items-center justify-between">
            <span className="text-sm text-gray-500">{t(`صفحة ${page}`,`Page ${page}`)}</span>
            <div className="flex gap-2">
              <button disabled={page===1} onClick={() => setPage(p=>p-1)} className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">{t('السابق','Prev')}</button>
              <button disabled={!data?.next} onClick={() => setPage(p=>p+1)} className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">{t('التالي','Next')}</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
