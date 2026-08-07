import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { notificationApi } from '../services/api';
import toast from 'react-hot-toast';

// Arabic label + description for every known settings key. Unknown keys fall
// back to the raw key / DB description.
const SETTING_META = {
  delivery_radius_km: { ar: 'نطاق التوصيل (كم)', descAr: 'أقصى مسافة للتوصيل بالكيلومتر — الطلبات الأبعد من ذلك تُرفض' },
  store_latitude: { ar: 'خط عرض المتجر', descAr: 'خط عرض موقع المتجر' },
  store_longitude: { ar: 'خط طول المتجر', descAr: 'خط طول موقع المتجر' },
  loyalty_enabled: { ar: 'تفعيل نقاط الولاء', descAr: 'تفعيل نظام نقاط الولاء (1 = مفعّل)' },
  loyalty_earn_points: { ar: 'النقاط المكتسبة لكل شريحة', descAr: 'عدد النقاط الممنوحة لكل شريحة إنفاق' },
  loyalty_earn_per_egp: { ar: 'قيمة شريحة الإنفاق (جنيه)', descAr: 'قيمة شريحة الإنفاق بالجنيه (نقاط لكل X جنيه)' },
  loyalty_redeem_points: { ar: 'نقاط الاستبدال المطلوبة', descAr: 'عدد النقاط المطلوبة مقابل خصم' },
  loyalty_redeem_egp: { ar: 'قيمة الخصم (جنيه)', descAr: 'قيمة الخصم بالجنيه مقابل عدد النقاط المحدد' },
  loyalty_min_redeem: { ar: 'أقل نقاط للاستبدال', descAr: 'أقل عدد نقاط يمكن استبداله في الطلب الواحد' },
  loyalty_max_redeem_percent: { ar: 'أقصى نسبة خصم بالنقاط (%)', descAr: 'أقصى نسبة خصم من قيمة الطلب عبر النقاط (%)' },
  loyalty_earn_rate: { ar: 'معدل اكتساب النقاط (قديم)', descAr: 'النقاط المكتسبة لكل جنيه (النظام القديم)' },
  loyalty_redeem_rate: { ar: 'معدل استبدال النقاط (قديم)', descAr: 'قيمة النقطة بالجنيه عند الاستبدال (النظام القديم)' },
  points_per_egp: { ar: 'نقاط لكل جنيه', descAr: 'النقاط المكتسبة عن كل جنيه إنفاق' },
  points_value_egp: { ar: 'قيمة النقطة (جنيه)', descAr: 'قيمة النقطة الواحدة بالجنيه' },
  rating_bonus_points: { ar: 'نقاط مكافأة التقييم', descAr: 'نقاط إضافية تُمنح عند تقييم الطلب' },
  support_phone_1: { ar: 'هاتف الدعم 1', descAr: 'رقم هاتف خدمة العملاء الأول' },
  support_phone_2: { ar: 'هاتف الدعم 2', descAr: 'رقم هاتف خدمة العملاء الثاني' },
  whatsapp_number: { ar: 'رقم الواتساب', descAr: 'رقم واتساب خدمة العملاء' },
  delivery_fee: { ar: 'رسوم التوصيل', descAr: 'رسوم التوصيل الافتراضية بالجنيه' },
  min_order_amount: { ar: 'الحد الأدنى للطلب', descAr: 'أقل قيمة للطلب بالجنيه' },
  app_name_ar: { ar: 'اسم التطبيق (عربي)', descAr: 'اسم التطبيق باللغة العربية' },
  app_name_en: { ar: 'اسم التطبيق (إنجليزي)', descAr: 'اسم التطبيق باللغة الإنجليزية' },
  working_hours: { ar: 'ساعات العمل', descAr: 'مواعيد عمل المتجر' },
  auto_close_hours: { ar: 'ساعات الإغلاق التلقائي', descAr: 'عدد الساعات قبل الإغلاق التلقائي للطلب المُسلَّم' },
  auto_close_timeout_hours: { ar: 'مهلة الإغلاق التلقائي (ساعات)', descAr: 'مؤقت الإغلاق التلقائي للطلبات بالساعات' },
  weight_diff_approval_timeout_mins: { ar: 'مهلة موافقة فرق الوزن (دقائق)', descAr: 'المهلة بالدقائق لموافقة العميل على فرق الوزن' },
  multistore_enabled: { ar: 'تفعيل تعدد المتاجر', descAr: 'عرض شبكة المتاجر في تطبيق العميل (1) أو وضع المتجر الواحد (0)' },
  default_store_id: { ar: 'المتجر الافتراضي', descAr: 'المتجر الذي يُحمَّل عند إيقاف تعدد المتاجر' },
  app_version_ios: { ar: 'إصدار تطبيق iOS', descAr: 'رقم إصدار تطبيق الآيفون' },
  app_version_android: { ar: 'إصدار تطبيق أندرويد', descAr: 'رقم إصدار تطبيق الأندرويد' },
  maintenance_mode: { ar: 'وضع الصيانة', descAr: 'إيقاف الخدمة مؤقتاً للصيانة (1 = مفعّل)' },
  ai_recommendations_enabled: { ar: 'توصيات الذكاء الاصطناعي', descAr: 'تفعيل ميزة التوصيات الذكية (1 = مفعّل)' },
};

export default function SettingsPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [editingKey, setEditingKey] = useState(null);
  const [editValue, setEditValue] = useState('');

  const { data: settings } = useQuery({
    queryKey: ['app-settings'],
    queryFn: () => notificationApi.settings().then(r => r.data),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, value }) => notificationApi.updateSetting(id, { value }),
    onSuccess: () => { qc.invalidateQueries(['app-settings']); setEditingKey(null); toast.success(t('تم الحفظ', 'Saved')); },
  });

  const settingsList = Array.isArray(settings) ? settings : (settings?.results || []);

  return (
    <div className="p-6 space-y-5">
      <h1 className="text-2xl font-bold text-[#0D2440] font-serif">{t('الإعدادات العامة', 'App Settings')}</h1>
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        {settingsList.map(setting => (
          <div key={setting.id} className="flex items-center justify-between p-4 border-b border-gray-50 last:border-0">
            <div>
              <div className="font-semibold text-[#0D2440] text-sm">
                {lang === 'ar' ? (SETTING_META[setting.key]?.ar || setting.key) : setting.key}
                {lang === 'ar' && SETTING_META[setting.key] && (
                  <span className="font-mono font-normal text-[10px] text-gray-300 mx-2" dir="ltr">{setting.key}</span>
                )}
              </div>
              <div className="text-xs text-gray-400">
                {lang === 'ar' ? (SETTING_META[setting.key]?.descAr || setting.description) : setting.description}
              </div>
            </div>
            <div className="flex items-center gap-2">
              {editingKey === setting.id ? (
                <>
                  <input value={editValue} onChange={e => setEditValue(e.target.value)}
                    className="border border-[#2E5E99] rounded-lg px-3 py-1.5 text-sm outline-none w-40" />
                  <button onClick={() => updateMutation.mutate({ id: setting.id, value: editValue })}
                    className="bg-[#2E5E99] text-white px-3 py-1.5 rounded-lg text-xs font-semibold">
                    {t('حفظ', 'Save')}
                  </button>
                  <button onClick={() => setEditingKey(null)} className="text-gray-400 text-xs px-2">{t('إلغاء', 'Cancel')}</button>
                </>
              ) : (
                <>
                  <span className="font-mono text-sm bg-gray-100 px-3 py-1.5 rounded-lg text-[#0D2440]">{setting.value}</span>
                  <button onClick={() => { setEditingKey(setting.id); setEditValue(setting.value); }}
                    className="text-[#2E5E99] text-xs font-semibold hover:underline">{t('تعديل', 'Edit')}</button>
                </>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
