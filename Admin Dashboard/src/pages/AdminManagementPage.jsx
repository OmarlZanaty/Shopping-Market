import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext, useNavigate } from 'react-router-dom';
import { api } from '../services/api';
import toast from 'react-hot-toast';

const PERMISSION_META = {
  view_orders:        { icon: '👁️', ar: 'عرض الطلبات',        en: 'View Orders' },
  manage_orders:      { icon: '📦', ar: 'إدارة الطلبات',       en: 'Manage Orders' },
  assign_drivers:     { icon: '🛵', ar: 'تعيين مناديب',        en: 'Assign Drivers' },
  cancel_orders:      { icon: '❌', ar: 'إلغاء الطلبات',       en: 'Cancel Orders' },
  view_products:      { icon: '👁️', ar: 'عرض المنتجات',        en: 'View Products' },
  manage_products:    { icon: '🛍️', ar: 'إدارة المنتجات',      en: 'Manage Products' },
  manage_categories:  { icon: '📂', ar: 'إدارة الأقسام',       en: 'Manage Categories' },
  manage_banners:     { icon: '🖼️', ar: 'إدارة الإعلانات',     en: 'Manage Banners' },
  manage_media:       { icon: '🗄️', ar: 'مكتبة الوسائط',       en: 'Media Library' },
  view_customers:     { icon: '👥', ar: 'عرض العملاء',         en: 'View Customers' },
  manage_customers:   { icon: '👤', ar: 'إدارة العملاء',       en: 'Manage Customers' },
  view_drivers:       { icon: '👁️', ar: 'عرض المناديب',        en: 'View Drivers' },
  manage_drivers:     { icon: '🛵', ar: 'إدارة المناديب',      en: 'Manage Drivers' },
  settle_cash:        { icon: '💵', ar: 'تسوية الكاش',         en: 'Settle Cash' },
  view_analytics:     { icon: '📊', ar: 'عرض الإحصائيات',      en: 'View Analytics' },
  view_reports:       { icon: '📋', ar: 'عرض التقارير',         en: 'View Reports' },
  export_reports:     { icon: '📤', ar: 'تصدير التقارير',      en: 'Export Reports' },
  manage_settings:    { icon: '⚙️', ar: 'إعدادات التطبيق',     en: 'App Settings' },
  manage_branches:    { icon: '🏪', ar: 'إدارة الفروع',        en: 'Manage Branches' },
  send_notifications: { icon: '🔔', ar: 'إرسال إشعارات',      en: 'Send Notifications' },
  manage_admins:      { icon: '👑', ar: 'إدارة الإداريين',     en: 'Manage Admins' },
  view_audit_log:     { icon: '📜', ar: 'سجل الإجراءات',       en: 'Audit Log' },
};

const GROUPS = {
  orders:    { ar: 'الطلبات',    en: 'Orders',    color: 'bg-blue-50 border-blue-200' },
  products:  { ar: 'المنتجات',  en: 'Products',  color: 'bg-green-50 border-green-200' },
  users:     { ar: 'المستخدمون', en: 'Users',     color: 'bg-purple-50 border-purple-200' },
  analytics: { ar: 'التقارير',  en: 'Analytics', color: 'bg-amber-50 border-amber-200' },
  settings:  { ar: 'الإعدادات', en: 'Settings',  color: 'bg-orange-50 border-orange-200' },
  superadmin:{ ar: 'صلاحيات خاصة', en: 'Super Admin', color: 'bg-red-50 border-red-200' },
};

const PRESET_ROLES_UI = {
  super_admin:     { ar: 'مدير عام',      en: 'Super Admin',    color: 'bg-red-100 text-red-800',    badge: '👑' },
  manager:         { ar: 'مدير فرع',     en: 'Branch Manager', color: 'bg-purple-100 text-purple-800', badge: '🏪' },
  orders_staff:    { ar: 'موظف طلبات',   en: 'Orders Staff',   color: 'bg-blue-100 text-blue-800',   badge: '📦' },
  products_staff:  { ar: 'موظف منتجات',  en: 'Products Staff', color: 'bg-green-100 text-green-800', badge: '🛍️' },
  analytics_viewer:{ ar: 'مشاهد تقارير', en: 'Analytics Only', color: 'bg-amber-100 text-amber-800', badge: '📊' },
  custom:          { ar: 'مخصص',         en: 'Custom',         color: 'bg-gray-100 text-gray-700',   badge: '🔧' },
};

function PermissionToggle({ perm, checked, onChange, lang }) {
  const meta = PERMISSION_META[perm] || { icon: '🔒', ar: perm, en: perm };
  return (
    <label className={`flex items-center gap-2 p-2 rounded-lg cursor-pointer hover:bg-white/60 transition-colors ${checked ? 'opacity-100' : 'opacity-60'}`}>
      <input type="checkbox" checked={checked} onChange={() => onChange(perm)}
        className="w-4 h-4 accent-[#2E5E99] rounded" />
      <span className="text-sm">{meta.icon}</span>
      <span className="text-sm font-medium text-[#0D2440]">
        {lang === 'ar' ? meta.ar : meta.en}
      </span>
    </label>
  );
}

function AdminCard({ admin, lang, onToggle, onEdit, onDelete, onResetPwd }) {
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const role = PRESET_ROLES_UI[admin.preset_role] || PRESET_ROLES_UI.custom;

  return (
    <div className={`bg-white rounded-2xl border shadow-sm overflow-hidden ${!admin.user_is_active ? 'opacity-60' : ''}`}>
      <div className="p-5">
        <div className="flex items-start justify-between mb-3">
          <div className="flex items-center gap-3">
            <div className={`w-12 h-12 rounded-full flex items-center justify-center text-xl font-bold text-white flex-shrink-0 ${admin.is_super_admin ? 'bg-gradient-to-br from-[#F97316] to-[#dc2626]' : 'bg-gradient-to-br from-[#2E5E99] to-[#0D2440]'}`}>
              {admin.is_super_admin ? '👑' : admin.user_name?.[0] || 'A'}
            </div>
            <div>
              <div className="font-bold text-[#0D2440]">{admin.user_name}</div>
              <div className="text-xs text-gray-400">{admin.user_phone}</div>
              {admin.user_email && <div className="text-xs text-gray-400">{admin.user_email}</div>}
            </div>
          </div>
          <div className="flex flex-col items-end gap-1">
            <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${role.color}`}>
              {role.badge} {lang === 'ar' ? role.ar : role.en}
            </span>
            {admin.is_super_admin && (
              <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-red-100 text-red-700">
                SUPER
              </span>
            )}
          </div>
        </div>

        {/* Permissions count */}
        <div className="flex items-center gap-2 mb-3 flex-wrap">
          <span className="text-xs bg-[#E7F0FA] text-[#2E5E99] px-2 py-1 rounded-lg font-semibold">
            {admin.is_super_admin
              ? `✅ ${t('كل الصلاحيات', 'All Permissions')}`
              : `🔐 ${admin.permissions?.length || 0} ${t('صلاحية', 'permissions')}`
            }
          </span>
          {admin.all_branches_access
            ? <span className="text-xs bg-green-50 text-green-700 px-2 py-1 rounded-lg">🏪 {t('كل الفروع', 'All Branches')}</span>
            : <span className="text-xs bg-orange-50 text-orange-700 px-2 py-1 rounded-lg">🏪 {admin.allowed_branch_ids?.length} {t('فرع', 'branches')}</span>
          }
          <span className={`text-xs px-2 py-1 rounded-lg ${admin.user_is_active ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-600'}`}>
            {admin.user_is_active ? t('نشط', 'Active') : t('موقوف', 'Blocked')}
          </span>
        </div>

        {admin.notes && (
          <p className="text-xs text-gray-500 bg-gray-50 rounded-lg p-2 mb-3">{admin.notes}</p>
        )}

        <div className="text-xs text-gray-400">
          {t('أنشئ بواسطة', 'Created by')}: {admin.created_by_name || t('النظام', 'System')} ·{' '}
          {new Date(admin.created_at).toLocaleDateString(lang === 'ar' ? 'ar-EG' : 'en-US')}
        </div>
      </div>

      <div className="border-t border-gray-100 flex divide-x divide-gray-100">
        <button onClick={() => onEdit(admin)} className="flex-1 py-2.5 text-xs font-semibold text-[#2E5E99] hover:bg-[#E7F0FA] transition-colors">
          {t('تعديل الصلاحيات', 'Edit Permissions')}
        </button>
        <button onClick={() => onResetPwd(admin)} className="flex-1 py-2.5 text-xs font-semibold text-gray-500 hover:bg-gray-50 transition-colors">
          {t('كلمة مرور', 'Reset Pwd')}
        </button>
        <button onClick={() => onToggle(admin)} className={`flex-1 py-2.5 text-xs font-semibold transition-colors ${admin.user_is_active ? 'text-orange-600 hover:bg-orange-50' : 'text-green-600 hover:bg-green-50'}`}>
          {admin.user_is_active ? t('إيقاف', 'Block') : t('تفعيل', 'Activate')}
        </button>
        <button onClick={() => onDelete(admin)} className="flex-1 py-2.5 text-xs font-semibold text-red-500 hover:bg-red-50 transition-colors">
          {t('حذف', 'Delete')}
        </button>
      </div>
    </div>
  );
}

function CreateAdminModal({ open, onClose, lang, permissionData, branches }) {
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [form, setForm] = useState({
    phone: '', full_name: '', email: '', password: '',
    preset_role: 'manager', is_super_admin: false,
    custom_permissions: [], allowed_branch_ids: [], notes: '',
  });
  const [step, setStep] = useState(1); // 1=account, 2=permissions, 3=access

  const createMutation = useMutation({
    mutationFn: (data) => api.post('/auth/superadmin/admins/create/', data).then(r => r.data),
    onSuccess: () => {
      qc.invalidateQueries(['admin-list']);
      toast.success(t('تم إنشاء الحساب بنجاح', 'Admin account created'));
      onClose();
      setForm({ phone:'', full_name:'', email:'', password:'', preset_role:'manager',
                is_super_admin:false, custom_permissions:[], allowed_branch_ids:[], notes:'' });
      setStep(1);
    },
    onError: (e) => toast.error(e.response?.data?.phone?.[0] || t('حدث خطأ', 'Error occurred')),
  });

  const togglePerm = (perm) => {
    setForm(f => ({
      ...f,
      custom_permissions: f.custom_permissions.includes(perm)
        ? f.custom_permissions.filter(p => p !== perm)
        : [...f.custom_permissions, perm]
    }));
  };

  const applyPreset = (role) => {
    setForm(f => ({ ...f, preset_role: role }));
    if (role !== 'custom' && permissionData?.preset_roles?.[role]) {
      setForm(f => ({
        ...f,
        preset_role: role,
        custom_permissions: permissionData.preset_roles[role].permissions,
        is_super_admin: role === 'super_admin',
      }));
    }
  };

  if (!open) return null;

  const groupedPerms = permissionData?.permission_groups || {};

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-3xl w-full max-w-2xl max-h-[90vh] flex flex-col shadow-2xl">
        {/* Header */}
        <div className="p-6 border-b border-gray-100 flex items-center justify-between flex-shrink-0">
          <div>
            <h2 className="text-xl font-bold text-[#0D2440] font-serif">
              {t('إنشاء مدير جديد', 'Create New Admin')}
            </h2>
            <div className="flex gap-2 mt-2">
              {[1, 2, 3].map(s => (
                <div key={s} className={`flex items-center gap-1.5`}>
                  <div className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${step >= s ? 'bg-[#2E5E99] text-white' : 'bg-gray-100 text-gray-400'}`}>{s}</div>
                  <span className="text-xs text-gray-500">
                    {s === 1 ? t('البيانات', 'Account') : s === 2 ? t('الصلاحيات', 'Permissions') : t('الوصول', 'Access')}
                  </span>
                  {s < 3 && <div className="w-8 h-px bg-gray-200 mx-1" />}
                </div>
              ))}
            </div>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-2xl w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100">×</button>
        </div>

        <div className="flex-1 overflow-y-auto p-6">
          {/* Step 1: Account Info */}
          {step === 1 && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="col-span-2">
                  <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">
                    {t('الاسم الكامل', 'Full Name')} *
                  </label>
                  <input value={form.full_name} onChange={e => setForm(f => ({...f, full_name: e.target.value}))}
                    placeholder={t('اسم المدير', 'Admin name')}
                    className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm" />
                </div>
                <div>
                  <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">
                    {t('رقم الهاتف', 'Phone')} *
                  </label>
                  <input value={form.phone} onChange={e => setForm(f => ({...f, phone: e.target.value}))}
                    placeholder="01000000000"
                    className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm font-mono" />
                </div>
                <div>
                  <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">
                    {t('كلمة المرور', 'Password')} *
                  </label>
                  <input value={form.password} onChange={e => setForm(f => ({...f, password: e.target.value}))}
                    type="password" placeholder="••••••••"
                    className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm" />
                </div>
                <div className="col-span-2">
                  <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">
                    {t('البريد الإلكتروني', 'Email')} ({t('اختياري', 'Optional')})
                  </label>
                  <input value={form.email} onChange={e => setForm(f => ({...f, email: e.target.value}))}
                    placeholder="admin@example.com" type="email"
                    className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm" />
                </div>
                <div className="col-span-2">
                  <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">
                    {t('ملاحظات', 'Notes')} ({t('اختياري', 'Optional')})
                  </label>
                  <textarea value={form.notes} onChange={e => setForm(f => ({...f, notes: e.target.value}))}
                    placeholder={t('مثلاً: مسؤول عن فرع المعادي', 'e.g. Responsible for Maadi branch')}
                    rows={2}
                    className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm resize-none" />
                </div>
              </div>
            </div>
          )}

          {/* Step 2: Permissions */}
          {step === 2 && (
            <div className="space-y-4">
              {/* Preset role selector */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                  {t('اختر دوراً محدداً أو خصص الصلاحيات', 'Choose a preset role or customize')}
                </p>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                  {Object.entries(PRESET_ROLES_UI).map(([key, val]) => (
                    <button key={key} onClick={() => applyPreset(key)}
                      className={`p-3 rounded-xl border-2 text-start transition-all ${form.preset_role === key ? 'border-[#2E5E99] bg-[#E7F0FA]' : 'border-gray-100 hover:border-gray-300'}`}>
                      <div className="text-lg mb-1">{val.badge}</div>
                      <div className="text-xs font-bold text-[#0D2440]">{lang === 'ar' ? val.ar : val.en}</div>
                    </button>
                  ))}
                </div>
              </div>

              {/* Super Admin toggle */}
              <div className="flex items-center justify-between bg-red-50 border-2 border-red-200 rounded-xl p-4">
                <div>
                  <div className="font-bold text-red-700 text-sm">👑 {t('مدير عام', 'Super Admin')}</div>
                  <div className="text-xs text-red-500 mt-0.5">
                    {t('وصول كامل لجميع الإعدادات وإدارة المديرين', 'Full access including admin management')}
                  </div>
                </div>
                <button onClick={() => setForm(f => ({ ...f, is_super_admin: !f.is_super_admin, preset_role: !f.is_super_admin ? 'super_admin' : 'custom' }))}
                  className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors ${form.is_super_admin ? 'bg-red-500' : 'bg-gray-200'}`}>
                  <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${form.is_super_admin ? 'translate-x-6' : 'translate-x-1'}`} />
                </button>
              </div>

              {/* Permission groups */}
              {!form.is_super_admin && (
                <div className="space-y-3">
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider">
                    {t('الصلاحيات التفصيلية', 'Detailed Permissions')}
                  </p>
                  {Object.entries(groupedPerms).map(([group, perms]) => {
                    const groupMeta = GROUPS[group] || { ar: group, en: group, color: 'bg-gray-50 border-gray-200' };
                    const allChecked = perms.every(p => form.custom_permissions.includes(p));
                    return (
                      <div key={group} className={`border-2 rounded-xl p-3 ${groupMeta.color}`}>
                        <div className="flex items-center justify-between mb-2">
                          <span className="text-xs font-bold text-[#0D2440] uppercase tracking-wider">
                            {lang === 'ar' ? groupMeta.ar : groupMeta.en}
                          </span>
                          <button onClick={() => {
                            if (allChecked) {
                              setForm(f => ({ ...f, custom_permissions: f.custom_permissions.filter(p => !perms.includes(p)) }));
                            } else {
                              setForm(f => ({ ...f, custom_permissions: [...new Set([...f.custom_permissions, ...perms])] }));
                            }
                          }} className="text-xs text-[#2E5E99] font-semibold">
                            {allChecked ? t('إلغاء الكل', 'Deselect All') : t('تحديد الكل', 'Select All')}
                          </button>
                        </div>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-0.5">
                          {perms.map(perm => (
                            <PermissionToggle key={perm} perm={perm}
                              checked={form.custom_permissions.includes(perm)}
                              onChange={togglePerm} lang={lang} />
                          ))}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {/* Step 3: Branch access */}
          {step === 3 && (
            <div className="space-y-4">
              <div className="bg-blue-50 border border-blue-200 rounded-xl p-4">
                <div className="font-semibold text-[#0D2440] mb-1">
                  🏪 {t('تحديد الفروع المسموح بها', 'Allowed Branch Access')}
                </div>
                <p className="text-xs text-gray-500">
                  {t('اتركه فارغاً للوصول لجميع الفروع', 'Leave empty for access to all branches')}
                </p>
              </div>
              <div className="space-y-2">
                {(branches || []).map(branch => (
                  <label key={branch.id} className="flex items-center gap-3 p-3 bg-white border border-gray-100 rounded-xl cursor-pointer hover:border-[#2E5E99] transition-colors">
                    <input type="checkbox"
                      checked={form.allowed_branch_ids.includes(branch.id)}
                      onChange={() => setForm(f => ({
                        ...f,
                        allowed_branch_ids: f.allowed_branch_ids.includes(branch.id)
                          ? f.allowed_branch_ids.filter(id => id !== branch.id)
                          : [...f.allowed_branch_ids, branch.id]
                      }))}
                      className="w-4 h-4 accent-[#2E5E99]" />
                    <div>
                      <div className="font-semibold text-[#0D2440] text-sm">{branch.name_ar || branch.name}</div>
                      <div className="text-xs text-gray-400">{branch.address}</div>
                    </div>
                  </label>
                ))}
              </div>

              {/* Summary */}
              <div className="bg-[#E7F0FA] rounded-xl p-4 border border-[#7BA4D0]">
                <div className="font-bold text-[#0D2440] text-sm mb-2">📋 {t('ملخص الحساب', 'Account Summary')}</div>
                <div className="space-y-1 text-xs text-gray-600">
                  <div>👤 {form.full_name} · {form.phone}</div>
                  <div>🎭 {lang === 'ar' ? PRESET_ROLES_UI[form.preset_role]?.ar : PRESET_ROLES_UI[form.preset_role]?.en}</div>
                  <div>🔐 {form.is_super_admin ? t('كل الصلاحيات', 'All permissions') : `${form.custom_permissions.length} ${t('صلاحية', 'permissions')}`}</div>
                  <div>🏪 {form.allowed_branch_ids.length === 0 ? t('كل الفروع', 'All branches') : `${form.allowed_branch_ids.length} ${t('فرع', 'branches')}`}</div>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-5 border-t border-gray-100 flex gap-3 flex-shrink-0">
          {step > 1 && (
            <button onClick={() => setStep(s => s - 1)}
              className="px-5 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold hover:bg-gray-50 transition-colors">
              {t('السابق', 'Back')}
            </button>
          )}
          <button onClick={onClose}
            className="px-5 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold hover:bg-gray-50 transition-colors">
            {t('إلغاء', 'Cancel')}
          </button>
          {step < 3 ? (
            <button onClick={() => setStep(s => s + 1)}
              disabled={step === 1 && (!form.phone || !form.full_name || !form.password)}
              className="flex-1 bg-[#2E5E99] hover:bg-[#0D2440] text-white py-2.5 rounded-xl text-sm font-bold disabled:opacity-40 transition-colors">
              {t('التالي', 'Next')} →
            </button>
          ) : (
            <button onClick={() => createMutation.mutate(form)}
              disabled={createMutation.isPending}
              className="flex-1 bg-[#0D2440] hover:bg-[#2E5E99] text-white py-2.5 rounded-xl text-sm font-bold disabled:opacity-60 transition-colors">
              {createMutation.isPending ? '...' : `✅ ${t('إنشاء الحساب', 'Create Account')}`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function EditPermissionsModal({ admin, open, onClose, lang, permissionData, branches }) {
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [perms, setPerms] = useState(admin?.permissions || []);
  const [isSuperAdmin, setIsSuperAdmin] = useState(admin?.is_super_admin || false);
  const [branchIds, setBranchIds] = useState(admin?.allowed_branch_ids || []);

  const updateMutation = useMutation({
    mutationFn: (data) => api.patch(`/auth/superadmin/admins/${admin?.id}/permissions/`, data).then(r => r.data),
    onSuccess: () => {
      qc.invalidateQueries(['admin-list']);
      toast.success(t('تم تحديث الصلاحيات', 'Permissions updated'));
      onClose();
    },
  });

  if (!open || !admin) return null;
  const groupedPerms = permissionData?.permission_groups || {};

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-3xl w-full max-w-xl max-h-[90vh] flex flex-col shadow-2xl">
        <div className="p-5 border-b border-gray-100 flex items-center justify-between flex-shrink-0">
          <div>
            <h2 className="text-lg font-bold text-[#0D2440] font-serif">{t('تعديل الصلاحيات', 'Edit Permissions')}</h2>
            <p className="text-sm text-gray-400">{admin.user_name} · {admin.user_phone}</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-2xl w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100">×</button>
        </div>
        <div className="flex-1 overflow-y-auto p-5 space-y-4">
          {/* Preset buttons */}
          <div className="grid grid-cols-3 gap-2">
            {Object.entries(PRESET_ROLES_UI).filter(([k]) => k !== 'custom').map(([key, val]) => (
              <button key={key} onClick={() => {
                const presetPerms = permissionData?.preset_roles?.[key]?.permissions || [];
                setPerms(presetPerms);
                setIsSuperAdmin(key === 'super_admin');
              }}
                className="p-2 rounded-xl border border-gray-100 text-xs font-semibold text-[#0D2440] hover:border-[#2E5E99] hover:bg-[#E7F0FA] transition-colors text-center">
                {val.badge} {lang === 'ar' ? val.ar : val.en}
              </button>
            ))}
          </div>

          <div className="flex items-center justify-between bg-red-50 border border-red-200 rounded-xl p-3">
            <span className="text-sm font-bold text-red-700">👑 {t('مدير عام', 'Super Admin')}</span>
            <button onClick={() => setIsSuperAdmin(!isSuperAdmin)}
              className={`relative inline-flex h-6 w-10 items-center rounded-full transition-colors ${isSuperAdmin ? 'bg-red-500' : 'bg-gray-200'}`}>
              <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${isSuperAdmin ? 'translate-x-5' : 'translate-x-1'}`} />
            </button>
          </div>

          {!isSuperAdmin && Object.entries(groupedPerms).map(([group, groupPerms]) => {
            const gm = GROUPS[group] || { ar: group, en: group, color: 'bg-gray-50 border-gray-200' };
            return (
              <div key={group} className={`border-2 rounded-xl p-3 ${gm.color}`}>
                <div className="text-xs font-bold text-[#0D2440] uppercase mb-2">
                  {lang === 'ar' ? gm.ar : gm.en}
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-0.5">
                  {groupPerms.map(perm => (
                    <PermissionToggle key={perm} perm={perm}
                      checked={perms.includes(perm)}
                      onChange={(p) => setPerms(ps => ps.includes(p) ? ps.filter(x => x !== p) : [...ps, p])}
                      lang={lang} />
                  ))}
                </div>
              </div>
            );
          })}
        </div>
        <div className="p-4 border-t border-gray-100 flex gap-3 flex-shrink-0">
          <button onClick={onClose} className="px-5 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold">{t('إلغاء', 'Cancel')}</button>
          <button onClick={() => updateMutation.mutate({ custom_permissions: perms, is_super_admin: isSuperAdmin, allowed_branch_ids: branchIds })}
            disabled={updateMutation.isPending}
            className="flex-1 bg-[#2E5E99] text-white py-2.5 rounded-xl text-sm font-bold disabled:opacity-60">
            {updateMutation.isPending ? '...' : t('حفظ الصلاحيات', 'Save Permissions')}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function AdminManagementPage() {
  const { lang } = useOutletContext();
  const t = (ar, en) => lang === 'ar' ? ar : en;
  const qc = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);
  const [editAdmin, setEditAdmin] = useState(null);
  const [resetAdmin, setResetAdmin] = useState(null);
  const [newPassword, setNewPassword] = useState('');
  const [activeTab, setActiveTab] = useState('admins');

  const { data: admins, isLoading } = useQuery({
    queryKey: ['admin-list'],
    queryFn: () => api.get('/auth/superadmin/admins/').then(r => r.data),
  });

  const { data: permissionData } = useQuery({
    queryKey: ['my-permissions'],
    queryFn: () => api.get('/auth/superadmin/my-permissions/').then(r => r.data),
  });

  const { data: branchesData } = useQuery({
    queryKey: ['branches-admin'],
    queryFn: () => api.get('/branches/admin/').then(r => r.data),
  });

  const { data: auditLog } = useQuery({
    queryKey: ['audit-log'],
    queryFn: () => api.get('/auth/superadmin/audit-log/').then(r => r.data),
    enabled: activeTab === 'audit',
  });

  const toggleMutation = useMutation({
    mutationFn: (pk) => api.post(`/auth/superadmin/admins/${pk}/toggle/`).then(r => r.data),
    onSuccess: (data) => { qc.invalidateQueries(['admin-list']); toast.success(data.message); },
  });

  const deleteMutation = useMutation({
    mutationFn: (pk) => api.delete(`/auth/superadmin/admins/${pk}/delete/`).then(r => r.data),
    onSuccess: (data) => { qc.invalidateQueries(['admin-list']); toast.success(data.message); },
  });

  const resetPwdMutation = useMutation({
    mutationFn: ({ pk, password }) => api.post(`/auth/superadmin/admins/${pk}/reset-password/`, { new_password: password }),
    onSuccess: () => { setResetAdmin(null); setNewPassword(''); toast.success(t('تم تغيير كلمة المرور', 'Password reset')); },
  });

  const adminList = Array.isArray(admins) ? admins : (admins?.results || []);
  const branches = Array.isArray(branchesData) ? branchesData : (branchesData?.results || []);

  const ACTION_ICONS = { create: '➕', update: '✏️', delete: '🗑️', login: '🔐', block: '🚫', settle: '💵', assign: '🛵', notify: '🔔', export: '📤' };

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-[#0D2440] font-serif flex items-center gap-2">
            👑 {t('إدارة المديرين', 'Admin Management')}
          </h1>
          <p className="text-gray-500 text-sm mt-1">
            {t('صلاحيات المدير العام فقط', 'Super Admin access only')}
          </p>
        </div>
        <button onClick={() => setShowCreate(true)}
          className="bg-[#0D2440] hover:bg-[#2E5E99] text-white px-5 py-2.5 rounded-xl font-bold text-sm transition-colors flex items-center gap-2">
          + {t('إنشاء مدير جديد', 'New Admin')}
        </button>
      </div>

      {/* Tabs */}
      <div className="flex gap-2">
        {[
          { key: 'admins', ar: 'المديرون', en: 'Admins', count: adminList.length },
          { key: 'audit', ar: 'سجل الإجراءات', en: 'Audit Log' },
        ].map(tab => (
          <button key={tab.key} onClick={() => setActiveTab(tab.key)}
            className={`px-5 py-2.5 rounded-xl text-sm font-semibold transition-colors flex items-center gap-2 ${activeTab === tab.key ? 'bg-[#0D2440] text-white' : 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'}`}>
            {lang === 'ar' ? tab.ar : tab.en}
            {tab.count !== undefined && <span className="bg-white/20 rounded-full px-2 py-0.5 text-xs">{tab.count}</span>}
          </button>
        ))}
      </div>

      {/* Admins Grid */}
      {activeTab === 'admins' && (
        <div>
          {isLoading ? (
            <div className="flex items-center justify-center h-48">
              <div className="animate-spin w-8 h-8 border-4 border-[#2E5E99] border-t-transparent rounded-full" />
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
              {adminList.map(admin => (
                <AdminCard key={admin.id} admin={admin} lang={lang}
                  onToggle={(a) => toggleMutation.mutate(a.id)}
                  onEdit={(a) => setEditAdmin(a)}
                  onDelete={(a) => {
                    if (confirm(t(`حذف ${a.user_name}؟`, `Delete ${a.user_name}?`))) {
                      deleteMutation.mutate(a.id);
                    }
                  }}
                  onResetPwd={(a) => setResetAdmin(a)}
                />
              ))}
              {adminList.length === 0 && (
                <div className="col-span-3 text-center py-20 text-gray-400">
                  <div className="text-5xl mb-3">👑</div>
                  <div className="font-semibold">{t('لا يوجد مديرون بعد', 'No admins yet')}</div>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* Audit Log */}
      {activeTab === 'audit' && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100">
                <tr>
                  {[t('المدير', 'Admin'), t('الإجراء', 'Action'), t('النوع', 'Resource'), t('التفاصيل', 'Description'), t('الوقت', 'Time'), t('IP', 'IP')].map(h => (
                    <th key={h} className="px-4 py-3 text-start text-xs font-semibold text-gray-500 uppercase">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {(auditLog?.results || []).map(log => (
                  <tr key={log.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3 font-semibold text-[#0D2440] text-xs">{log.admin_name}</td>
                    <td className="px-4 py-3"><span className="text-sm">{ACTION_ICONS[log.action] || '📝'}</span> <span className="text-xs font-mono text-gray-600">{log.action}</span></td>
                    <td className="px-4 py-3 text-xs font-mono text-[#2E5E99] bg-[#E7F0FA] rounded px-2 py-0.5 inline-block">{log.resource_type}</td>
                    <td className="px-4 py-3 text-xs text-gray-600 max-w-xs truncate">{log.description}</td>
                    <td className="px-4 py-3 text-xs text-gray-400 whitespace-nowrap">
                      {new Date(log.created_at).toLocaleString(lang === 'ar' ? 'ar-EG' : 'en-US')}
                    </td>
                    <td className="px-4 py-3 text-xs font-mono text-gray-400">{log.ip_address || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {(auditLog?.results || []).length === 0 && (
              <div className="text-center py-12 text-gray-400">
                <div className="text-4xl mb-3">📜</div>
                <div>{t('لا توجد إجراءات مسجلة', 'No audit logs yet')}</div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Modals */}
      <CreateAdminModal open={showCreate} onClose={() => setShowCreate(false)}
        lang={lang} permissionData={permissionData} branches={branches} />

      <EditPermissionsModal admin={editAdmin} open={!!editAdmin} onClose={() => setEditAdmin(null)}
        lang={lang} permissionData={permissionData} branches={branches} />

      {/* Reset Password Modal */}
      {resetAdmin && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl">
            <h3 className="font-bold text-[#0D2440] mb-1">{t('إعادة تعيين كلمة المرور', 'Reset Password')}</h3>
            <p className="text-sm text-gray-400 mb-4">{resetAdmin.user_name}</p>
            <input value={newPassword} onChange={e => setNewPassword(e.target.value)}
              type="password" placeholder={t('كلمة مرور جديدة (6+ أحرف)', 'New password (6+ chars)')}
              className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm mb-4" />
            <div className="flex gap-3">
              <button onClick={() => { setResetAdmin(null); setNewPassword(''); }}
                className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-semibold">{t('إلغاء', 'Cancel')}</button>
              <button onClick={() => resetPwdMutation.mutate({ pk: resetAdmin.id, password: newPassword })}
                disabled={newPassword.length < 6 || resetPwdMutation.isPending}
                className="flex-1 bg-[#F97316] text-white rounded-xl py-2.5 text-sm font-bold disabled:opacity-40">
                {t('تغيير', 'Reset')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
