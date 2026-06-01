from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import permissions
from django.db.models import (
    Sum, Count, Avg, F, Q, DecimalField, IntegerField,
    ExpressionWrapper, FloatField
)
from django.db.models.functions import TruncDate, TruncMonth, TruncWeek
from django.utils import timezone
from datetime import timedelta, date
from apps.users.permissions import IsAdminUser
from apps.orders.models import Order, OrderItem, OrderAdjustment, OrderRating
from apps.products.models import Product, Category
from django.contrib.auth import get_user_model

User = get_user_model()


class DashboardSummaryView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        today = timezone.now().date()
        week_ago = today - timedelta(days=7)
        month_ago = today - timedelta(days=30)

        orders_today = Order.objects.filter(created_at__date=today)
        orders_week = Order.objects.filter(created_at__date__gte=week_ago)
        orders_month = Order.objects.filter(created_at__date__gte=month_ago)

        delivered_today = orders_today.filter(status='delivered')
        delivered_month = orders_month.filter(status='delivered')

        return Response({
            'today': {
                'total_orders': orders_today.count(),
                'delivered': delivered_today.count(),
                'cancelled': orders_today.filter(status='cancelled').count(),
                'revenue': str(delivered_today.aggregate(r=Sum('total_amount'))['r'] or 0),
                'new_customers': User.objects.filter(role='customer', created_at__date=today).count(),
            },
            'week': {
                'total_orders': orders_week.count(),
                'revenue': str(orders_week.filter(status='delivered')
                               .aggregate(r=Sum('total_amount'))['r'] or 0),
            },
            'month': {
                'total_orders': orders_month.count(),
                'revenue': str(delivered_month.aggregate(r=Sum('total_amount'))['r'] or 0),
                'avg_order_value': str(delivered_month.aggregate(a=Avg('total_amount'))['a'] or 0),
            },
            'active_drivers': User.objects.filter(role='driver', is_online=True, is_active=True).count(),
            'pending_orders': Order.objects.filter(status__in=['new', 'preparing', 'out_for_delivery']).count(),
            'low_stock_products': Product.objects.filter(
                quantity_in_stock__lte=F('low_stock_threshold'), is_available=True).count(),
        })


class SalesByDayView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        data = (Order.objects
                .filter(status='delivered', created_at__gte=cutoff)
                .annotate(day=TruncDate('created_at'))
                .values('day')
                .annotate(revenue=Sum('total_amount'), orders=Count('id'))
                .order_by('day'))
        return Response(list(data))


class SalesByProductView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        data = (OrderItem.objects
                .filter(order__status='delivered', order__created_at__gte=cutoff)
                .values('product__name_en', 'product__name_ar', 'product_id')
                .annotate(
                    total_qty=Sum('quantity'),
                    total_revenue=Sum(F('unit_price') * F('quantity'),
                                      output_field=DecimalField()),
                    order_count=Count('order', distinct=True)
                )
                .order_by('-total_revenue')[:50])
        return Response(list(data))


class SalesByCategoryView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        data = (OrderItem.objects
                .filter(order__status='delivered', order__created_at__gte=cutoff)
                .values('product__categories__name_en', 'product__categories__name_ar')
                .annotate(
                    total_revenue=Sum(F('unit_price') * F('quantity'), output_field=DecimalField()),
                    order_count=Count('order', distinct=True)
                )
                .order_by('-total_revenue'))
        return Response(list(data))


class DriverPerformanceView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        drivers = User.objects.filter(role__in=['driver', 'preparer'], is_active=True)
        result = []
        for driver in drivers:
            orders = Order.objects.filter(
                driver=driver, status='delivered', delivered_at__gte=cutoff)
            ratings = OrderRating.objects.filter(order__driver=driver)
            avg_delivery_minutes = 0
            completed = orders.filter(
                out_for_delivery_at__isnull=False, delivered_at__isnull=False)
            if completed.exists():
                deltas = [
                    (o.delivered_at - o.out_for_delivery_at).total_seconds() / 60
                    for o in completed if o.out_for_delivery_at and o.delivered_at
                ]
                avg_delivery_minutes = round(sum(deltas) / len(deltas), 1) if deltas else 0
            result.append({
                'driver_id': str(driver.id),
                'name': driver.full_name,
                'phone': driver.phone,
                'is_online': driver.is_online,
                'orders_completed': orders.count(),
                'avg_rating': str(driver.rating),
                'avg_delivery_minutes': avg_delivery_minutes,
                'cash_on_hand': str(driver.cash_on_hand),
                'total_revenue_delivered': str(
                    orders.aggregate(r=Sum('total_amount'))['r'] or 0),
                'ratings_count': ratings.count(),
            })
        result.sort(key=lambda x: x['orders_completed'], reverse=True)
        return Response(result)


class OrderCloseMethodReportView(APIView):
    """Orders closed by customer vs driver auto-close"""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        data = (Order.objects
                .filter(status='delivered', delivered_at__gte=cutoff)
                .values('closed_by')
                .annotate(count=Count('id'))
                .order_by('closed_by'))
        return Response(list(data))


class PriceAdjustmentReportView(APIView):
    """Log of all driver price edits"""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        data = (OrderAdjustment.objects
                .filter(adjustment_type='price_change', created_at__gte=cutoff)
                .select_related('driver', 'order', 'order_item__product')
                .values(
                    'driver__full_name', 'driver__phone',
                    'order__order_id', 'order_item__product_name_en',
                    'old_value', 'new_value', 'reason', 'customer_approved', 'created_at'
                )
                .order_by('-created_at'))
        return Response(list(data))


class SubstituteReportView(APIView):
    """Which products get substituted most - signals restocking needs"""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        data = (OrderAdjustment.objects
                .filter(adjustment_type='substitute')
                .values('order_item__product__name_en', 'order_item__product_id')
                .annotate(substitute_count=Count('id'))
                .order_by('-substitute_count')[:30])
        return Response(list(data))


class CustomerRatingReportView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        summary = OrderRating.objects.filter(created_at__gte=cutoff).aggregate(
            avg_product=Avg('product_rating'),
            avg_delivery=Avg('delivery_rating'),
            total=Count('id'),
            one_star=Count('id', filter=Q(delivery_rating=1)),
        )
        by_driver = (OrderRating.objects
                     .filter(created_at__gte=cutoff)
                     .values('order__driver__full_name', 'order__driver__phone')
                     .annotate(
                         avg_rating=Avg('delivery_rating'),
                         count=Count('id'),
                         bad=Count('id', filter=Q(delivery_rating__lte=2))
                     )
                     .order_by('avg_rating'))
        return Response({'summary': summary, 'by_driver': list(by_driver)})


class InventoryReportView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        low_stock = Product.objects.filter(
            quantity_in_stock__lte=F('low_stock_threshold'),
            is_available=True
        ).values('name_en', 'name_ar', 'quantity_in_stock', 'low_stock_threshold', 'barcode')

        out_of_stock = Product.objects.filter(
            quantity_in_stock__lte=0
        ).values('name_en', 'name_ar', 'barcode')

        return Response({
            'low_stock': list(low_stock),
            'out_of_stock': list(out_of_stock),
            'total_products': Product.objects.count(),
            'active_products': Product.objects.filter(is_available=True).count(),
        })


class LoyaltyPointsReportView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        from apps.users.models import PointsTransaction
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        summary = PointsTransaction.objects.filter(created_at__gte=cutoff).aggregate(
            total_earned=Sum('points', filter=Q(transaction_type='earned')),
            total_redeemed=Sum('points', filter=Q(transaction_type='redeemed')),
            total_bonus=Sum('points', filter=Q(transaction_type='bonus')),
        )
        top_earners = (User.objects.filter(role='customer')
                       .order_by('-loyalty_points')[:20]
                       .values('full_name', 'phone', 'loyalty_points'))
        return Response({'summary': summary, 'top_earners': list(top_earners)})


class BannerAnalyticsView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        from apps.products.models import Banner
        banners = Banner.objects.all().values(
            'id', 'title_en', 'position', 'view_count',
            'click_count', 'purchase_count', 'is_active'
        )
        result = []
        for b in banners:
            ctr = round((b['click_count'] / b['view_count']) * 100, 2) if b['view_count'] else 0
            result.append({**b, 'ctr': ctr})
        return Response(result)


class RevenueByBranchView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        data = (Order.objects
                .filter(status='delivered', created_at__gte=cutoff)
                .values('branch__name', 'branch_id')
                .annotate(revenue=Sum('total_amount'), orders=Count('id'))
                .order_by('-revenue'))
        return Response(list(data))


class CustomerChurnView(APIView):
    """Customers who haven't ordered in 14+ days"""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        cutoff = timezone.now() - timedelta(days=14)
        inactive = (User.objects
                    .filter(role='customer', is_active=True)
                    .exclude(customer_orders__created_at__gte=cutoff)
                    .values('id', 'full_name', 'phone', 'last_order_date', 'loyalty_points')
                    .order_by('last_order_date')[:100])
        return Response(list(inactive))


class PeakHoursView(APIView):
    """Order count grouped by hour - shows when customers order most"""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        from django.db.models.functions import ExtractHour
        days = int(request.query_params.get('days', 30))
        cutoff = timezone.now() - timedelta(days=days)
        data = (Order.objects
                .filter(created_at__gte=cutoff)
                .annotate(hour=ExtractHour('created_at'))
                .values('hour')
                .annotate(count=Count('id'))
                .order_by('hour'))
        return Response(list(data))
