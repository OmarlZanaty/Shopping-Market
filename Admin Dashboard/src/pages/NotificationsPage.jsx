import React, { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { notificationApi } from '../services/api';
import toast from 'react-hot-toast';

export default function NotificationsPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const [form, setForm] = useState({ title_ar:'', title_en:'', body_ar:'', body_en:'', target:'all' });

  const sendMutation = useMutation({
    mutationFn: (d) => notificationApi.send(d),
    onSuccess: (r) => { toast.success(t(`تم الإرسال لـ ${r.data?.sent || 0} مستخدم`, `Sent to ${r.data?.sent || 0} users`)); setForm({ title_ar:'', title_en:'', body_ar:'', body_en:'', target:'all' }); },
    onError: () => toast.error(t('حدث خطأ','Error sending')),
  });

  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none transition-colors';
  const lbl = 'text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5';

  return (
    <div className="p-6 max-w-2xl mx-auto space-y-5">
      <div><h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('إرسال إشعار','Send Notification')}</h1><p className="text-gray-500 text-sm mt-1">{t('إرسال إشعارات فورية للعملاء والمناديب','Send push notifications to customers and drivers')}</p></div>

      <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm space-y-4">
        <div>
          <label className={lbl}>{t('الهدف','Target Audience')}</label>
          <div className="flex gap-3">
            {[['all', t('جميع العملاء','All Customers')], ['drivers', t('المناديب','Drivers')]].map(([val, lbText]) => (
              <button key={val} onClick={() => setForm(f => ({...f, target: val}))}
                className={`flex-1 py-2.5 rounded-xl text-sm font-semibold border-2 transition-all ${form.target === val ? 'border-[#2E5E99] bg-[#E7F0FA] text-[#2E5E99]' : 'border-gray-100 text-gray-500 hover:border-gray-300'}`}>
                {lbText}
              </button>
            ))}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>{t('العنوان (عربي)','Title Arabic')}</label><input value={form.title_ar} onChange={e => setForm(f => ({...f, title_ar: e.target.value}))} className={inp} placeholder="عرض اليوم!" dir="rtl" /></div>
          <div><label className={lbl}>{t('العنوان (إنجليزي)','Title English')}</label><input value={form.title_en} onChange={e => setForm(f => ({...f, title_en: e.target.value}))} className={inp} placeholder="Today's offer!" dir="ltr" /></div>
          <div><label className={lbl}>{t('الرسالة (عربي)','Body Arabic')}</label><textarea value={form.body_ar} onChange={e => setForm(f => ({...f, body_ar: e.target.value}))} className={`${inp} resize-none`} rows={3} placeholder="نص الإشعار بالعربية..." dir="rtl" /></div>
          <div><label className={lbl}>{t('الرسالة (إنجليزي)','Body English')}</label><textarea value={form.body_en} onChange={e => setForm(f => ({...f, body_en: e.target.value}))} className={`${inp} resize-none`} rows={3} placeholder="Notification text in English..." dir="ltr" /></div>
        </div>

        {/* Preview */}
        {form.title_ar && (
          <div className="bg-[#0D2440] rounded-2xl p-4 flex gap-3">
            <div className="w-10 h-10 bg-[#2E5E99] rounded-xl flex items-center justify-center text-xl flex-shrink-0">🛒</div>
            <div><div className="text-white font-bold text-sm">{form.title_ar || 'العنوان'}</div><div className="text-[#7BA4D0] text-xs mt-0.5">{form.body_ar || 'نص الإشعار'}</div></div>
          </div>
        )}

        <button onClick={() => sendMutation.mutate(form)} disabled={sendMutation.isPending || !form.title_ar || !form.body_ar}
          className="w-full bg-[#F97316] hover:bg-orange-600 text-white py-3 rounded-xl font-bold text-sm disabled:opacity-40 transition-colors flex items-center justify-center gap-2">
          {sendMutation.isPending ? <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> {t('جاري الإرسال...','Sending...')}</> : `🔔 ${t('إرسال الإشعار','Send Notification')}`}
        </button>
      </div>
    </div>
  );
}
