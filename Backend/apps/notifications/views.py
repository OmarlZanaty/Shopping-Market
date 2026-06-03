from rest_framework import generics, permissions
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import serializers
from django.utils import timezone
from django.core.cache import cache

from .models import AppSettings, InAppNotification
from apps.users.permissions import IsAdminUser
from apps.core.responses import ok, fail
from apps.core.cache_keys import APP_SETTINGS_CACHE_KEY, APP_SETTINGS_CACHE_TTL


class AppSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = AppSettings
        fields = '__all__'


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = InAppNotification
        fields = '__all__'
        read_only_fields = ['user', 'sent_at', 'read_at', 'created_at']


class AppSettingsPublicView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        cached = cache.get(APP_SETTINGS_CACHE_KEY)
        if cached is not None:
            return Response(cached)
        settings_dict = {s.key: s.value for s in AppSettings.objects.all()}
        cache.set(APP_SETTINGS_CACHE_KEY, settings_dict, APP_SETTINGS_CACHE_TTL)
        return Response(settings_dict)


class AdminAppSettingsView(generics.ListCreateAPIView):
    serializer_class = AppSettingsSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    queryset = AppSettings.objects.all().order_by('key')

    def perform_create(self, serializer):
        serializer.save()
        cache.delete(APP_SETTINGS_CACHE_KEY)


class AdminAppSettingDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = AppSettingsSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    queryset = AppSettings.objects.all()

    def perform_update(self, serializer):
        serializer.save()
        cache.delete(APP_SETTINGS_CACHE_KEY)


class AdminAppSettingsBulkView(APIView):
    """PATCH /admin/settings/bulk — body: [{key, value}, ...]"""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def patch(self, request):
        items = request.data if isinstance(request.data, list) else request.data.get('items', [])
        if not isinstance(items, list):
            return fail('Body must be a list of {key, value}', status_code=400)
        updated = 0
        for it in items:
            key = it.get('key')
            value = it.get('value')
            if not key:
                continue
            AppSettings.objects.update_or_create(
                key=key, defaults={'value': str(value), 'description': it.get('description', '')}
            )
            updated += 1
        cache.delete(APP_SETTINGS_CACHE_KEY)
        return ok({'updated': updated})


class MyNotificationsView(generics.ListAPIView):
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        qs = InAppNotification.objects.filter(user=self.request.user)
        type_filter = self.request.query_params.get('type')
        if type_filter:
            qs = qs.filter(type=type_filter)
        return qs.order_by('is_read', '-created_at')  # unread first


class MarkNotificationReadView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, pk):
        updated = InAppNotification.objects.filter(pk=pk, user=request.user).update(
            is_read=True, read_at=timezone.now()
        )
        if not updated:
            return fail('Notification not found', status_code=404)
        return ok({'id': pk, 'is_read': True})


class MarkAllNotificationsReadView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request):
        count = InAppNotification.objects.filter(user=request.user, is_read=False).update(
            is_read=True, read_at=timezone.now()
        )
        return ok({'updated': count})


class AdminSendNotificationView(APIView):
    """
    Body: { title_ar, title_en, body_ar, body_en, type, target: 'all'|'branch'|'customers'|'drivers',
            branch_id?, store_id?, link? }
    """
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def post(self, request):
        from django.contrib.auth import get_user_model
        from apps.notifications.utils import send_bulk_push
        User = get_user_model()

        target = request.data.get('target', 'all')
        title_ar = request.data.get('title_ar', '')
        title_en = request.data.get('title_en', '')
        body_ar = request.data.get('body_ar', '')
        body_en = request.data.get('body_en', '')
        notif_type = request.data.get('type', 'general')
        branch_id = request.data.get('branch_id')
        store_id = request.data.get('store_id') or getattr(request.user, 'store_id', None)

        qs = User.objects.filter(is_active=True)
        if target == 'drivers':
            qs = qs.filter(role='driver')
            if store_id:
                qs = qs.filter(store_id=store_id)
            if branch_id:
                qs = qs.filter(branch_id=branch_id)
        elif target == 'branch' and branch_id:
            qs = qs.filter(role='customer')  # branch broadcasts go to customers who ordered from that branch
        else:
            qs = qs.filter(role='customer')

        users = list(qs)
        # Persist in-app + send push
        for u in users:
            InAppNotification.objects.create(
                user=u, title_ar=title_ar, title_en=title_en,
                body_ar=body_ar, body_en=body_en, type=notif_type,
                data={'broadcast': True, 'link': request.data.get('link', '')},
            )
        sent = send_bulk_push(qs, title_ar, title_en, body_ar, body_en,
                              data={'type': notif_type, 'broadcast': True})
        return ok({'sent_push': sent, 'persisted_in_app': len(users)})


class TestPushNotificationView(APIView):
    """POST /notifications/test/ — send a test push to the authenticated user's
    own device so they can verify notifications work on THIS device.

    Returns whether a token is registered and whether FCM accepted the send, so
    the app can tell the user exactly what's wrong (no token vs. delivery failure)."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from apps.notifications.utils import send_push_notification
        user = request.user
        has_token = bool(getattr(user, 'fcm_token', None))
        sent = send_push_notification(
            user,
            title_ar='✅ اختبار الإشعارات',
            title_en='Notification test',
            body_ar='الإشعارات تعمل على هذا الجهاز.',
            body_en='Notifications are working on this device.',
            data={'type': 'test'},
        )
        return ok({
            'has_token': has_token,
            'fcm_sent': sent,
            'role': getattr(user, 'role', ''),
        })
