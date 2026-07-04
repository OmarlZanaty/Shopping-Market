import React, { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { notificationApi } from '../services/api';
import toast from 'react-hot-toast';

/**
 * Smart loyalty-points control panel.
 *
 * Reads/writes the loyalty_* AppSettings keys (see apps/orders/loyalty.py).
 * Admins set the earn ratio ("X points for every Y EGP") and the redeem ratio
 * ("Z points = W EGP discount") in plain language, with a live preview of the
 * resulting economics.
 */
const KEYS = {
  loyalty_enabled:            '1',
  loyalty_earn_points:        '1',
  loyalty_earn_per_egp:       '1',
  loyalty_redeem_points:      '20',
  loyalty_redeem_egp:         '1',
  loyalty_min_redeem:         '0',
  loyalty_max_redeem_percent: '100',
};

export default function LoyaltyPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => (lang === 'ar' ? ar : en);
  const qc = useQueryClient();
  const [form, setForm] = useState(KEYS);

  const { data: settings, isLoading } = useQuery({
    queryKey: ['app-settings'],
    queryFn: () => notificationApi.settings().then((r) => r.data),
  });

  // Hydrate the form from the fetched settings list once loaded.
  useEffect(() => {
    const list = Array.isArray(settings) ? settings : settings?.results || [];
    if (!list.length) return;
    const byKey = Object.fromEntries(list.map((s) => [s.key, s.value]));
    setForm((f) => {
      const next = { ...f };
      for (const k of Object.keys(KEYS)) if (byKey[k] != null) next[k] = byKey[k];
      return next;
    });
  }, [settings]);

  const save = useMutation({
    mutationFn: () =>
      notificationApi.bulkSettings(
        Object.entries(form).map(([key, value]) => ({ key, value: String(value) })),
      ),
    onSuccess: () => {
      qc.invalidateQueries(['app-settings']);
      toast.success(t('تم حفظ إعدادات النقاط', 'Loyalty settings saved'));
    },
    onError: (e) => toast.error(e?.message || t('فشل الحفظ', 'Save failed')),
  });

  const set = (k) => (e) =>
    setForm((f) => ({ ...f, [k]: e.target.value }));
  const num = (k) => Number(form[k]) || 0;

  const enabled = String(form.loyalty_enabled) === '1';
  const egpPerPoint =
    num('loyalty_redeem_points') > 0
      ? num('loyalty_redeem_egp') / num('loyalty_redeem_points')
      : 0;
  // Points earned on a sample 100 EGP order.
  const earnOn100 =
    num('loyalty_earn_per_egp') > 0
      ? Math.floor(100 / num('loyalty_earn_per_egp')) * num('loyalty_earn_points')
      : 0;

  if (isLoading) return <div className="p-6 text-gray-400">{t('جارِ التحميل…', 'Loading…')}</div>;

  const card = 'bg-white rounded-2xl shadow-sm border border-gray-100 p-5 space-y-4';
  const lbl = 'block text-sm font-semibold text-[#0D2440] mb-1';
  const inp = 'border border-gray-200 focus:border-[#2E5E99] rounded-lg px-3 py-2 text-sm outline-none w-28 text-center';
  const hint = 'text-xs text-gray-400';

  return (
    <div className="p-6 space-y-5 max-w-3xl">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-[#0D2440] font-serif">
          {t('نظام نقاط الولاء ⭐', 'Loyalty Points ⭐')}
        </h1>
        <button
          onClick={() => save.mutate()}
          disabled={save.isPending}
          className="bg-[#FF6B35] text-white px-5 py-2 rounded-xl text-sm font-bold shadow hover:opacity-90 disabled:opacity-50"
        >
          {save.isPending ? t('جارِ الحفظ…', 'Saving…') : t('حفظ التغييرات', 'Save changes')}
        </button>
      </div>

      {/* Master toggle */}
      <div className={card}>
        <label className="flex items-center justify-between cursor-pointer">
          <div>
            <div className="font-semibold text-[#0D2440]">{t('تفعيل النظام', 'Enable loyalty')}</div>
            <div className={hint}>{t('إيقافه يمنع كسب واستبدال النقاط', 'Turning off stops earning and redeeming')}</div>
          </div>
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => setForm((f) => ({ ...f, loyalty_enabled: e.target.checked ? '1' : '0' }))}
            className="w-5 h-5 accent-[#FF6B35]"
          />
        </label>
      </div>

      {/* Earn */}
      <div className={card}>
        <div className="font-bold text-[#0D2440]">{t('كسب النقاط', 'Earning points')}</div>
        <div className="flex flex-wrap items-end gap-4">
          <div>
            <label className={lbl}>{t('عدد النقاط', 'Points')}</label>
            <input type="number" min="0" value={form.loyalty_earn_points} onChange={set('loyalty_earn_points')} className={inp} />
          </div>
          <div className="pb-2 text-gray-500 text-sm">{t('نقطة لكل', 'points per')}</div>
          <div>
            <label className={lbl}>{t('قيمة الإنفاق (ج)', 'EGP spent')}</label>
            <input type="number" min="1" value={form.loyalty_earn_per_egp} onChange={set('loyalty_earn_per_egp')} className={inp} />
          </div>
        </div>
        <div className="bg-orange-50 text-[#FF6B35] rounded-lg px-4 py-2 text-sm font-semibold inline-block">
          {t(
            `طلب بقيمة 100 ج ← ${earnOn100} نقطة`,
            `A 100 EGP order → ${earnOn100} points`,
          )}
        </div>
      </div>

      {/* Redeem */}
      <div className={card}>
        <div className="font-bold text-[#0D2440]">{t('استبدال النقاط', 'Redeeming points')}</div>
        <div className="flex flex-wrap items-end gap-4">
          <div>
            <label className={lbl}>{t('عدد النقاط', 'Points')}</label>
            <input type="number" min="1" value={form.loyalty_redeem_points} onChange={set('loyalty_redeem_points')} className={inp} />
          </div>
          <div className="pb-2 text-gray-500 text-sm">{t('نقطة =', 'points =')}</div>
          <div>
            <label className={lbl}>{t('خصم (ج)', 'EGP discount')}</label>
            <input type="number" min="0" step="0.5" value={form.loyalty_redeem_egp} onChange={set('loyalty_redeem_egp')} className={inp} />
          </div>
        </div>
        <div className="bg-green-50 text-green-700 rounded-lg px-4 py-2 text-sm font-semibold inline-block">
          {t(
            `النقطة الواحدة = ${egpPerPoint.toFixed(3)} ج`,
            `1 point = ${egpPerPoint.toFixed(3)} EGP`,
          )}
        </div>
        <div className="flex flex-wrap items-end gap-6 pt-2">
          <div>
            <label className={lbl}>{t('أقل عدد نقاط للاستبدال', 'Min points to redeem')}</label>
            <input type="number" min="0" value={form.loyalty_min_redeem} onChange={set('loyalty_min_redeem')} className={inp} />
          </div>
          <div>
            <label className={lbl}>{t('أقصى خصم من الطلب (%)', 'Max discount of order (%)')}</label>
            <input type="number" min="0" max="100" value={form.loyalty_max_redeem_percent} onChange={set('loyalty_max_redeem_percent')} className={inp} />
          </div>
        </div>
      </div>
    </div>
  );
}
