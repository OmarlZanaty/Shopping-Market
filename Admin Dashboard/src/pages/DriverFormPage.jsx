import React, { useEffect, useState } from 'react';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
import { useOutletContext, useNavigate, useParams } from 'react-router-dom';
import { userApi, branchApi } from '../services/api';
import toast from 'react-hot-toast';

const ROLES = [
  { value: 'preparer', labelAr: '🧺 محضّر (يجهّز الطلبات)', labelEn: '🧺 Preparer (picks orders)' },
  { value: 'driver',   labelAr: '🛵 مندوب توصيل',           labelEn: '🛵 Delivery Driver' },
];

const EMPTY_FORM = {
  full_name: '', phone: '', password: '', confirm_password: '',
  email: '', branch: '', role: 'preparer',
};

/**
 * Shared form for creating AND editing a staff account (driver / preparer).
 * - /drivers/new        → create mode (password required)
 * - /drivers/:id/edit   → edit mode (password optional — only sent if filled)
 */
export default function DriverFormPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => (lang === 'ar' ? ar : en);
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { id: editId } = useParams();
  const isEdit = Boolean(editId);

  const [form, setForm] = useState(EMPTY_FORM);

  // ── Lookups ─────────────────────────────────────────────────────────────
  const { data: branchesData } = useQuery({
    queryKey: ['branches'],
    queryFn: () => branchApi.list().then((r) => r.data),
  });
  const branches = Array.isArray(branchesData) ? branchesData : (branchesData?.results || []);

  // Prefill in edit mode.
  const { data: existing, isLoading: loadingExisting } = useQuery({
    enabled: isEdit,
    queryKey: ['staff', editId],
    queryFn: () => userApi.get(editId).then((r) => r.data?.data || r.data),
  });
  useEffect(() => {
    if (!existing) return;
    setForm({
      full_name: existing.full_name || '',
      phone:     existing.phone || '',
      email:     existing.email || '',
      branch:    existing.branch || '',
      role:      existing.role === 'driver' ? 'driver' : 'preparer',
      password: '', confirm_password: '',
    });
  }, [existing]);

  // ── Submit handler — one mutation, two URLs ─────────────────────────────
  const errorToast = (e) => {
    const data = e.response?.data;
    const fieldErr = data?.errors?.[0]?.message
      || data?.errors?.phone?.[0] || data?.errors?.password?.[0]
      || data?.phone?.[0] || data?.password?.[0] || data?.full_name?.[0];
    const msg = fieldErr || data?.message || e.message || t('حدث خطأ', 'An error occurred');
    toast.error(msg, { duration: 5000 });
  };

  const mutation = useMutation({
    mutationFn: (payload) => (isEdit
      ? userApi.update(editId, payload)
      : userApi.createStaff(payload)),
    onSuccess: () => {
      qc.invalidateQueries(['drivers']);
      qc.invalidateQueries(['staff', editId]);
      toast.success(isEdit
        ? t('تم حفظ التعديلات ✓', 'Changes saved ✓')
        : t('تم إنشاء الحساب بنجاح ✓', 'Account created successfully ✓'));
      navigate('/drivers');
    },
    onError: errorToast,
  });

  // ── Validation ──────────────────────────────────────────────────────────
  const passwordOK = isEdit
    ? (!form.password || (form.password.length >= 8 && form.password === form.confirm_password))
    : (form.password.length >= 8 && form.password === form.confirm_password);
  const canSubmit = form.full_name && form.phone && passwordOK;

  const submit = () => {
    const payload = {
      full_name: form.full_name,
      phone:     form.phone,
      email:     form.email || undefined,
      branch:    form.branch || undefined,
      role:      form.role,
    };
    // Only send password on create, or on edit when the admin actually typed one.
    if (form.password) {
      payload.password = form.password;
      payload.confirm_password = form.confirm_password;
    }
    mutation.mutate(payload);
  };

  // ── Styles ──────────────────────────────────────────────────────────────
  const inp = 'w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-2.5 text-sm outline-none transition-colors bg-white';
  const lbl = 'text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5';

  if (isEdit && loadingExisting) {
    return <div className="p-10 text-center text-gray-500">{t('جاري التحميل...', 'Loading...')}</div>;
  }

  return (
    <div className="p-6 max-w-xl mx-auto">
      {/* Header */}
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => navigate('/drivers')}
          className="w-9 h-9 bg-white border border-gray-200 rounded-xl flex items-center justify-center hover:bg-gray-50 text-lg">←</button>
        <div>
          <h1 className="text-xl font-bold text-[#0D2440] font-serif">
            {isEdit
              ? t('تعديل بيانات الموظف', 'Edit Staff Account')
              : t('إضافة موظف جديد', 'Add New Staff Account')}
          </h1>
          <p className="text-gray-500 text-sm mt-0.5">
            {isEdit
              ? t('عدّل البيانات واترك كلمة المرور فارغة لو لا تريد تغييرها', 'Edit any field — leave password blank to keep current')
              : t('محضّر أو مندوب — يمكنه تسجيل الدخول فوراً', 'Preparer or driver — can login immediately')}
          </p>
        </div>
      </div>

      <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm space-y-5">
        {/* Role */}
        <div>
          <label className={lbl}>{t('نوع الموظف', 'Staff Role')} *</label>
          <div className="grid grid-cols-2 gap-3">
            {ROLES.map((r) => (
              <button key={r.value} type="button"
                onClick={() => setForm((f) => ({ ...f, role: r.value }))}
                className={`py-3 px-4 rounded-xl border-2 text-sm font-semibold text-start transition-all ${
                  form.role === r.value
                    ? 'border-[#2E5E99] bg-[#E7F0FA] text-[#0D2440]'
                    : 'border-gray-100 text-gray-500 hover:border-gray-200'}`}>
                {t(r.labelAr, r.labelEn)}
              </button>
            ))}
          </div>
        </div>

        {/* Name / Phone / Email */}
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <label className={lbl}>{t('الاسم الكامل', 'Full Name')} *</label>
            <input value={form.full_name}
              onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))}
              placeholder={t('اسم الموظف', 'Staff member name')} className={inp} />
          </div>
          <div>
            <label className={lbl}>{t('رقم الهاتف', 'Phone')} *</label>
            <input value={form.phone}
              onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
              placeholder="01000000000" className={`${inp} font-mono`} />
          </div>
          <div>
            <label className={lbl}>{t('البريد الإلكتروني', 'Email')}</label>
            <input type="email" value={form.email}
              onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
              placeholder="staff@example.com" className={inp} />
          </div>
        </div>

        {/* Password — optional in edit mode */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={lbl}>
              {t('كلمة المرور', 'Password')} {isEdit ? '' : '*'}{' '}
              <span className="text-gray-400 normal-case font-normal">
                {isEdit ? t('(اتركها فارغة لو لا تريد تغييرها)', '(leave blank to keep current)')
                        : t('(8 أحرف على الأقل)', '(min 8 chars)')}
              </span>
            </label>
            <input type="password" autoComplete="new-password" value={form.password}
              onChange={(e) => setForm((f) => ({ ...f, password: e.target.value }))}
              placeholder="••••••••"
              className={`${inp} ${form.password && form.password.length < 8 ? 'border-red-400' : ''}`} />
            {form.password && form.password.length < 8 && (
              <p className="text-xs text-red-500 mt-1">{t('يجب أن تكون 8 أحرف على الأقل', 'Must be at least 8 characters')}</p>
            )}
          </div>
          <div>
            <label className={lbl}>{t('تأكيد المرور', 'Confirm Password')} {isEdit ? '' : '*'}</label>
            <input type="password" autoComplete="new-password" value={form.confirm_password}
              onChange={(e) => setForm((f) => ({ ...f, confirm_password: e.target.value }))}
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
          <select value={form.branch}
            onChange={(e) => setForm((f) => ({ ...f, branch: e.target.value }))} className={inp}>
            <option value="">{t('جميع الفروع', 'All branches')}</option>
            {branches.map((b) => (
              <option key={b.id} value={b.id}>{lang === 'ar' ? b.name_ar : b.name}</option>
            ))}
          </select>
        </div>

        {/* Actions */}
        <div className="flex gap-3 pt-1">
          <button onClick={() => navigate('/drivers')}
            className="px-6 py-3 border-2 border-gray-200 rounded-xl text-sm font-semibold hover:bg-gray-50 transition-colors">
            {t('إلغاء', 'Cancel')}
          </button>
          <button onClick={submit}
            disabled={mutation.isPending || !canSubmit}
            className="flex-1 bg-[#0D2440] hover:bg-[#2E5E99] text-white py-3 rounded-xl text-sm font-bold disabled:opacity-40 transition-colors flex items-center justify-center gap-2">
            {mutation.isPending
              ? <><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  {isEdit ? t('جاري الحفظ...', 'Saving...') : t('جاري الإنشاء...', 'Creating...')}</>
              : (isEdit
                  ? `💾 ${t('حفظ التعديلات', 'Save Changes')}`
                  : `${form.role === 'preparer' ? '🧺' : '🛵'} ${t('إنشاء الحساب', 'Create Account')}`)}
          </button>
        </div>
      </div>
    </div>
  );
}
