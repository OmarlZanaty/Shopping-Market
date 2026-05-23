import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend
} from 'recharts';
import { api } from '../services/api';

const COLORS = ['#2E5E99', '#F97316', '#2FBE8F', '#FBBF24', '#FB7185', '#7BA4D0'];

function StatCard({ icon, title, value, sub, color, trend }) {
  return (
    <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
      <div className="flex items-start justify-between mb-3">
        <div className={`w-11 h-11 ${color} rounded-xl flex items-center justify-center text-xl`}>{icon}</div>
        {trend !== undefined && (
          <span className={`text-xs font-semibold px-2 py-1 rounded-full ${trend >= 0 ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
            {trend >= 0 ? '↑' : '↓'} {Math.abs(trend)}%
          </span>
        )}
      </div>
      <div className="text-2xl font-bold text-[#0D2440] font-serif">{value}</div>
      <div className="text-sm text-gray-500 mt-1">{title}</div>
      {sub && <div className="text-xs text-gray-400 mt-0.5">{sub}</div>}
    </div>
  );
}

export default function Dashboard() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;

  const { data: summary, isLoading } = useQuery({
    queryKey: ['dashboard-summary'],
    queryFn: () => api.get('/analytics/dashboard/').then(r => r.data),
    refetchInterval: 30000,
  });

  const { data: salesData } = useQuery({
    queryKey: ['sales-daily'],
    queryFn: () => api.get('/analytics/sales/daily/?days=14').then(r => r.data),
  });

  const { data: categoryData } = useQuery({
    queryKey: ['sales-categories'],
    queryFn: () => api.get('/analytics/sales/categories/?days=30').then(r => r.data),
  });

  const { data: recentOrders } = useQuery({
    queryKey: ['recent-orders'],
    queryFn: () => api.get('/orders/admin/all/?ordering=-created_at&page_size=8').then(r => r.data),
  });

  if (isLoading) return (
    <div className="flex items-center justify-center h-full">
      <div className="animate-spin w-8 h-8 border-4 border-[#2E5E99] border-t-transparent rounded-full" />
    </div>
  );

  const today = summary?.today || {};
  const month = summary?.month || {};

  const statusColors = {
    new: 'bg-[#E7F0FA] text-[#2E5E99]',
    preparing: 'bg-yellow-100 text-yellow-800',
    out_for_delivery: 'bg-orange-100 text-orange-800',
    delivered: 'bg-green-100 text-green-700',
    cancelled: 'bg-red-100 text-red-700',
  };
  const statusLabels = {
    new: t('جديد', 'New'),
    preparing: t('يتم التحضير', 'Preparing'),
    out_for_delivery: t('خرج للتوصيل', 'Out for Delivery'),
    delivered: t('تم التسليم', 'Delivered'),
    cancelled: t('ملغي', 'Cancelled'),
  };

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">
          {t('لوحة التحكم', 'Dashboard')}
        </h1>
        <p className="text-gray-500 text-sm mt-1">{t('نظرة عامة على النظام', 'System Overview')}</p>
      </div>

      {/* KPI Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard icon="📦" title={t('طلبات اليوم', "Today's Orders")}
          value={today.total_orders || 0} color="bg-[#EFF6FF]"
          sub={`${today.delivered || 0} ${t('مسلم', 'delivered')}`} />
        <StatCard icon="💰" title={t('إيرادات اليوم', "Today's Revenue")}
          value={`${Number(today.revenue || 0).toFixed(0)} EGP`} color="bg-[#ECFDF5]" />
        <StatCard icon="🛵" title={t('مناديب أونلاين', 'Online Drivers')}
          value={summary?.active_drivers || 0} color="bg-[#FFF7ED]"
          sub={t('يتحرك الآن', 'Active now')} />
        <StatCard icon="⏳" title={t('طلبات معلقة', 'Pending Orders')}
          value={summary?.pending_orders || 0} color="bg-[#FFF0F3]"
          sub={t('تحتاج انتباه', 'Need attention')} />
        <StatCard icon="👥" title={t('عملاء جدد اليوم', 'New Customers Today')}
          value={today.new_customers || 0} color="bg-[#F5F3FF]" />
        <StatCard icon="📊" title={t('إيرادات الشهر', 'Month Revenue')}
          value={`${Number(month.revenue || 0).toFixed(0)} EGP`} color="bg-[#EFF6FF]" />
        <StatCard icon="🛒" title={t('متوسط قيمة الطلب', 'Avg Order Value')}
          value={`${Number(month.avg_order_value || 0).toFixed(1)} EGP`} color="bg-[#ECFDF5]" />
        <StatCard icon="⚠️" title={t('مخزون منخفض', 'Low Stock')}
          value={summary?.low_stock_products || 0} color="bg-[#FFF7ED]"
          sub={t('منتج يحتاج طلب', 'products need reorder')} />
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Sales Chart */}
        <div className="lg:col-span-2 bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
          <h2 className="font-bold text-[#0D2440] mb-4 font-serif">
            {t('المبيعات اليومية (14 يوم)', 'Daily Sales (14 days)')}
          </h2>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={salesData || []}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis dataKey="day" tick={{ fontSize: 10 }} />
              <YAxis tick={{ fontSize: 10 }} />
              <Tooltip formatter={(v) => `${v} EGP`} />
              <Line type="monotone" dataKey="revenue" stroke="#2E5E99" strokeWidth={2.5}
                dot={{ fill: '#2E5E99', r: 4 }} />
              <Line type="monotone" dataKey="orders" stroke="#F97316" strokeWidth={2}
                dot={{ fill: '#F97316', r: 3 }} />
            </LineChart>
          </ResponsiveContainer>
        </div>

        {/* Category pie */}
        <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
          <h2 className="font-bold text-[#0D2440] mb-4 font-serif">
            {t('المبيعات بالقسم', 'Sales by Category')}
          </h2>
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie data={categoryData?.slice(0, 6) || []}
                dataKey="total_revenue"
                nameKey={lang === 'ar' ? 'product__categories__name_ar' : 'product__categories__name_en'}
                cx="50%" cy="50%" outerRadius={80} label={false}>
                {(categoryData || []).map((_, i) => (
                  <Cell key={i} fill={COLORS[i % COLORS.length]} />
                ))}
              </Pie>
              <Legend iconSize={8} wrapperStyle={{ fontSize: 10 }} />
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Recent Orders */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-5 border-b border-gray-100 flex items-center justify-between">
          <h2 className="font-bold text-[#0D2440] font-serif">{t('أحدث الطلبات', 'Recent Orders')}</h2>
          <a href="/orders" className="text-[#2E5E99] text-sm font-medium hover:underline">
            {t('عرض الكل', 'View all')} →
          </a>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  {t('رقم الطلب', 'Order ID')}
                </th>
                <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  {t('العميل', 'Customer')}
                </th>
                <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  {t('الحالة', 'Status')}
                </th>
                <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  {t('المبلغ', 'Amount')}
                </th>
                <th className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  {t('الوقت', 'Time')}
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {(recentOrders?.results || []).map(order => (
                <tr key={order.id} className="hover:bg-gray-50 cursor-pointer"
                    onClick={() => window.location.href = `/orders/${order.order_id}`}>
                  <td className="px-4 py-3 font-mono font-semibold text-[#2E5E99]">
                    {order.order_id}
                  </td>
                  <td className="px-4 py-3 text-[#0D2440]">{order.customer_name}</td>
                  <td className="px-4 py-3">
                    <span className={`text-xs font-semibold px-2 py-1 rounded-full ${statusColors[order.status] || ''}`}>
                      {statusLabels[order.status] || order.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 font-bold text-[#0D2440]">{order.total_amount} EGP</td>
                  <td className="px-4 py-3 text-gray-400 text-xs">
                    {new Date(order.created_at).toLocaleTimeString(lang === 'ar' ? 'ar-EG' : 'en-US')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
