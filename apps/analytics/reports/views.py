"""
12 spec reports. Each accepts: from_date, to_date, page, limit, export=xlsx|pdf.
All store-scoped via request.user.store_id (None = super admin sees all).
"""
from datetime import timedelta, datetime, date as _date
from decimal import Decimal

from rest_framework.views import APIView
from rest_framework import permissions
from django.db.models import (
    Sum, Count, Avg, F, Q, DecimalField, ExpressionWrapper,
)
from django.utils import timezone

from apps.orders.models import Order, OrderItem, OrderAdjustment, OrderRating
from apps.products.models import Product
from apps.users.models import PointsTransaction
from apps.core.permissions import IsAdminWriteOrSupportRead
from apps.core.scoping import scope_to_user
from apps.core.responses import paginated, ok
from .exporters import maybe_export


def _parse_date(s):
    if not s:
        return None
    try:
        if isinstance(s, (_date, datetime)):
            return s
        return datetime.strptime(s, '%Y-%m-%d').date()
    except (ValueError, TypeError):
        return None


def _date_range(request, default_days=30):
    from_d = _parse_date(request.query_params.get('from_date'))
    to_d = _parse_date(request.query_params.get('to_date'))
    if not from_d:
        from_d = (timezone.now() - timedelta(days=default_days)).date()
    if not to_d:
        to_d = timezone.now().date()
    return from_d, to_d


def _paginate(rows, request, default_limit=50):
    try:
        page = max(1, int(request.query_params.get('page', 1)))
        limit = min(int(request.query_params.get('limit', default_limit)), 1000)
    except (TypeError, ValueError):
        page, limit = 1, default_limit
    total = len(rows)
    start = (page - 1) * limit
    end = start + limit
    return rows[start:end], page, limit, total


class ReportBase(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    columns = []
    title = 'Report'
    base_filename = 'report'

    def build_rows(self, request):
        raise NotImplementedError

    def get(self, request):
        rows = self.build_rows(request)
        # Export?
        exp = maybe_export(request, self.columns, rows, self.base_filename, self.title)
        if exp is not None:
            return exp
        # JSON paginated
        page_rows, page, limit, total = _paginate(rows, request)
        return paginated(page_rows, page, limit, total)


# ───────── 1. Sales ─────────────────────────────────────────────────────────

class SalesReport(ReportBase):
    title = 'Sales Report'
    base_filename = 'sales_report'
    columns = [
        {'key': 'date',           'label': 'Date'},
        {'key': 'order_number',   'label': 'Order #'},
        {'key': 'product',        'label': 'Product'},
        {'key': 'barcode',        'label': 'Barcode'},
        {'key': 'qty',            'label': 'Qty'},
        {'key': 'unit_price',     'label': 'Unit Price'},
        {'key': 'line_total',     'label': 'Line Total'},
        {'key': 'payment_method', 'label': 'Payment'},
        {'key': 'customer',       'label': 'Customer'},
        {'key': 'phone',          'label': 'Phone'},
        {'key': 'address',        'label': 'Address'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = OrderItem.objects.filter(
            order__status='delivered',
            order__created_at__date__gte=from_d,
            order__created_at__date__lte=to_d,
        ).select_related('order', 'order__customer', 'product')
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(order__store_id=store_id)
        return [{
            'date': it.order.created_at.date(),
            'order_number': it.order.order_number,
            'product': it.product_name_en or it.product_name_ar,
            'barcode': it.product_barcode,
            'qty': float(it.quantity or 0),
            'unit_price': float(it.unit_price or 0),
            'line_total': float(it.line_total or 0),
            'payment_method': it.order.payment_method,
            'customer': it.order.customer.full_name,
            'phone': it.order.customer.phone,
            'address': it.order.delivery_address,
        } for it in qs]


# ───────── 2. Payments ──────────────────────────────────────────────────────

class PaymentsReport(ReportBase):
    title = 'Payments Report'
    base_filename = 'payments_report'
    columns = [
        {'key': 'date',           'label': 'Date'},
        {'key': 'order_number',   'label': 'Order #'},
        {'key': 'amount',         'label': 'Amount'},
        {'key': 'payment_method', 'label': 'Payment Method'},
        {'key': 'driver',         'label': 'Driver'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = Order.objects.filter(
            status='delivered',
            delivered_at__date__gte=from_d,
            delivered_at__date__lte=to_d,
        ).select_related('driver')
        qs = scope_to_user(qs, request.user, branch_field='branch_id')
        return [{
            'date': o.delivered_at.date() if o.delivered_at else o.created_at.date(),
            'order_number': o.order_number,
            'amount': float(o.amount_collected or o.total_amount or 0),
            'payment_method': o.payment_method,
            'driver': o.driver.full_name if o.driver else '',
        } for o in qs]


# ───────── 3. Out of stock ──────────────────────────────────────────────────

class OutOfStockReport(ReportBase):
    title = 'Out of Stock'
    base_filename = 'out_of_stock'
    columns = [
        {'key': 'product',         'label': 'Product'},
        {'key': 'barcode',         'label': 'Barcode'},
        {'key': 'category',        'label': 'Category'},
        {'key': 'waitlist_count',  'label': 'Waitlist'},
    ]

    def build_rows(self, request):
        qs = Product.objects.filter(quantity_in_stock__lte=0).prefetch_related('categories', 'waitlist')
        qs = scope_to_user(qs, request.user)
        rows = []
        for p in qs:
            categories = ', '.join(c.name_en for c in p.categories.all()[:3])
            rows.append({
                'product': p.name_en or p.name_ar,
                'barcode': p.barcode or '',
                'category': categories,
                'waitlist_count': p.waitlist.filter(notified_at__isnull=True).count(),
            })
        return rows


# ───────── 4. Cancelled orders ──────────────────────────────────────────────

class CancelledOrdersReport(ReportBase):
    title = 'Cancelled Orders'
    base_filename = 'cancelled_orders'
    columns = [
        {'key': 'date',         'label': 'Date'},
        {'key': 'order_number', 'label': 'Order #'},
        {'key': 'amount',       'label': 'Amount'},
        {'key': 'reason',       'label': 'Reason'},
        {'key': 'cancelled_by', 'label': 'Cancelled By'},
        {'key': 'driver',       'label': 'Driver'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = Order.objects.filter(
            status='cancelled',
            cancelled_at__date__gte=from_d,
            cancelled_at__date__lte=to_d,
        ).select_related('cancelled_by', 'driver')
        qs = scope_to_user(qs, request.user, branch_field='branch_id')
        return [{
            'date': o.cancelled_at.date() if o.cancelled_at else o.created_at.date(),
            'order_number': o.order_number,
            'amount': float(o.total_amount or 0),
            'reason': o.cancellation_reason or '',
            'cancelled_by': o.cancelled_by.full_name if o.cancelled_by else '',
            'driver': o.driver.full_name if o.driver else '',
        } for o in qs]


# ───────── 5. Preparation time ──────────────────────────────────────────────

class PreparationTimeReport(ReportBase):
    title = 'Preparation Time'
    base_filename = 'preparation_time'
    columns = [
        {'key': 'date',          'label': 'Date'},
        {'key': 'order_number',  'label': 'Order #'},
        {'key': 'accepted_at',   'label': 'Accepted'},
        {'key': 'prepared_at',   'label': 'Prepared'},
        {'key': 'duration_mins', 'label': 'Duration (min)'},
        {'key': 'preparer',      'label': 'Preparer'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = Order.objects.filter(
            accepted_at__isnull=False,
            out_for_delivery_at__isnull=False,
            created_at__date__gte=from_d,
            created_at__date__lte=to_d,
        ).select_related('preparer')
        qs = scope_to_user(qs, request.user, branch_field='branch_id')
        rows = []
        for o in qs:
            mins = (o.out_for_delivery_at - o.accepted_at).total_seconds() / 60.0
            rows.append({
                'date': o.created_at.date(),
                'order_number': o.order_number,
                'accepted_at': o.accepted_at.isoformat(),
                'prepared_at': o.out_for_delivery_at.isoformat(),
                'duration_mins': round(mins, 1),
                'preparer': o.preparer.full_name if o.preparer else '',
            })
        return rows


# ───────── 6. Top products ──────────────────────────────────────────────────

class TopProductsReport(ReportBase):
    title = 'Top Products'
    base_filename = 'top_products'
    columns = [
        {'key': 'product',  'label': 'Product'},
        {'key': 'barcode',  'label': 'Barcode'},
        {'key': 'category', 'label': 'Category'},
        {'key': 'qty_sold', 'label': 'Qty Sold'},
        {'key': 'revenue',  'label': 'Revenue'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = OrderItem.objects.filter(
            order__status='delivered',
            order__created_at__date__gte=from_d,
            order__created_at__date__lte=to_d,
        )
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(order__store_id=store_id)
        revenue_expr = ExpressionWrapper(F('unit_price') * F('quantity'), output_field=DecimalField())
        agg = (qs.values('product__id', 'product__name_en', 'product__name_ar', 'product__barcode')
                  .annotate(qty_sold=Sum('quantity'), revenue=Sum(revenue_expr))
                  .order_by('-qty_sold'))
        # Pull primary category for each product
        from apps.products.models import Product
        prod_cats = {}
        prod_ids = [r['product__id'] for r in agg if r['product__id']]
        for p in Product.objects.filter(id__in=prod_ids).prefetch_related('categories'):
            cats = list(p.categories.values_list('name_en', flat=True))
            prod_cats[p.id] = ', '.join(cats[:2])
        return [{
            'product': r['product__name_en'] or r['product__name_ar'],
            'barcode': r['product__barcode'] or '',
            'category': prod_cats.get(r['product__id'], ''),
            'qty_sold': float(r['qty_sold'] or 0),
            'revenue': float(r['revenue'] or 0),
        } for r in agg]


# ───────── 7. Driver performance ────────────────────────────────────────────

class DriverPerformanceReport(ReportBase):
    title = 'Driver Performance'
    base_filename = 'driver_performance'
    columns = [
        {'key': 'driver',              'label': 'Driver'},
        {'key': 'orders_completed',   'label': 'Orders'},
        {'key': 'avg_delivery_mins',  'label': 'Avg Delivery (min)'},
        {'key': 'avg_rating',         'label': 'Avg Rating'},
        {'key': 'cash_collected',     'label': 'Cash Collected'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        from django.contrib.auth import get_user_model
        User = get_user_model()
        drivers = User.objects.filter(role='driver', is_active=True)
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            drivers = drivers.filter(store_id=store_id)
        rows = []
        for d in drivers:
            orders = Order.objects.filter(driver=d, status='delivered',
                                          delivered_at__date__gte=from_d,
                                          delivered_at__date__lte=to_d)
            completed = orders.filter(out_for_delivery_at__isnull=False, delivered_at__isnull=False)
            mins = []
            for o in completed:
                if o.out_for_delivery_at and o.delivered_at:
                    mins.append((o.delivered_at - o.out_for_delivery_at).total_seconds() / 60)
            cash = orders.filter(payment_method='cash').aggregate(s=Sum('amount_collected'))['s'] or 0
            rows.append({
                'driver': d.full_name,
                'orders_completed': orders.count(),
                'avg_delivery_mins': round(sum(mins) / len(mins), 1) if mins else 0,
                'avg_rating': str(d.rating),
                'cash_collected': float(cash),
            })
        rows.sort(key=lambda x: x['orders_completed'], reverse=True)
        return rows


# ───────── 8. Inventory ─────────────────────────────────────────────────────

class InventoryReport(ReportBase):
    title = 'Inventory'
    base_filename = 'inventory'
    columns = [
        {'key': 'product',         'label': 'Product'},
        {'key': 'barcode',         'label': 'Barcode'},
        {'key': 'opening_stock',   'label': 'Opening'},
        {'key': 'received',        'label': 'Received'},
        {'key': 'sold',            'label': 'Sold'},
        {'key': 'adjustments',     'label': 'Adjustments'},
        {'key': 'closing_stock',   'label': 'Closing'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = Product.objects.all()
        qs = scope_to_user(qs, request.user)
        sold_map = dict(
            OrderItem.objects.filter(
                order__status='delivered',
                order__created_at__date__gte=from_d,
                order__created_at__date__lte=to_d,
            ).values('product_id').annotate(s=Sum('quantity')).values_list('product_id', 's')
        )
        rows = []
        for p in qs:
            sold = float(sold_map.get(p.id, 0) or 0)
            closing = p.quantity_in_stock
            # Opening ≈ closing + sold − received − adjustments. We do not yet
            # track received/adjustments as separate ledgers — leave 0 for now.
            opening = closing + int(sold)
            rows.append({
                'product': p.name_en or p.name_ar,
                'barcode': p.barcode or '',
                'opening_stock': opening,
                'received': 0,
                'sold': sold,
                'adjustments': 0,
                'closing_stock': closing,
            })
        return rows


# ───────── 9. Top customers ─────────────────────────────────────────────────

class TopCustomersReport(ReportBase):
    title = 'Top Customers'
    base_filename = 'top_customers'
    columns = [
        {'key': 'customer',        'label': 'Customer'},
        {'key': 'phone',           'label': 'Phone'},
        {'key': 'order_count',     'label': 'Orders'},
        {'key': 'total_spent',     'label': 'Total Spent'},
        {'key': 'avg_order_value', 'label': 'AOV'},
        {'key': 'points',          'label': 'Points'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = Order.objects.filter(
            status='delivered',
            delivered_at__date__gte=from_d,
            delivered_at__date__lte=to_d,
        )
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(store_id=store_id)
        agg = (qs.values('customer__id', 'customer__full_name',
                          'customer__phone', 'customer__loyalty_points')
                  .annotate(order_count=Count('id'),
                            total_spent=Sum('total_amount'),
                            avg=Avg('total_amount'))
                  .order_by('-total_spent'))
        return [{
            'customer': r['customer__full_name'],
            'phone': r['customer__phone'],
            'order_count': r['order_count'],
            'total_spent': float(r['total_spent'] or 0),
            'avg_order_value': float(r['avg'] or 0),
            'points': r['customer__loyalty_points'] or 0,
        } for r in agg]


# ───────── 10. Adjustments ──────────────────────────────────────────────────

class AdjustmentsReport(ReportBase):
    title = 'Adjustments'
    base_filename = 'adjustments'
    columns = [
        {'key': 'order_number',    'label': 'Order #'},
        {'key': 'original',        'label': 'Original'},
        {'key': 'alternative',     'label': 'Alternative / New'},
        {'key': 'preparer',        'label': 'Preparer'},
        {'key': 'approval_status', 'label': 'Approval'},
        {'key': 'price_diff',      'label': 'Price Diff'},
        {'key': 'action_type',     'label': 'Type'},
        {'key': 'date',            'label': 'Date'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = OrderAdjustment.objects.filter(
            created_at__date__gte=from_d,
            created_at__date__lte=to_d,
        ).select_related('order', 'order_item', 'preparer', 'driver')
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(order__store_id=store_id)
        rows = []
        for a in qs:
            agent = a.preparer.full_name if a.preparer else (a.driver.full_name if a.driver else '')
            rows.append({
                'order_number': a.order.order_number if a.order else '',
                'original': a.old_value,
                'alternative': a.new_value,
                'preparer': agent,
                'approval_status': a.customer_approval_status or '',
                'price_diff': '',
                'action_type': a.action_type,
                'date': a.created_at.isoformat(),
            })
        return rows


# ───────── 11. Promotions ───────────────────────────────────────────────────

class PromotionsReport(ReportBase):
    title = 'Promotions'
    base_filename = 'promotions'
    columns = [
        {'key': 'code',             'label': 'Code'},
        {'key': 'name',             'label': 'Name'},
        {'key': 'discount',         'label': 'Discount %/EGP'},
        {'key': 'usage_count',      'label': 'Usage'},
        {'key': 'total_discount',   'label': 'Total Discount'},
        {'key': 'is_active',        'label': 'Active'},
    ]

    def build_rows(self, request):
        from apps.promotions.models import Promotion, PromotionUsage
        qs = Promotion.objects.all()
        qs = scope_to_user(qs, request.user)
        rows = []
        for p in qs:
            total_d = PromotionUsage.objects.filter(promotion=p).aggregate(
                t=Sum('discount_applied'))['t'] or 0
            disc_str = f"{p.discount_value}{'%' if p.discount_type == 'percentage' else ' EGP'}"
            rows.append({
                'code': p.code or '',
                'name': p.name_en or p.name_ar,
                'discount': disc_str,
                'usage_count': p.used_count,
                'total_discount': float(total_d),
                'is_active': p.is_active,
            })
        return rows


# ───────── 12. Daily revenue ────────────────────────────────────────────────

class DailyRevenueReport(ReportBase):
    title = 'Daily Revenue'
    base_filename = 'daily_revenue'
    columns = [
        {'key': 'date',           'label': 'Date'},
        {'key': 'total_sales',    'label': 'Total Sales'},
        {'key': 'cash',           'label': 'Cash'},
        {'key': 'online',         'label': 'Online'},
        {'key': 'pos',            'label': 'POS'},
        {'key': 'wallet',         'label': 'Wallet'},
        {'key': 'points_value',   'label': 'Points'},
        {'key': 'delivery_fees',  'label': 'Delivery Fees'},
        {'key': 'orders',         'label': 'Orders'},
    ]

    def build_rows(self, request):
        from_d, to_d = _date_range(request)
        qs = Order.objects.filter(
            status='delivered',
            delivered_at__date__gte=from_d,
            delivered_at__date__lte=to_d,
        )
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(store_id=store_id)
        # Group by date
        agg = {}
        for o in qs:
            day = o.delivered_at.date() if o.delivered_at else o.created_at.date()
            row = agg.setdefault(day, {
                'date': day, 'total_sales': 0, 'cash': 0, 'online': 0, 'pos': 0,
                'wallet': 0, 'points_value': 0, 'delivery_fees': 0, 'orders': 0,
            })
            row['total_sales'] += float(o.total_amount or 0)
            row['delivery_fees'] += float(o.delivery_fee or 0)
            row['points_value'] += float(o.points_value or 0)
            row['orders'] += 1
            pm = o.payment_method
            if pm in row:
                row[pm] += float(o.amount_collected or o.total_amount or 0)
        return sorted(agg.values(), key=lambda r: r['date'])
