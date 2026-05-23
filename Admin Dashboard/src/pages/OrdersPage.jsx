import React, { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext, useNavigate } from 'react-router-dom';
import { orderApi, userApi } from '../services/api';
import toast from 'react-hot-toast';

const STATUS_CONFIG = {
  new:              { ar: 'جديد',           en: 'New',              color: 'bg-blue-100 text-blue-800',   dot: 'bg-blue-500' },
  preparing:        { ar: 'يتم التحضير',     en: 'Preparing',        color: 'bg-yellow-100 text-yellow-800', dot: 'bg-yellow-500' },
  out_for_delivery: { ar: 'خرج للتوصيل',    en: 'Out for Delivery', color: 'bg-orange-100 text-orange-800', dot: 'bg-orange-500' },
  delivered:        { ar: 'تم التسليم',      en: 'Delivered',        color: 'bg-green-100 text-green-800',  dot: 'bg-green-500' },
  cancelled:        { ar: 'ملغي',            en: 'Cancelled',        color: 'bg-red-100 text-red-700',      dot: 'bg-red-500' },
};

const PAY_ICONS = { cash: '💵', card: '💳', wallet: '📱', points: '⭐', mixed: '🔄' };

export default function OrdersPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [selectedOrder, setSelectedOrder] = useState(null);
  const [showAssign, setShowAssign] = useState(false);

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['admin-orders', statusFilter, search, page],
    queryFn: () => orderApi.list({
      status: statusFilter || undefined,
      search: search || undefined,
      page,
      ordering: '-created_at'
    }).then(r => r.data),
    refetchInterval: 15000, // Poll every 15s
  });

  const { data: driversData } = useQuery({
    queryKey: ['online-drivers'],
    queryFn: () => userApi.liveDrivers().then(r => r.data),
    enabled: showAssign,
  });

  const assignMutation = useMutation({
    mutationFn: ({ orderId, driverId }) => orderApi.assignDriver(orderId, driverId),
    onSuccess: () => {
      qc.invalidateQueries(['admin-orders']);
      setShowAssign(false);
      setSelectedOrder(null);
      toast.success(t('تم تعيين المندوب', 'Driver assigned'));
    },
    onError: () => toast.error(t('خطأ في التعيين', 'Assignment failed')),
  });

  const orders = data?.results || [];

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('الطلبات', 'Orders')}</h1>
          <p className="text-gray-500 text-sm">{data?.count || 0} {t('طلب', 'orders')}</p>
        </div>
        <button onClick={() => refetch()}
          className="flex items-center gap-2 text-sm text-[#2E5E99] bg-[#E7F0FA] hover:bg-[#dbeafe] px-4 py-2 rounded-xl font-medium transition-colors">
          🔄 {t('تحديث', 'Refresh')}
        </button>
      </div>

      {/* Status filter tabs */}
      <div className="flex gap-2 flex-wrap">
        {[{ key: '', ar: 'الكل', en: 'All' }, ...Object.entries(STATUS_CONFIG).map(([k, v]) => ({ key: k, ...v }))].map(s => (
          <button
            key={s.key}
            onClick={() => { setStatusFilter(s.key); setPage(1); }}
            className={`px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${
              statusFilter === s.key
                ? 'bg-[#0D2440] text-white'
                : 'bg-white text-gray-600 hover:bg-gray-100 border border-gray-200'
            }`}
          >
            {s.key && <span className={`inline-block w-2 h-2 rounded-full mr-1.5 ${s.dot}`} />}
            {lang === 'ar' ? (s.ar || 'الكل') : (s.en || 'All')}
          </button>
        ))}
      </div>

      {/* Search */}
      <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
        <input
          value={search}
          onChange={e => { setSearch(e.target.value); setPage(1); }}
          placeholder={t('🔍 ابحث برقم الطلب أو اسم العميل أو الهاتف...', '🔍 Search by order ID, customer name or phone...')}
          className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#2E5E99]"
        />
      </div>

      {/* Orders table */}
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
                  {[
                    t('رقم الطلب', 'Order ID'),
                    t('العميل', 'Customer'),
                    t('المندوب', 'Driver'),
                    t('الأصناف', 'Items'),
                    t('الدفع', 'Payment'),
                    t('المبلغ', 'Total'),
                    t('الحالة', 'Status'),
                    t('الوقت', 'Time'),
                    t('إجراءات', 'Actions'),
                  ].map(h => (
                    <th key={h} className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {orders.map(order => {
                  const sc = STATUS_CONFIG[order.status] || {};
                  return (
                    <tr key={order.id}
                        className={`hover:bg-gray-50 cursor-pointer ${order.status === 'new' ? 'bg-blue-50/30' : ''}`}
                        onClick={() => navigate(`/orders/${order.order_id}`)}>
                      <td className="px-4 py-3">
                        <span className="font-mono font-bold text-[#2E5E99] text-xs">{order.order_id}</span>
                      </td>
                      <td className="px-4 py-3 font-medium text-[#0D2440] whitespace-nowrap">{order.customer_name}</td>
                      <td className="px-4 py-3 text-gray-500 whitespace-nowrap">
                        {order.driver_name || (
                          <button
                            onClick={e => {
                              e.stopPropagation();
                              setSelectedOrder(order);
                              setShowAssign(true);
                            }}
                            className="text-xs bg-[#F97316] text-white px-2 py-1 rounded-lg font-semibold hover:bg-orange-600 transition-colors"
                          >
                            + {t('تعيين', 'Assign')}
                          </button>
                        )}
                      </td>
                      <td className="px-4 py-3 text-center font-semibold text-gray-700">{order.items_count}</td>
                      <td className="px-4 py-3 text-center text-lg">{PAY_ICONS[order.payment_method] || '💵'}</td>
                      <td className="px-4 py-3 font-bold text-[#0D2440] whitespace-nowrap">{order.total_amount} EGP</td>
                      <td className="px-4 py-3">
                        <span className={`text-xs font-semibold px-2.5 py-1 rounded-full whitespace-nowrap ${sc.color}`}>
                          {lang === 'ar' ? sc.ar : sc.en}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-gray-400 text-xs whitespace-nowrap">
                        {new Date(order.created_at).toLocaleString(lang === 'ar' ? 'ar-EG' : 'en-US', {
                          day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'
                        })}
                      </td>
                      <td className="px-4 py-3">
                        <button
                          onClick={e => { e.stopPropagation(); navigate(`/orders/${order.order_id}`); }}
                          className="text-xs text-[#2E5E99] font-semibold hover:underline whitespace-nowrap"
                        >
                          {t('عرض', 'View')} →
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {orders.length === 0 && (
              <div className="text-center py-16 text-gray-400">
                <div className="text-4xl mb-3">📦</div>
                <div>{t('لا توجد طلبات', 'No orders found')}</div>
              </div>
            )}
          </div>
        )}

        {/* Pagination */}
        {data?.count > 20 && (
          <div className="px-4 py-3 border-t border-gray-100 flex items-center justify-between">
            <span className="text-sm text-gray-500">
              {t(`${orders.length} من ${data.count}`, `${orders.length} of ${data.count}`)}
            </span>
            <div className="flex gap-2">
              <button disabled={page === 1} onClick={() => setPage(p => p - 1)}
                className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">
                {t('السابق', 'Prev')}
              </button>
              <button disabled={!data?.next} onClick={() => setPage(p => p + 1)}
                className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">
                {t('التالي', 'Next')}
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Assign Driver Modal */}
      {showAssign && selectedOrder && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-md shadow-xl">
            <h3 className="font-bold text-[#0D2440] text-lg font-serif mb-1">
              {t('تعيين مندوب', 'Assign Driver')}
            </h3>
            <p className="text-sm text-gray-500 mb-4">
              {t(`للطلب رقم ${selectedOrder.order_id}`, `Order ${selectedOrder.order_id}`)}
            </p>
            <div className="space-y-2 max-h-64 overflow-y-auto">
              {(driversData || []).filter(d => d.is_online).map(driver => (
                <button
                  key={driver.id}
                  onClick={() => assignMutation.mutate({ orderId: selectedOrder.order_id, driverId: driver.id })}
                  className="w-full flex items-center gap-3 p-3 border border-gray-200 rounded-xl hover:border-[#2E5E99] hover:bg-[#E7F0FA] transition-all text-start"
                >
                  <div className="w-9 h-9 bg-[#2E5E99] rounded-full flex items-center justify-center text-white font-bold text-sm flex-shrink-0">
                    {driver.full_name?.[0]}
                  </div>
                  <div>
                    <div className="font-semibold text-[#0D2440] text-sm">{driver.full_name}</div>
                    <div className="text-xs text-gray-400">{driver.phone} · ⭐ {driver.rating}</div>
                  </div>
                  <div className="ms-auto">
                    <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full font-semibold">
                      {t('متاح', 'Online')}
                    </span>
                  </div>
                </button>
              ))}
              {(driversData || []).filter(d => d.is_online).length === 0 && (
                <div className="text-center py-8 text-gray-400 text-sm">
                  {t('لا يوجد مناديب متاحين الآن', 'No drivers online right now')}
                </div>
              )}
            </div>
            <button
              onClick={() => { setShowAssign(false); setSelectedOrder(null); }}
              className="mt-4 w-full py-2.5 border border-gray-200 rounded-xl text-sm font-medium hover:bg-gray-50 transition-colors"
            >
              {t('إلغاء', 'Cancel')}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
