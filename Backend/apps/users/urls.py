from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import views
from . import admin_views
from . import otp_views

urlpatterns = [
    # OTP customer auth (spec)
    path('send-otp/', otp_views.SendOTPView.as_view(), name='send-otp'),
    path('verify-otp/', otp_views.VerifyOTPView.as_view(), name='verify-otp'),
    # Firebase Phone Auth token exchange (replaces SMS OTP on client side)
    path('firebase-token/', otp_views.FirebaseTokenLoginView.as_view(), name='firebase-token-login'),

    # Staff + general auth
    path('register/', views.RegisterView.as_view(), name='register'),
    path('login/', views.StaffLoginView.as_view(), name='login'),
    path('social/', views.SocialLoginView.as_view(), name='social-login'),
    path('social-login/', views.SocialLoginView.as_view()),  # back-compat
    path('biometric/register/', views.BiometricRegisterView.as_view(), name='biometric-register'),
    path('biometric/login/', views.BiometricLoginView.as_view(), name='biometric-login'),
    path('logout/', views.LogoutView.as_view(), name='logout'),
    path('refresh/', TokenRefreshView.as_view(), name='token-refresh'),
    path('token/refresh/', TokenRefreshView.as_view()),  # back-compat

    # Profile
    path('me/', views.MeView.as_view(), name='me'),
    path('profile/', views.ProfileView.as_view(), name='profile'),  # back-compat
    path('fcm-token/', views.UpdateFCMTokenView.as_view(), name='fcm-token'),

    # Location (agent)
    path('location/', views.UpdateLocationView.as_view(), name='location'),
    path('online-toggle/', views.DriverOnlineToggleView.as_view(), name='online-toggle'),

    # Addresses
    path('addresses/', views.AddressListCreateView.as_view(), name='addresses'),
    path('addresses/<int:pk>/', views.AddressDetailView.as_view(), name='address-detail'),
    path('addresses/<int:pk>/default/', views.AddressDefaultView.as_view(), name='address-default'),

    # Wallet + points
    path('wallet/balance/', views.WalletBalanceView.as_view(), name='wallet-balance'),
    path('wallet/transactions/', views.WalletTransactionsView.as_view(), name='wallet-transactions'),
    path('points/', views.PointsHistoryView.as_view(), name='points-history'),

    # Privacy/audit
    path('data-share-log/', views.DataShareLogView.as_view(), name='data-share-log'),

    # Admin user management
    path('admin/users/', views.AdminUserListView.as_view(), name='admin-users'),
    path('admin/users/<uuid:id>/', views.AdminUserDetailView.as_view(), name='admin-user-detail'),
    path('admin/staff/create/', views.AdminStaffCreateView.as_view(), name='admin-staff-create'),
    path('admin/drivers/create/', views.AdminStaffCreateView.as_view()),  # alias
    path('admin/users/<uuid:pk>/block/', views.AdminBlockUserView.as_view(), name='admin-user-block'),
    path('admin/drivers/live/', views.AdminDriversLiveView.as_view(), name='admin-drivers-live'),
    path('admin/drivers/<uuid:pk>/settle/', views.AdminSettleCashView.as_view(), name='admin-settle'),

    # Customers
    path('admin/customers/', views.AdminCustomerListView.as_view(), name='admin-customers'),
    path('admin/customers/<uuid:pk>/wallet/', views.AdminCustomerWalletAdjustView.as_view(),
         name='admin-customer-wallet'),

    # Super-Admin RBAC suite (preserved)
    path('superadmin/my-permissions/', admin_views.MyPermissionsView.as_view()),
    path('superadmin/admins/', admin_views.AdminListView.as_view()),
    path('superadmin/admins/create/', admin_views.CreateAdminView.as_view()),
    path('superadmin/admins/<int:pk>/', admin_views.AdminDetailView.as_view()),
    path('superadmin/admins/<int:pk>/permissions/', admin_views.UpdateAdminPermissionsView.as_view()),
    path('superadmin/admins/<int:pk>/toggle/', admin_views.ToggleAdminAccountView.as_view()),
    path('superadmin/admins/<int:pk>/delete/', admin_views.DeleteAdminView.as_view()),
    path('superadmin/admins/<int:pk>/reset-password/', admin_views.ResetAdminPasswordView.as_view()),
    path('superadmin/audit-log/', admin_views.AuditLogListView.as_view()),
]
