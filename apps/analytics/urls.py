from django.urls import path
from . import views

urlpatterns = [
    path('dashboard/', views.DashboardSummaryView.as_view()),
    path('sales/daily/', views.SalesByDayView.as_view()),
    path('sales/products/', views.SalesByProductView.as_view()),
    path('sales/categories/', views.SalesByCategoryView.as_view()),
    path('sales/branches/', views.RevenueByBranchView.as_view()),
    path('drivers/', views.DriverPerformanceView.as_view()),
    path('orders/close-method/', views.OrderCloseMethodReportView.as_view()),
    path('orders/price-adjustments/', views.PriceAdjustmentReportView.as_view()),
    path('orders/substitutes/', views.SubstituteReportView.as_view()),
    path('orders/peak-hours/', views.PeakHoursView.as_view()),
    path('ratings/', views.CustomerRatingReportView.as_view()),
    path('inventory/', views.InventoryReportView.as_view()),
    path('points/', views.LoyaltyPointsReportView.as_view()),
    path('banners/', views.BannerAnalyticsView.as_view()),
    path('customers/churn/', views.CustomerChurnView.as_view()),
]
