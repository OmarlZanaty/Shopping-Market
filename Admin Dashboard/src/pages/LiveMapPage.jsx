import React, { useState, useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { userApi, orderApi } from '../services/api';

export default function LiveMapPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const [selectedDriver, setSelectedDriver] = useState(null);

  const { data: drivers, refetch: refetchDrivers } = useQuery({
    queryKey: ['live-drivers'],
    queryFn: () => userApi.liveDrivers().then(r => r.data),
    refetchInterval: 10000,
  });

  const { data: pendingOrders } = useQuery({
    queryKey: ['pending-orders-live'],
    queryFn: () => orderApi.list({ status: 'new', page_size: 20 }).then(r => r.data),
    refetchInterval: 10000,
  });

  const driversArr = Array.isArray(drivers) ? drivers : [];
  const onlineDrivers = driversArr.filter(d => d.is_online);
  const offlineDrivers = driversArr.filter(d => !d.is_online);
  const pending = pendingOrders?.results || [];

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-[#0D2440] font-serif flex items-center gap-2">
            🗺️ {t('الخريطة المباشرة', 'Live Map')}
          </h1>
          <p className="text-gray-500 text-sm">{t('متابعة المناديب والطلبات في الوقت الحقيقي', 'Real-time driver and order tracking')}</p>
        </div>
        <button onClick={() => refetchDrivers()}
          className="flex items-center gap-2 bg-[#E7F0FA] text-[#2E5E99] px-4 py-2 rounded-xl text-sm font-semibold hover:bg-[#dbeafe] transition-colors">
          🔄 {t('تحديث', 'Refresh')}
        </button>
      </div>

      {/* Stats bar */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[
          { label: t('مناديب متاحون', 'Online Drivers'), val: onlineDrivers.length, color: 'bg-[#ECFDF5]', text: 'text-[#2FBE8F]', icon: '🟢' },
          { label: t('غير متاحون', 'Offline Drivers'), val: offlineDrivers.length, color: 'bg-gray-50', text: 'text-gray-500', icon: '⚫' },
          { label: t('طلبات جديدة', 'New Orders'), val: pending.length, color: 'bg-[#FFF0F3]', text: 'text-[#FB7185]', icon: '🔴' },
          { label: t('قيد التوصيل', 'In Delivery'), val: driversArr.filter(d => d.is_online).length, color: 'bg-[#FFF7ED]', text: 'text-[#F97316]', icon: '🛵' },
        ].map(s => (
          <div key={s.label} className={`${s.color} rounded-2xl p-4 border border-gray-100`}>
            <div className="flex items-center gap-2 mb-1">
              <span>{s.icon}</span>
              <span className={`text-2xl font-bold font-serif ${s.text}`}>{s.val}</span>
            </div>
            <div className="text-gray-500 text-xs">{s.label}</div>
          </div>
        ))}
      </div>

      {/* Map placeholder + driver list */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Map area */}
        <div className="lg:col-span-2 bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <div className="bg-gradient-to-br from-[#E7F0FA] to-[#dbeafe] h-96 flex items-center justify-center relative">
            <div className="text-center">
              <div className="text-6xl mb-4">🗺️</div>
              <div className="font-bold text-[#0D2440] text-lg font-serif">{t('خريطة جوجل المباشرة', 'Google Maps Live View')}</div>
              <p className="text-gray-500 text-sm mt-2 max-w-xs">
                {t('في التطبيق الحقيقي تظهر هنا خريطة جوجل مع مواقع جميع المناديب في الوقت الفعلي',
                   'In production, Google Maps shows all driver positions in real-time via WebSocket')}
              </p>
              <div className="mt-4 flex gap-2 justify-center flex-wrap">
                {onlineDrivers.slice(0,4).map(d => (
                  <div key={d.id} className="bg-white border border-[#2E5E99] rounded-xl px-3 py-1.5 text-xs font-semibold text-[#2E5E99] flex items-center gap-1">
                    🛵 {d.full_name}
                  </div>
                ))}
              </div>
            </div>
            {/* Decorative driver pins */}
            <div className="absolute top-8 left-12 w-10 h-10 bg-[#2FBE8F] rounded-full flex items-center justify-center text-white text-lg shadow-lg">🛵</div>
            <div className="absolute top-24 right-16 w-10 h-10 bg-[#F97316] rounded-full flex items-center justify-center text-white text-lg shadow-lg">🛵</div>
            <div className="absolute bottom-16 left-1/3 w-10 h-10 bg-[#2E5E99] rounded-full flex items-center justify-center text-white text-lg shadow-lg">🛵</div>
          </div>
          <div className="p-4 border-t border-gray-100">
            <div className="flex gap-4 text-xs text-gray-500">
              <span className="flex items-center gap-1"><span className="w-3 h-3 bg-[#2FBE8F] rounded-full inline-block"></span> {t('متاح', 'Online')}</span>
              <span className="flex items-center gap-1"><span className="w-3 h-3 bg-[#F97316] rounded-full inline-block"></span> {t('قيد التوصيل', 'Delivering')}</span>
              <span className="flex items-center gap-1"><span className="w-3 h-3 bg-gray-300 rounded-full inline-block"></span> {t('غير متاح', 'Offline')}</span>
            </div>
          </div>
        </div>

        {/* Drivers sidebar */}
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden flex flex-col">
          <div className="p-4 border-b border-gray-100">
            <h3 className="font-bold text-[#0D2440] font-serif">{t('المناديب', 'Drivers')} ({driversArr.length})</h3>
          </div>
          <div className="flex-1 overflow-y-auto divide-y divide-gray-50">
            {driversArr.map(driver => (
              <div key={driver.id}
                onClick={() => setSelectedDriver(selectedDriver?.id === driver.id ? null : driver)}
                className={`p-4 cursor-pointer hover:bg-gray-50 transition-colors ${selectedDriver?.id === driver.id ? 'bg-[#E7F0FA]' : ''}`}>
                <div className="flex items-center gap-3">
                  <div className="relative flex-shrink-0">
                    <div className="w-10 h-10 bg-[#2E5E99] rounded-full flex items-center justify-center text-white font-bold">
                      {driver.full_name?.[0]}
                    </div>
                    <span className={`absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full border-2 border-white ${driver.is_online ? 'bg-[#2FBE8F]' : 'bg-gray-300'}`} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-[#0D2440] text-sm truncate">{driver.full_name}</div>
                    <div className="text-xs text-gray-400">{driver.phone}</div>
                  </div>
                  <div className="text-right flex-shrink-0">
                    <div className="flex items-center gap-0.5 justify-end">
                      <span className="text-[#FBBF24] text-xs">⭐</span>
                      <span className="text-xs font-bold text-[#0D2440]">{driver.rating}</span>
                    </div>
                    <div className={`text-xs font-semibold ${driver.is_online ? 'text-[#2FBE8F]' : 'text-gray-400'}`}>
                      {driver.is_online ? t('متاح', 'Online') : t('غير متاح', 'Offline')}
                    </div>
                  </div>
                </div>
                {selectedDriver?.id === driver.id && (
                  <div className="mt-3 pt-3 border-t border-[#dbeafe] grid grid-cols-2 gap-2 text-xs">
                    <div className="bg-white rounded-lg p-2 text-center border border-gray-100">
                      <div className="font-bold text-[#2E5E99]">{driver.total_deliveries || 0}</div>
                      <div className="text-gray-400">{t('توصيلات', 'Deliveries')}</div>
                    </div>
                    <div className="bg-white rounded-lg p-2 text-center border border-gray-100">
                      <div className="font-bold text-[#F97316]">{driver.cash_on_hand || 0} EGP</div>
                      <div className="text-gray-400">{t('كاش', 'Cash')}</div>
                    </div>
                  </div>
                )}
              </div>
            ))}
            {driversArr.length === 0 && (
              <div className="text-center py-12 text-gray-400">
                <div className="text-4xl mb-2">🛵</div>
                <div className="text-sm">{t('لا يوجد مناديب مسجلون', 'No drivers registered')}</div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Pending orders waiting assignment */}
      {pending.length > 0 && (
        <div className="bg-white rounded-2xl shadow-sm border border-[#FB7185] overflow-hidden">
          <div className="p-4 border-b border-gray-100 flex items-center gap-2">
            <span className="animate-pulse text-[#FB7185] text-xl">🔴</span>
            <h3 className="font-bold text-[#0D2440] font-serif">{t('طلبات تنتظر التعيين', 'Orders Awaiting Assignment')} ({pending.length})</h3>
          </div>
          <div className="divide-y divide-gray-50">
            {pending.slice(0,5).map(order => (
              <div key={order.id} className="px-4 py-3 flex items-center gap-3">
                <div className="font-mono text-sm font-bold text-[#2E5E99]">#{order.order_id}</div>
                <div className="flex-1">
                  <div className="font-semibold text-[#0D2440] text-sm">{order.customer_name}</div>
                  <div className="text-xs text-gray-400">
                    {new Date(order.created_at).toLocaleTimeString(lang === 'ar' ? 'ar-EG' : 'en-US')}
                  </div>
                </div>
                <div className="font-bold text-[#0D2440]">{order.total_amount} EGP</div>
                <a href={`/orders/${order.order_id}`} className="bg-[#F97316] text-white px-3 py-1.5 rounded-lg text-xs font-bold hover:bg-orange-600 transition-colors">
                  {t('تعيين', 'Assign')}
                </a>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
