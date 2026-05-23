from django.urls import path
from . import views as r

urlpatterns = [
    path('sales/',              r.SalesReport.as_view(),           name='sales'),
    path('payments/',           r.PaymentsReport.as_view(),        name='payments'),
    path('out-of-stock/',       r.OutOfStockReport.as_view(),      name='out-of-stock'),
    path('cancelled-orders/',   r.CancelledOrdersReport.as_view(), name='cancelled'),
    path('preparation-time/',   r.PreparationTimeReport.as_view(), name='prep-time'),
    path('top-products/',       r.TopProductsReport.as_view(),     name='top-products'),
    path('driver-performance/', r.DriverPerformanceReport.as_view(), name='driver-perf'),
    path('inventory/',          r.InventoryReport.as_view(),       name='inventory'),
    path('top-customers/',      r.TopCustomersReport.as_view(),    name='top-customers'),
    path('adjustments/',        r.AdjustmentsReport.as_view(),     name='adjustments'),
    path('promotions/',         r.PromotionsReport.as_view(),      name='promotions'),
    path('daily-revenue/',      r.DailyRevenueReport.as_view(),    name='daily-revenue'),
]
