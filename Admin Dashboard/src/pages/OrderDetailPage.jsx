import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext, useParams, useNavigate } from 'react-router-dom';
import { orderApi } from '../services/api';

const STATUS_LABELS = { new:{ar:'جديد',en:'New',color:'bg-blue-100 text-blue-800'}, preparing:{ar:'يتم التحضير',en:'Preparing',color:'bg-yellow-100 text-yellow-800'}, out_for_delivery:{ar:'خرج للتوصيل',en:'Out for Delivery',color:'bg-orange-100 text-orange-800'}, delivered:{ar:'تم التسليم',en:'Delivered',color:'bg-green-100 text-green-800'}, cancelled:{ar:'ملغي',en:'Cancelled',color:'bg-red-100 text-red-700'} };
const PAY_ICONS = { cash:'💵', card:'💳', wallet:'📱', points:'⭐', mixed:'🔄' };

export default function OrderDetailPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const { orderId } = useParams();
  const navigate = useNavigate();

  // Detail endpoint returns the { success, data: {...order} } envelope, so unwrap r.data.data.
  const { data: order, isLoading } = useQuery({ queryKey: ['order-detail', orderId], queryFn: () => orderApi.get(orderId).then(r => r.data?.data ?? r.data) });

  if (isLoading) return <div className="flex items-center justify-center h-64"><div className="animate-spin w-8 h-8 border-4 border-[#2E5E99] border-t-transparent rounded-full" /></div>;
  if (!order) return <div className="p-6 text-center text-gray-400">Order not found</div>;

  const sc = STATUS_LABELS[order.status] || {};
  const adjustments = order.adjustments || [];
  const items = order.items || [];

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-5">
      <div className="flex items-center gap-4">
        <button onClick={() => navigate('/orders')} className="w-9 h-9 bg-white border border-gray-200 rounded-xl flex items-center justify-center hover:bg-gray-50">←</button>
        <div>
          <h1 className="text-xl font-bold text-[#0D2440] font-serif font-mono">#{order.order_id}</h1>
          <p className="text-xs text-gray-400">{new Date(order.created_at).toLocaleString(lang === 'ar' ? 'ar-EG' : 'en-US')}</p>
        </div>
        <span className={`ms-auto text-xs font-bold px-3 py-1.5 rounded-full ${sc.color}`}>{lang === 'ar' ? sc.ar : sc.en}</span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Customer */}
        <div className="bg-white rounded-2xl p-5 border border-gray-100 shadow-sm">
          <h3 className="font-bold text-[#0D2440] text-sm mb-3 flex items-center gap-2">👤 {t('العميل', 'Customer')}</h3>
          <div className="space-y-1 text-sm"><div className="font-semibold">{order.delivery_name || '—'}</div><div className="text-gray-500">{order.delivery_phone}</div><div className="text-gray-500 text-xs">{order.delivery_address}</div>{order.building_number && <div className="text-xs text-gray-400">عمارة {order.building_number} - دور {order.floor_number} - شقة {order.apartment_number}</div>}{order.landmark && <div className="text-xs text-[#7BA4D0]">{order.landmark}</div>}</div>
        </div>
        {/* Agent (preparer + driver) */}
        <div className="bg-white rounded-2xl p-5 border border-gray-100 shadow-sm">
          <h3 className="font-bold text-[#0D2440] text-sm mb-3 flex items-center gap-2">🛵 {t('الموظف', 'Agent')}</h3>
          {(order.preparer_info || order.driver_info) ? (
            <div className="space-y-3 text-sm">
              {order.preparer_info && (
                <div><div className="text-xs text-gray-400">{t('محضّر الطلب', 'Preparer')}</div><div className="font-semibold">{order.preparer_info.name}</div><div className="text-gray-500">{order.preparer_info.phone}</div></div>
              )}
              {order.driver_info && (
                <div><div className="text-xs text-gray-400">{t('مندوب التوصيل', 'Driver')}</div><div className="font-semibold">{order.driver_info.name}</div><div className="text-gray-500">{order.driver_info.phone}</div><div className="flex items-center gap-1 text-[#FBBF24]">⭐ <span className="text-gray-700 text-xs">{order.driver_info.rating}</span></div></div>
              )}
            </div>
          ) : (
            <p className="text-gray-400 text-sm">{t('لم يتم التعيين', 'Not assigned yet')}</p>
          )}
        </div>
        {/* Payment */}
        <div className="bg-white rounded-2xl p-5 border border-gray-100 shadow-sm">
          <h3 className="font-bold text-[#0D2440] text-sm mb-3 flex items-center gap-2">💰 {t('الدفع', 'Payment')}</h3>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between"><span className="text-gray-500">{t('الإجمالي','Total')}</span><span className="font-bold text-[#2E5E99]">{order.total_amount} EGP</span></div>
            <div className="flex justify-between"><span className="text-gray-500">{t('طريقة الدفع','Method')}</span><span>{PAY_ICONS[order.payment_method]} {order.payment_method}</span></div>
            <div className="flex justify-between"><span className="text-gray-500">{t('الحالة','Status')}</span><span className={`text-xs font-bold px-2 py-0.5 rounded-full ${order.payment_status === 'paid' ? 'bg-green-100 text-green-700' : 'bg-yellow-100 text-yellow-700'}`}>{order.payment_status}</span></div>
            {order.customer_notes && <div className="bg-[#FFF7ED] rounded-lg p-2 text-xs text-[#92400e] border border-[#fed7aa]">📝 {order.customer_notes}</div>}
          </div>
        </div>
      </div>

      {/* Items */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-4 border-b border-gray-100 font-bold text-[#0D2440] font-serif">{t('الأصناف', 'Items')} ({items.length})</div>
        <table className="w-full text-sm">
          <thead className="bg-gray-50"><tr>{['المنتج/Product','الكمية/Qty','السعر/Price','الإجمالي/Total','الحالة/Status'].map(h => <th key={h} className="px-4 py-2.5 text-start text-xs font-semibold text-gray-500 uppercase">{h}</th>)}</tr></thead>
          <tbody className="divide-y divide-gray-50">
            {items.map(item => (
              <tr key={item.id} className={item.added_by_driver ? 'bg-orange-50' : ''}>
                <td className="px-4 py-3"><div className="font-medium text-[#0D2440]">{item.product_name_ar}</div><div className="text-xs text-gray-400 font-mono">{item.product_barcode}</div>{item.added_by_driver && <span className="text-xs bg-orange-100 text-orange-700 px-1.5 py-0.5 rounded font-semibold">أضافه المندوب</span>}</td>
                <td className="px-4 py-3">{item.delivered_quantity || item.quantity}<span className="text-gray-400 text-xs"> {item.delivered_quantity && item.delivered_quantity !== item.quantity ? `(طلب ${item.quantity})` : ''}</span></td>
                <td className="px-4 py-3">{item.final_unit_price || item.unit_price} EGP{item.final_unit_price && item.final_unit_price !== item.unit_price && <span className="text-xs text-gray-400 line-through ms-1">{item.unit_price}</span>}</td>
                <td className="px-4 py-3 font-bold text-[#2E5E99]">{((item.final_unit_price || item.unit_price) * (item.delivered_quantity || item.quantity)).toFixed(2)} EGP</td>
                <td className="px-4 py-3"><span className={`text-xs font-semibold px-2 py-1 rounded-full ${item.status === 'collected' ? 'bg-green-100 text-green-700' : item.status === 'rejected' ? 'bg-red-100 text-red-600' : 'bg-gray-100 text-gray-600'}`}>{item.status}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="p-4 border-t border-gray-100 flex justify-end gap-8 text-sm">
          <span className="text-gray-500">{t('المنتجات','Subtotal')}: <strong>{order.subtotal} EGP</strong></span>
          <span className="text-gray-500">{t('التوصيل','Delivery')}: <strong>{order.delivery_fee} EGP</strong></span>
          {order.total_savings > 0 && <span className="text-[#2FBE8F]">{t('الوفر','Savings')}: <strong>-{order.total_savings} EGP</strong></span>}
          <span className="font-bold text-[#0D2440] text-base">{t('الإجمالي','Total')}: {order.total_amount} EGP</span>
        </div>
      </div>

      {/* Adjustments log */}
      {adjustments.length > 0 && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="p-4 border-b border-gray-100 font-bold text-[#0D2440] font-serif">{t('سجل التعديلات', 'Adjustments Log')} ({adjustments.length})</div>
          <div className="divide-y divide-gray-50">
            {adjustments.map(adj => (
              <div key={adj.id} className="px-4 py-3 flex items-center gap-3 text-sm">
                <span className="text-lg">{adj.adjustment_type === 'price_change' ? '💰' : adj.adjustment_type === 'substitute' ? '🔄' : adj.adjustment_type === 'item_added' ? '➕' : '✏️'}</span>
                <div className="flex-1"><div className="font-medium text-[#0D2440]">{adj.adjustment_type}</div><div className="text-xs text-gray-400">{adj.old_value} → {adj.new_value} {adj.reason && `· ${adj.reason}`}</div></div>
                <span className={`text-xs font-semibold px-2 py-1 rounded-full ${adj.customer_approved === true ? 'bg-green-100 text-green-700' : adj.customer_approved === false ? 'bg-red-100 text-red-600' : 'bg-yellow-100 text-yellow-700'}`}>
                  {adj.customer_approved === true ? '✅ قبل' : adj.customer_approved === false ? '❌ رفض' : '⏳ معلق'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
