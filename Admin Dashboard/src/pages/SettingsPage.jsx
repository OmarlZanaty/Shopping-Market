import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import { notificationApi } from '../services/api';
import toast from 'react-hot-toast';

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
              <div className="font-semibold text-[#0D2440] text-sm">{setting.key}</div>
              <div className="text-xs text-gray-400">{setting.description}</div>
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
