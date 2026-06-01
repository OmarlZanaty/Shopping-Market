import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts';
import { analyticsApi } from '../../services/api';

const COLORS = ['#2E5E99', '#F97316', '#2FBE8F', '#FBBF24', '#FB7185', '#7BA4D0', '#0D2440', '#FB923C'];

export default function SalesPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const [days, setDays] = useState(30);

  const { data: daily } = useQuery({ queryKey: ['sales-daily', days], queryFn: () => analyticsApi.salesDaily(days).then(r => r.data) });
  const { data: products } = useQuery({ queryKey: ['sales-products', days], queryFn: () => analyticsApi.salesProducts(days).then(r => r.data) });
  const { data: categories } = useQuery({ queryKey: ['sales-categories', days], queryFn: () => analyticsApi.salesCategories(days).then(r => r.data) });
  const { data: peakHours } = useQuery({ queryKey: ['peak-hours', days], queryFn: () => analyticsApi.peakHours(days).then(r => r.data) });

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div><h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('تقارير المبيعات','Sales Reports')}</h1><p className="text-gray-500 text-sm">{t('تحليل المبيعات والإيرادات','Revenue and sales analysis')}</p></div>
        <div className="flex gap-2">
          {[7,14,30,90].map(d => <button key={d} onClick={() => setDays(d)} className={`px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${days===d ? 'bg-[#0D2440] text-white' : 'bg-white border border-gray-200 text-gray-600 hover:bg-gray-50'}`}>{d} {t('يوم','d')}</button>)}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Daily Revenue Line */}
        <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100 lg:col-span-2">
          <h2 className="font-bold text-[#0D2440] font-serif mb-4">{t('الإيرادات اليومية','Daily Revenue')}</h2>
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={daily || []}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis dataKey="day" tick={{ fontSize: 10 }} />
              <YAxis tick={{ fontSize: 10 }} />
              <Tooltip formatter={(v, n) => [`${v} EGP`, n === 'revenue' ? t('الإيرادات','Revenue') : t('الطلبات','Orders')]} />
              <Legend />
              <Line type="monotone" dataKey="revenue" name={t('الإيرادات','Revenue')} stroke="#2E5E99" strokeWidth={2.5} dot={{ fill: '#2E5E99', r: 3 }} />
              <Line type="monotone" dataKey="orders" name={t('الطلبات','Orders')} stroke="#F97316" strokeWidth={2} dot={{ fill: '#F97316', r: 3 }} />
            </LineChart>
          </ResponsiveContainer>
        </div>

        {/* Top Products */}
        <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
          <h2 className="font-bold text-[#0D2440] font-serif mb-4">{t('أكثر المنتجات مبيعاً','Top Selling Products')}</h2>
          <div dir="ltr">
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={(products || []).slice(0,8)} layout="vertical" margin={{ top: 5, right: 20, left: 10, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis type="number" tick={{ fontSize: 9 }} />
              <YAxis type="category" dataKey="product__name_ar" tick={{ fontSize: 10 }} width={150} interval={0} />
              <Tooltip formatter={(v) => [`${v} EGP`, t('الإيرادات','Revenue')]} />
              <Bar dataKey="total_revenue" fill="#2E5E99" radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
          </div>
        </div>

        {/* Categories Pie */}
        <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
          <h2 className="font-bold text-[#0D2440] font-serif mb-4">{t('المبيعات بالقسم','Sales by Category')}</h2>
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie data={(categories || []).slice(0,6)} dataKey="total_revenue" nameKey={lang==='ar'?'product__categories__name_ar':'product__categories__name_en'} cx="50%" cy="50%" outerRadius={80} label={({percent}) => `${(percent*100).toFixed(0)}%`}>
                {(categories || []).map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
              </Pie>
              <Legend iconSize={8} wrapperStyle={{fontSize:10}} />
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </div>

        {/* Peak Hours */}
        <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100 lg:col-span-2">
          <h2 className="font-bold text-[#0D2440] font-serif mb-4">{t('ساعات الذروة','Peak Hours')}</h2>
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={peakHours || []}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis dataKey="hour" tick={{ fontSize: 10 }} tickFormatter={h => `${h}:00`} />
              <YAxis tick={{ fontSize: 10 }} />
              <Tooltip labelFormatter={h => `${h}:00 - ${h+1}:00`} formatter={(v) => [v, t('طلب','Orders')]} />
              <Bar dataKey="count" fill="#F97316" radius={[4,4,0,0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
}
