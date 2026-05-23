import React, { useState } from 'react';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
import { useOutletContext, useNavigate } from 'react-router-dom';
import { userApi, branchApi } from '../services/api';
import toast from 'react-hot-toast';

export default function DriverFormPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [form, setForm] = useState({
    full_name: '', phone: '', password: '', email: '',
    delivery_zone: '', branch: '',
  });

  const { data: branchesData } = useQuery({ queryKey: ['branches'], queryFn: () => branchApi.list().then(r => r.data) });
  const branches = Array.isArray(branchesData) ? branchesData : (branchesData?.results || []);

  const createMutation = useMutation({
    mutationFn: (d) => userApi.createDriver(d),
    onSuccess: () => {
      qc.invalidateQueries(['drivers']);
      toast.success(t('تم إنشاء حساب المندوب بنجاح', 'Driver account created'));
      navigate('/drivers');
    },
    onError: (e) => toast.error(e.response?.data?.phone?.[0] || t('حدث خطأ', 'Error occurred')),
  });

  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none transition-colors';
  const lbl = 'text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5';

  return (
    <div className="p-6 max-w-xl mx-auto">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => navigate('/drivers')} className="w-9 h-9 bg-white border border-gray-200 rounded-xl flex items-center justify-center hover:bg-gray-50">←</button>
        <div>
          <h1 className="text-xl font-bold text-[#0D2440] font-serif">{t('إضافة مندوب جديد', 'Add New Driver')}</h1>
          <p className="text-gray-500 text-sm mt-0.5">{t('سيتمكن من تسجيل الدخول فوراً', 'Can login immediately after creation')}</p>
        </div>
      </div>

      <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <label className={lbl}>{t('الاسم الكامل', 'Full Name')} *</label>
            <input value={form.full_name} onChange={e => setForm(f => ({...f, full_name: e.target.value}))}
              placeholder={t('اسم المندوب', 'Driver name')} className={inp} />
          </div>
          <div>
            <label className={lbl}>{t('رقم الهاتف', 'Phone Number')} *</label>
            <input value={form.phone} onChange={e => setForm(f => ({...f, phone: e.target.value}))}
              placeholder="01000000000" className={`${inp} font-mono`} />
          </div>
          <div>
            <label className={lbl}>{t('كلمة المرور', 'Password')} *</label>
            <input type="password" value={form.password} onChange={e => setForm(f => ({...f, password: e.target.value}))}
              placeholder="••••••" className={inp} />
          </div>
          <div className="col-span-2">
            <label className={lbl}>{t('البريد الإلكتروني', 'Email')} ({t('اختياري', 'Optional')})</label>
            <input type="email" value={form.email} onChange={e => setForm(f => ({...f, email: e.target.value}))}
              placeholder="driver@example.com" className={inp} />
          </div>
          <div className="col-span-2">
            <label className={lbl}>{t('الفرع', 'Branch')} ({t('اختياري', 'Optional')})</label>
            <select value={form.branch} onChange={e => setForm(f => ({...f, branch: e.target.value}))} className={inp}>
              <option value="">{t('جميع الفروع', 'All Branches')}</option>
              {branches.map(b => <option key={b.id} value={b.id}>{lang === 'ar' ? b.name_ar : b.name}</option>)}
            </select>
          </div>
          <div className="col-span-2">
            <label className={lbl}>{t('منطقة التوصيل', 'Delivery Zone')} ({t('اختياري', 'Optional')})</label>
            <input value={form.delivery_zone} onChange={e => setForm(f => ({...f, delivery_zone: e.target.value}))}
              placeholder={t('مثال: المعادي، الزمالك', 'e.g. Maadi, Zamalek')} className={inp} />
          </div>
        </div>

        <div className="bg-[#E7F0FA] rounded-xl p-4 border border-[#7BA4D0]">
          <div className="flex items-start gap-2">
            <span className="text-lg">ℹ️</span>
            <div className="text-xs text-[#2E5E99]">
              <div className="font-bold mb-1">{t('ملاحظة للمندوب الجديد:', 'Note for new driver:')}</div>
              <div>{t('• يمكنه تحميل تطبيق المناديب وتسجيل الدخول برقم الهاتف وكلمة المرور', '• Can download driver app and login with phone + password')}</div>
              <div>{t('• يمكنه إعداد بصمة الإصبع من الإعدادات', '• Can setup fingerprint from settings')}</div>
              <div>{t('• يظهر في لوحة التحكم بمجرد تفعيل الحساب', '• Appears in dashboard once account is active')}</div>
            </div>
          </div>
        </div>

        <div className="flex gap-3 pt-2">
          <button onClick={() => navigate('/drivers')} className="px-6 py-3 border-2 border-gray-200 rounded-xl text-sm font-semibold hover:bg-gray-50 transition-colors">
            {t('إلغاء', 'Cancel')}
          </button>
          <button onClick={() => createMutation.mutate(form)}
            disabled={createMutation.isPending || !form.full_name || !form.phone || !form.password}
            className="flex-1 bg-[#0D2440] hover:bg-[#2E5E99] text-white py-3 rounded-xl text-sm font-bold disabled:opacity-40 transition-colors flex items-center justify-center gap-2">
            {createMutation.isPending
              ? <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> {t('جاري الإنشاء...', 'Creating...')}</>
              : `🛵 ${t('إنشاء حساب المندوب', 'Create Driver Account')}`}
          </button>
        </div>
      </div>
    </div>
  );
}
