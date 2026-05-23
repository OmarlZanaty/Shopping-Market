import React, { useState } from 'react';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
import { useOutletContext, useNavigate } from 'react-router-dom';
import { userApi, branchApi } from '../services/api';
import toast from 'react-hot-toast';

const ROLES = [
  { value: 'preparer', labelAr: '🧺 محضّر (يجهّز الطلبات)', labelEn: '🧺 Preparer (picks orders)' },
  { value: 'driver',   labelAr: '🛵 مندوب توصيل',           labelEn: '🛵 Delivery Driver' },
];

export default function DriverFormPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [form, setForm] = useState({
    full_name: '', phone: '', password: '', confirm_password: '',
    email: '', branch: '', role: 'preparer',
  });

  const { data: branchesData } = useQuery({
    queryKey: ['branches'],
    queryFn: () => branchApi.list().then(r => r.data),
  });
  const branches = Array.isArray(branchesData) ? branchesData : (branchesData?.results || []);

  const createMutation = useMutation({
    mutationFn: (d) => userApi.createStaff(d),
    onSuccess: () => {
      qc.invalidateQueries(['drivers']);
      toast.success(t('تم إنشاء الحساب بنجاح ✓', 'Account created successfully ✓'));
      navigate('/drivers');
    },
    onError: (e) => {
      const data = e.response?.data;
      // Show first field-level error if present
      const fieldErr = data?.errors?.[0]
        || data?.phone?.[0]
        || data?.password?.[0]
        || data?.full_name?.[0];
      const msg = fieldErr || data?.message || e.message || t('حدث خطأ', 'An error occurred');
      toast.error(msg, { duration: 5000 });
    },
  });

  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none transition-colors bg-white';
  const lbl = 'text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5';

  const canSubmit = form.full_name && form.phone && form.password.length >= 8 && form.password === form.confirm_password;

  return (
    <div className="p-6 max-w-xl mx-auto">
      {/* Header */}
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => navigate('/drivers')}
          className="w-9 h-9 bg-white border border-gray-200 rounded-xl flex items-center justify-center hover:bg-gray-50 text-lg">←</button>
        <div>
          <h1 className="text-xl font-bold text-[#0D2440] font-serif">
            {t('إضافة موظف جديد', 'Add New Staff Account')}
          </h1>
          <p className="text-gray-500 text-sm mt-0.5">
            {t('محضّر أو مندوب — يمكنه تسجيل الدخول فوراً', 'Preparer or driver — can login immediately')}
          </p>
        </div>
      </div>

      <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm space-y-5">

        {/* Role selector */}
        <div>
          <label className={lbl}>{t('نوع الموظف', 'Staff Role')} *</label>
          <div className="grid grid-cols-2 gap-3">
            {ROLES.map(r => (
              <button
                key={r.value}
                type="button"
                onClick={() => setForm(f => ({ ...f, role: r.value }))}
                className={`py-3 px-4 rounded-xl border-2 text-sm font-semibold text-start transition-all ${
                  form.role === r.value
                    ? 'border-[#2E5E99] bg-[#E7F0FA] text-[#0D2440]'
                    : 'border-gray-100 text-gray-500 hover:border-gray-200'
                }`}
              >
                {t(r.labelAr, r.labelEn)}
              </button>
            ))}
          </div>
        </div>

        {/* Name + Phone */}
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <label className={lbl}>{t('الاسم الكامل', 'Full Name')} *</label>
            <input value={form.full_name}
              onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))}
              placeholder={t('اسم الموظف', 'Staff member name')} className={inp} />
          </div>
          <div>
            <label className={lbl}>{t('رقم الهاتف', 'Phone')} *</label>
            <input value={form.phone}
              onChange={e => setForm(f => ({ ...f, phone: e.target.value }))}
              placeholder="01000000000" className={`${inp} font-mono`} />
          </div>
          <div>
            <label className={lbl}>{t('البريد الإلكتروني', 'Email')}</label>
            <input type="email" value={form.email}
              onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
              placeholder="staff@example.com" className={inp} />
          </div>
        </div>

        {/* Password */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={lbl}>{t('كلمة المرور', 'Password')} * <span className="text-gray-400 normal-case font-normal">{t('(8 أحرف على الأقل)', '(min 8 chars)')}</span></label>
            <input type="password" value={form.password}
              onChange={e => setForm(f => ({ ...f, password: e.target.value }))}
              placeholder="••••••••"
              className={`${inp} ${form.password && form.password.length < 8 ? 'border-red-400' : ''}`} />
            {form.password && form.password.length < 8 && (
              <p className="text-xs text-red-500 mt-1">{t('يجب أن تكون 8 أحرف على الأقل', 'Must be at least 8 characters')}</p>
            )}
          </div>
          <div>
            <label className={lbl}>{t('تأكيد المرور', 'Confirm Password')} *</label>
            <input type="password" value={form.confirm_password}
              onChange={e => setForm(f => ({ ...f, confirm_password: e.target.value }))}
              placeholder="••••••••"
              className={`${inp} ${form.confirm_password && form.password !== form.confirm_password ? 'border-red-400' : ''}`} />
            {form.confirm_password && form.password !== form.confirm_password && (
              <p className="text-xs text-red-500 mt-1">{t('كلمتا المرور غير متطابقتين', 'Passwords do not match')}</p>
            )}
          </div>
        </div>

        {/* Branch */}
        <div>
          <label className={lbl}>{t('الفرع', 'Branch')} ({t('اختياري', 'optional')})</label>
          <select value={form.branch} onChange={e => setForm(f => ({ ...f, branch: e.target.value }))} className={inp}>
            <option value="">{t('جميع الفروع', 'All branches')}</option>
            {branches.map(b => <option key={b.id} value={b.id}>{lang === 'ar' ? b.name_ar : b.name}</option>)}
          </select>
        </div>

        {/* Info box */}
        <div className="bg-[#E7F0FA] rounded-xl p-4 border border-[#7BA4D0]">
          <div className="flex items-start gap-2 text-xs text-[#2E5E99]">
            <span className="text-base">ℹ️</span>
            <div>
              <div className="font-bold mb-1">{t('بعد الإنشاء:', 'After creation:')}</div>
              <div>• {t('يحمّل تطبيق المناديب', 'Downloads the agent app')}</div>
              <div>• {t('يسجّل الدخول برقم الهاتف وكلمة المرور', 'Logs in with phone + password')}</div>
              <div>• {t('يظهر فوراً في لوحة التحكم', 'Appears in dashboard immediately')}</div>
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="flex gap-3 pt-1">
          <button onClick={() => navigate('/drivers')}
            className="px-6 py-3 border-2 border-gray-200 rounded-xl text-sm font-semibold hover:bg-gray-50 transition-colors">
            {t('إلغاء', 'Cancel')}
          </button>
          <button
            onClick={() => createMutation.mutate({
              full_name: form.full_name,
              phone: form.phone,
              password: form.password,
              confirm_password: form.confirm_password,
              email: form.email || undefined,
              branch: form.branch || undefined,
              role: form.role,
            })}
            disabled={createMutation.isPending || !canSubmit}
            className="flex-1 bg-[#0D2440] hover:bg-[#2E5E99] text-white py-3 rounded-xl text-sm font-bold disabled:opacity-40 transition-colors flex items-center justify-center gap-2">
            {createMutation.isPending
              ? <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />{t('جاري الإنشاء...', 'Creating...')}</>
              : `${form.role === 'preparer' ? '🧺' : '🛵'} ${t('إنشاء الحساب', 'Create Account')}`}
          </button>
        </div>
      </div>
    </div>
  );
}
