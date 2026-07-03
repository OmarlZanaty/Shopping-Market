import React, { useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { productApi } from '../../services/api';
import toast from 'react-hot-toast';

/**
 * Excel/CSV product import modal.
 * Flow: pick file → automatic dry-run preview (new/updated/errors) → confirm import.
 * Also offers template download, full product export, and import history.
 */
export default function ImportProductsModal({ lang, onClose }) {
  const t = (ar, en) => (lang === 'ar' ? ar : en);
  const qc = useQueryClient();
  const fileRef = useRef(null);

  const [tab, setTab] = useState('import'); // import | history
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);   // dry-run result
  const [result, setResult] = useState(null);     // real import result
  const [busy, setBusy] = useState(false);

  const { data: history } = useQuery({
    queryKey: ['product-import-history'],
    queryFn: () => productApi.importHistory().then(r => r.data),
    enabled: tab === 'history',
  });

  const downloadBlob = (blob, filename) => {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  };

  const downloadTemplate = async (includeProducts) => {
    try {
      const res = await productApi.importTemplate(includeProducts);
      downloadBlob(res.data, includeProducts ? 'products_export.xlsx' : 'product_import_template.xlsx');
    } catch {
      toast.error(t('فشل التحميل', 'Download failed'));
    }
  };

  const runDryRun = async (f) => {
    setBusy(true);
    setPreview(null);
    setResult(null);
    try {
      const res = await productApi.import(f, { dryRun: true });
      setPreview(res.data);
    } catch (e) {
      toast.error(e?.message || t('فشل قراءة الملف', 'Could not read the file'));
      setFile(null);
    } finally {
      setBusy(false);
    }
  };

  const onPickFile = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    setFile(f);
    runDryRun(f);
  };

  const confirmImport = async () => {
    if (!file) return;
    setBusy(true);
    try {
      const res = await productApi.import(file, { dryRun: false });
      setResult(res.data);
      setPreview(null);
      qc.invalidateQueries(['admin-products']);
      qc.invalidateQueries(['product-import-history']);
      toast.success(t('تم الاستيراد بنجاح ✅', 'Import completed ✅'));
    } catch (e) {
      toast.error(e?.message || t('فشل الاستيراد', 'Import failed'));
    } finally {
      setBusy(false);
    }
  };

  const reset = () => {
    setFile(null);
    setPreview(null);
    setResult(null);
    if (fileRef.current) fileRef.current.value = '';
  };

  const IssuesTable = ({ items, tone }) => (
    <div className="max-h-44 overflow-y-auto border border-gray-100 rounded-xl">
      <table className="w-full text-xs">
        <thead className="bg-gray-50 sticky top-0">
          <tr>
            <th className="px-3 py-2 text-start text-gray-500">{t('صف', 'Row')}</th>
            <th className="px-3 py-2 text-start text-gray-500">{t('باركود', 'Barcode')}</th>
            <th className="px-3 py-2 text-start text-gray-500">{t('السبب', 'Reason')}</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-50">
          {items.map((e, i) => (
            <tr key={i}>
              <td className="px-3 py-1.5">{e.row || '—'}</td>
              <td className="px-3 py-1.5 font-mono">{e.barcode || '—'}</td>
              <td className={`px-3 py-1.5 ${tone}`}>{e.reason}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );

  const Summary = ({ data, isPreview }) => (
    <div className="space-y-3">
      <div className="grid grid-cols-3 gap-3 text-center">
        <div className="bg-green-50 border border-green-100 rounded-xl py-3">
          <div className="text-2xl font-bold text-green-600">{data.created}</div>
          <div className="text-xs text-gray-500">{isPreview ? t('سيتم إنشاؤها', 'Will be created') : t('تم إنشاؤها', 'Created')}</div>
        </div>
        <div className="bg-blue-50 border border-blue-100 rounded-xl py-3">
          <div className="text-2xl font-bold text-[#2E5E99]">{data.updated}</div>
          <div className="text-xs text-gray-500">{isPreview ? t('سيتم تحديثها', 'Will be updated') : t('تم تحديثها', 'Updated')}</div>
        </div>
        <div className="bg-red-50 border border-red-100 rounded-xl py-3">
          <div className="text-2xl font-bold text-red-500">{data.errors.length}</div>
          <div className="text-xs text-gray-500">{t('أخطاء', 'Errors')}</div>
        </div>
      </div>
      {data.errors.length > 0 && <IssuesTable items={data.errors} tone="text-red-600" />}
      {data.warnings?.length > 0 && <IssuesTable items={data.warnings} tone="text-amber-600" />}
    </div>
  );

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-white rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}
      >
        {/* Header + tabs */}
        <div className="px-6 pt-5 pb-3 border-b border-gray-100 flex items-center justify-between">
          <h2 className="text-lg font-bold text-[#0D2440]">
            📥 {t('استيراد المنتجات من Excel', 'Import Products from Excel')}
          </h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
        </div>
        <div className="px-6 pt-3 flex gap-2">
          {[['import', t('استيراد', 'Import')], ['history', t('السجل', 'History')]].map(([key, label]) => (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`px-4 py-1.5 rounded-lg text-sm font-semibold transition-colors
                ${tab === key ? 'bg-[#2E5E99] text-white' : 'text-gray-500 hover:bg-gray-100'}`}
            >
              {label}
            </button>
          ))}
        </div>

        {tab === 'import' ? (
          <div className="p-6 space-y-4">
            {/* Template / export */}
            <div className="flex gap-2 flex-wrap text-sm">
              <button onClick={() => downloadTemplate(false)}
                className="border border-gray-200 hover:bg-gray-50 px-4 py-2 rounded-xl font-semibold text-[#2E5E99]">
                ⬇️ {t('تحميل القالب الفارغ', 'Download blank template')}
              </button>
              <button onClick={() => downloadTemplate(true)}
                className="border border-gray-200 hover:bg-gray-50 px-4 py-2 rounded-xl font-semibold text-[#2E5E99]">
                ⬇️ {t('تصدير المنتجات الحالية', 'Export current products')}
              </button>
            </div>

            <p className="text-xs text-gray-500 leading-relaxed">
              {t(
                'الباركود هو المفتاح: باركود موجود = تحديث المنتج، باركود جديد = إنشاء منتج. الخلايا الفارغة تُبقي القيمة الحالية دون تغيير.',
                'Barcode is the key: existing barcode = update, new barcode = create. Blank cells keep the current value unchanged.'
              )}
            </p>

            {/* File picker */}
            {!result && (
              <label className="block border-2 border-dashed border-gray-200 hover:border-[#2E5E99] rounded-2xl p-8 text-center cursor-pointer transition-colors">
                <input ref={fileRef} type="file" accept=".xlsx,.csv" className="hidden" onChange={onPickFile} />
                <div className="text-3xl mb-2">📄</div>
                <div className="font-semibold text-[#0D2440] text-sm">
                  {file ? file.name : t('اضغط لاختيار ملف .xlsx أو .csv', 'Click to choose an .xlsx or .csv file')}
                </div>
              </label>
            )}

            {busy && (
              <div className="flex items-center justify-center py-6">
                <div className="animate-spin w-7 h-7 border-4 border-[#2E5E99] border-t-transparent rounded-full" />
              </div>
            )}

            {/* Dry-run preview */}
            {preview && !busy && (
              <>
                <div className="text-sm font-bold text-[#0D2440]">
                  {t('معاينة قبل التأكيد', 'Preview before confirming')} — {preview.total_rows} {t('صف', 'rows')}
                </div>
                <Summary data={preview} isPreview />
                <div className="flex gap-2 justify-end">
                  <button onClick={reset} className="px-4 py-2 rounded-xl text-sm font-semibold text-gray-500 hover:bg-gray-100">
                    {t('إلغاء', 'Cancel')}
                  </button>
                  <button
                    onClick={confirmImport}
                    disabled={preview.created + preview.updated === 0}
                    className="bg-[#2FBE8F] hover:bg-emerald-600 disabled:opacity-40 text-white px-5 py-2 rounded-xl text-sm font-bold"
                  >
                    ✅ {t(`تأكيد الاستيراد (${preview.created + preview.updated})`, `Confirm Import (${preview.created + preview.updated})`)}
                  </button>
                </div>
              </>
            )}

            {/* Final result */}
            {result && !busy && (
              <>
                <div className="text-sm font-bold text-[#0D2440]">{t('نتيجة الاستيراد', 'Import result')}</div>
                <Summary data={result} isPreview={false} />
                <div className="flex justify-end">
                  <button onClick={reset} className="border border-gray-200 hover:bg-gray-50 px-4 py-2 rounded-xl text-sm font-semibold text-[#2E5E99]">
                    {t('استيراد ملف آخر', 'Import another file')}
                  </button>
                </div>
              </>
            )}
          </div>
        ) : (
          /* History tab */
          <div className="p-6">
            {(history || []).length === 0 ? (
              <div className="text-center py-10 text-gray-400 text-sm">{t('لا توجد عمليات استيراد سابقة', 'No previous imports')}</div>
            ) : (
              <div className="space-y-2">
                {history.map(job => (
                  <div key={job.id} className="border border-gray-100 rounded-xl px-4 py-3 text-sm">
                    <div className="flex items-center justify-between flex-wrap gap-2">
                      <div className="font-semibold text-[#0D2440]">📄 {job.filename}</div>
                      <div className="text-xs text-gray-400">
                        {new Date(job.created_at).toLocaleString(lang === 'ar' ? 'ar-EG' : 'en-GB')} · {job.user}
                      </div>
                    </div>
                    <div className="flex gap-4 mt-1 text-xs">
                      <span className="text-green-600 font-semibold">+{job.created} {t('جديد', 'new')}</span>
                      <span className="text-[#2E5E99] font-semibold">↻ {job.updated} {t('محدث', 'updated')}</span>
                      {job.error_count > 0 && (
                        <span className="text-red-500 font-semibold">⚠ {job.error_count} {t('أخطاء', 'errors')}</span>
                      )}
                    </div>
                    {job.errors?.length > 0 && (
                      <details className="mt-2">
                        <summary className="text-xs text-red-500 cursor-pointer">{t('عرض الأخطاء', 'Show errors')}</summary>
                        <div className="mt-2"><IssuesTable items={job.errors} tone="text-red-600" /></div>
                      </details>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
