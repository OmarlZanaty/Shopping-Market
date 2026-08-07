import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useOutletContext } from 'react-router-dom';
import toast from 'react-hot-toast';
import { reportApi } from '../services/api';
import { apiError } from '../utils/apiError';

/**
 * Reports — one page over the whole /api/v1/reports/* family.
 *
 * Every report answers the same contract (from_date, to_date, page, limit, and
 * ?export=xlsx|pdf), so the page is a picker plus one table rather than
 * thirteen bespoke screens. Columns are read off the returned rows and labelled
 * from the dictionary below, which keeps a new backend report working here the
 * day it is added — an unknown key degrades to its own name, not a crash.
 */

// The three the owner asked for come first; the rest follow in the backend's
// own order so nothing is hidden behind a "more" affordance.
const REPORTS = [
  ['sales-summary',      'إجمالي المبيعات',     'Sales Summary'],
  ['sales',              'تفاصيل المبيعات',     'Sales Details'],
  ['out-of-stock',       'نواقص الأصناف',       'Out of Stock'],
  ['daily-revenue',      'الإيراد اليومي',      'Daily Revenue'],
  ['payments',           'المدفوعات',           'Payments'],
  ['cancelled-orders',   'الطلبات الملغاة',     'Cancelled Orders'],
  ['preparation-time',   'وقت التحضير',         'Preparation Time'],
  ['top-products',       'الأكثر مبيعاً',       'Top Products'],
  ['top-customers',      'أفضل العملاء',        'Top Customers'],
  ['driver-performance', 'أداء المناديب',       'Driver Performance'],
  ['inventory',          'المخزون',             'Inventory'],
  ['adjustments',        'تعديلات الطلبات',     'Order Adjustments'],
  ['promotions',         'العروض',              'Promotions'],
];

const LABELS = {
  order_number: ['رقم الاوردر', 'Order #'],
  date: ['التاريخ', 'Date'],
  amount: ['القيمة', 'Amount'],
  payment_method: ['كاش / اون لاين', 'Cash / Online'],
  preparer: ['المحضر', 'Preparer'],
  prep_mins: ['وقت التحضير (دقيقة)', 'Prep Time (min)'],
  points_earned: ['نقاط الولاء', 'Loyalty Points'],
  items_count: ['عدد المنتجات', 'Products'],
  product: ['الصنف', 'Product'],
  barcode: ['باركود الصنف', 'Barcode'],
  category: ['القسم', 'Category'],
  qty: ['الكمية', 'Qty'],
  unit_price: ['سعر الوحدة', 'Unit Price'],
  line_total: ['الإجمالي', 'Line Total'],
  customer: ['اسم العميل', 'Customer'],
  phone: ['رقم الموبايل', 'Mobile'],
  address: ['العنوان', 'Address'],
  waitlist_count: ['قائمة الانتظار', 'Waitlist'],
  driver: ['المندوب', 'Driver'],
  reason: ['السبب', 'Reason'],
  cancelled_by: ['ألغاه', 'Cancelled By'],
  duration_mins: ['المدة (دقيقة)', 'Duration (min)'],
  accepted_at: ['وقت القبول', 'Accepted'],
  prepared_at: ['وقت التحضير', 'Prepared'],
  qty_sold: ['الكمية المباعة', 'Qty Sold'],
  revenue: ['الإيراد', 'Revenue'],
  orders: ['الطلبات', 'Orders'],
  orders_completed: ['طلبات مكتملة', 'Completed'],
  order_count: ['عدد الطلبات', 'Orders'],
  avg_delivery_mins: ['متوسط التوصيل (دقيقة)', 'Avg Delivery (min)'],
  avg_rating: ['متوسط التقييم', 'Avg Rating'],
  avg_order_value: ['متوسط قيمة الطلب', 'Avg Order Value'],
  cash_collected: ['المحصّل كاش', 'Cash Collected'],
  cash: ['كاش', 'Cash'],
  online: ['اون لاين', 'Online'],
  pos: ['ماكينة', 'POS'],
  wallet: ['محفظة', 'Wallet'],
  points: ['النقاط', 'Points'],
  points_value: ['قيمة النقاط', 'Points Value'],
  total_sales: ['إجمالي المبيعات', 'Total Sales'],
  total_spent: ['إجمالي الإنفاق', 'Total Spent'],
  total_discount: ['إجمالي الخصم', 'Total Discount'],
  delivery_fees: ['رسوم التوصيل', 'Delivery Fees'],
  opening_stock: ['رصيد أول', 'Opening'],
  closing_stock: ['رصيد آخر', 'Closing'],
  sold: ['المباع', 'Sold'],
  received: ['الوارد', 'Received'],
  name: ['الاسم', 'Name'],
  code: ['الكود', 'Code'],
  usage_count: ['مرات الاستخدام', 'Used'],
  discount: ['الخصم', 'Discount'],
  is_active: ['نشط', 'Active'],
  action_type: ['نوع التعديل', 'Action'],
  approval_status: ['حالة الموافقة', 'Approval'],
  price_diff: ['فرق السعر', 'Price Diff'],
  original: ['الأصلي', 'Original'],
  alternative: ['البديل', 'Alternative'],
  adjustments: ['التعديلات', 'Adjustments'],
};

const today = () => new Date().toISOString().slice(0, 10);
const daysAgo = (n) => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);

export default function ReportsPage() {
  const { lang } = useOutletContext() || { lang: 'ar' };
  const t = (ar, en) => (lang === 'ar' ? ar : en);

  const [slug, setSlug] = useState(REPORTS[0][0]);
  const [fromDate, setFromDate] = useState(daysAgo(30));
  const [toDate, setToDate] = useState(today());
  const [page, setPage] = useState(1);
  const [downloading, setDownloading] = useState('');

  const params = { from_date: fromDate, to_date: toDate, page, limit: 50 };

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['report', slug, fromDate, toDate, page],
    queryFn: () => reportApi.rows(slug, params).then((r) => r.data),
    keepPreviousData: true,
  });

  const rows = Array.isArray(data?.data) ? data.data : [];
  const total = data?.pagination?.total ?? rows.length;
  const totalPages = data?.pagination?.totalPages ?? 1;
  // Rows carry their own shape, so the header follows the data rather than a
  // second copy of every report's column list.
  const keys = rows.length ? Object.keys(rows[0]) : [];
  const label = (key) => {
    const pair = LABELS[key];
    if (pair) return lang === 'ar' ? pair[0] : pair[1];
    return key.replace(/_/g, ' ');
  };

  const download = async (format) => {
    setDownloading(format);
    try {
      const res = await reportApi.download(slug, params, format);
      const url = URL.createObjectURL(res.data);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${slug}_${fromDate}_${toDate}.${format}`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      toast.error(apiError(e, t('فشل التصدير', 'Export failed')));
    } finally {
      setDownloading('');
    }
  };

  const dateInput = 'bg-input-bg border border-input-border text-text rounded-xl px-3 py-2 text-sm';

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-bold text-text">📊 {t('التقارير', 'Reports')}</h1>
        <p className="text-xs text-muted mt-1">
          {t('اختر التقرير والفترة، ثم صدّره Excel أو PDF.',
             'Pick a report and a date range, then export it as Excel or PDF.')}
        </p>
      </div>

      {/* Report picker */}
      <div className="flex gap-2 flex-wrap">
        {REPORTS.map(([value, ar, en]) => (
          <button
            key={value}
            onClick={() => { setSlug(value); setPage(1); }}
            className={`px-3.5 py-1.5 rounded-full text-xs font-semibold border transition-colors ${
              slug === value
                ? 'bg-orange border-orange text-white'
                : 'border-divider text-muted hover:bg-card-hover hover:text-text'
            }`}
          >
            {lang === 'ar' ? ar : en}
          </button>
        ))}
      </div>

      {/* Range + export */}
      <div className="bg-card border border-divider rounded-2xl p-4 flex items-end gap-3 flex-wrap">
        <div>
          <label className="text-[10px] font-semibold text-muted uppercase block mb-1">
            {t('من', 'From')}
          </label>
          <input type="date" value={fromDate} className={dateInput}
                 onChange={(e) => { setFromDate(e.target.value); setPage(1); }} />
        </div>
        <div>
          <label className="text-[10px] font-semibold text-muted uppercase block mb-1">
            {t('إلى', 'To')}
          </label>
          <input type="date" value={toDate} className={dateInput}
                 onChange={(e) => { setToDate(e.target.value); setPage(1); }} />
        </div>
        <div className="flex-1" />
        <span className="text-xs text-muted pb-2">
          {total} {t('صف', 'rows')}
        </span>
        <button
          onClick={() => download('xlsx')}
          disabled={!!downloading || !rows.length}
          className="bg-green hover:bg-green/90 text-white px-4 py-2 rounded-xl text-sm font-bold disabled:opacity-40"
        >
          {downloading === 'xlsx' ? '...' : `📗 ${t('تصدير Excel', 'Export Excel')}`}
        </button>
        <button
          onClick={() => download('pdf')}
          disabled={!!downloading || !rows.length}
          className="bg-red hover:bg-red/90 text-white px-4 py-2 rounded-xl text-sm font-bold disabled:opacity-40"
        >
          {downloading === 'pdf' ? '...' : `📕 ${t('تصدير PDF', 'Export PDF')}`}
        </button>
      </div>

      {/* Table */}
      <div className="bg-card border border-divider rounded-2xl overflow-hidden">
        {isLoading ? (
          <div className="flex items-center justify-center h-40">
            <div className="animate-spin w-7 h-7 border-4 border-orange border-t-transparent rounded-full" />
          </div>
        ) : isError ? (
          <div className="p-6 text-center text-sm text-red">
            {apiError(error, t('تعذّر تحميل التقرير', 'Could not load the report'))}
          </div>
        ) : !rows.length ? (
          <div className="p-8 text-center text-sm text-muted">
            {t('لا توجد بيانات في هذه الفترة', 'No data in this period')}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-table-header">
                <tr>
                  {keys.map((key) => (
                    <th key={key} className="px-4 py-3 text-start text-[11px] font-semibold text-muted uppercase whitespace-nowrap">
                      {label(key)}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row, index) => (
                  <tr key={index} className="border-t border-divider hover:bg-card-hover">
                    {keys.map((key) => (
                      <td key={key} className="px-4 py-2.5 text-text whitespace-nowrap">
                        {row[key] === null || row[key] === undefined || row[key] === '' ? '—' : String(row[key])}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-3">
          <button
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="px-3 py-1.5 rounded-xl border border-divider text-text text-sm disabled:opacity-40"
          >
            {t('السابق', 'Previous')}
          </button>
          <span className="text-xs text-muted">{page} / {totalPages}</span>
          <button
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            disabled={page >= totalPages}
            className="px-3 py-1.5 rounded-xl border border-divider text-text text-sm disabled:opacity-40"
          >
            {t('التالي', 'Next')}
          </button>
        </div>
      )}
    </div>
  );
}
