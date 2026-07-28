from rest_framework import generics, permissions, serializers
from rest_framework.views import APIView

from .coverage import OUT_OF_ZONE_AR, OUT_OF_ZONE_EN, covering_branch
from .geo import circle_to_polygon, validate_geometry
from .models import Branch, DeliveryZone
from apps.users.permissions import IsAdminUser
from apps.core.permissions import IsAdminWriteOrSupportRead
from apps.core.scoping import scope_to_user, enforce_store_id_on_create
from apps.core.responses import ok, fail


class BranchSerializer(serializers.ModelSerializer):
    class Meta:
        model = Branch
        fields = '__all__'


class BranchListView(generics.ListAPIView):
    """Customer-facing: only show active branches. Filter by ?store_id="""
    serializer_class = BranchSerializer
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        qs = Branch.objects.filter(is_active=True)
        store_id = self.request.query_params.get('store_id')
        if store_id:
            qs = qs.filter(store_id=store_id)
        return qs


class AdminBranchView(generics.ListCreateAPIView):
    serializer_class = BranchSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        return scope_to_user(Branch.objects.all(), self.request.user)

    def perform_create(self, serializer):
        enforce_store_id_on_create(serializer, self.request.user)


class AdminBranchDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = BranchSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        return scope_to_user(Branch.objects.all(), self.request.user)


class AdminBranchStatusToggleView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def patch(self, request, pk):
        qs = scope_to_user(Branch.objects.all(), request.user)
        try:
            branch = qs.get(pk=pk)
        except Branch.DoesNotExist:
            return fail('Branch not found', status_code=404)
        branch.is_active = not branch.is_active
        branch.save(update_fields=['is_active'])
        return ok({'id': branch.id, 'is_active': branch.is_active})


# ── Delivery zones ───────────────────────────────────────────────────────────

class DeliveryZoneSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryZone
        fields = [
            'id', 'branch', 'name_ar', 'name_en', 'geometry',
            'bbox', 'source', 'is_active', 'created_at', 'updated_at',
        ]
        read_only_fields = ['bbox', 'created_at', 'updated_at']

    def validate_geometry(self, value):
        try:
            return validate_geometry(value)
        except ValueError as e:
            raise serializers.ValidationError(str(e))


class AdminDeliveryZoneView(generics.ListCreateAPIView):
    """?branch_id= filters to one branch."""
    serializer_class = DeliveryZoneSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        branches = scope_to_user(Branch.objects.all(), self.request.user)
        qs = DeliveryZone.objects.filter(branch__in=branches)
        branch_id = self.request.query_params.get('branch_id')
        if branch_id:
            qs = qs.filter(branch_id=branch_id)
        return qs

    def perform_create(self, serializer):
        branch = serializer.validated_data['branch']
        allowed = scope_to_user(Branch.objects.all(), self.request.user)
        if not allowed.filter(pk=branch.pk).exists():
            raise serializers.ValidationError({'branch': 'Not permitted for this branch'})
        serializer.save()


class AdminDeliveryZoneDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = DeliveryZoneSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        branches = scope_to_user(Branch.objects.all(), self.request.user)
        return DeliveryZone.objects.filter(branch__in=branches)


class AdminZoneFromRadiusView(APIView):
    """Turn a branch's delivery_radius_km into an editable polygon.

    The one-click migration path off circles: the admin gets the exact area the
    branch already serves, then reshapes it instead of starting from nothing.
    """
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def post(self, request, pk):
        qs = scope_to_user(Branch.objects.all(), request.user)
        try:
            branch = qs.get(pk=pk)
        except Branch.DoesNotExist:
            return fail('Branch not found', status_code=404)
        if branch.latitude is None or branch.longitude is None:
            return fail('Branch has no coordinates', status_code=400)

        radius = request.data.get('radius_km') or branch.delivery_radius_km
        zone = DeliveryZone.objects.create(
            branch=branch,
            name_ar=request.data.get('name_ar') or f'نطاق {branch.name_ar}',
            name_en=request.data.get('name_en') or f'{branch.name_en or branch.name} area',
            geometry=circle_to_polygon(branch.latitude, branch.longitude, radius),
            source=DeliveryZone.Source.CIRCLE,
        )
        return ok(DeliveryZoneSerializer(zone).data)


class DeliveryCoverageCheckView(APIView):
    """Customer-facing: can we deliver to ?lat=&lng= (&store_id=)?

    Exists so the app can tell someone while they are picking an address rather
    than after they have filled a basket.
    """
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        try:
            lat = float(request.query_params['lat'])
            lng = float(request.query_params['lng'])
        except (KeyError, TypeError, ValueError):
            return fail('lat and lng are required', status_code=400)

        store_id = request.query_params.get('store_id') or None
        branch = covering_branch(lat, lng, store_id=store_id)
        if branch is None:
            return ok({
                'covered': False,
                'branch': None,
                'message_ar': OUT_OF_ZONE_AR,
                'message_en': OUT_OF_ZONE_EN,
            })
        return ok({
            'covered': True,
            'branch': {
                'id': branch.id,
                'name_ar': branch.name_ar,
                'name_en': branch.name_en or branch.name,
                'delivery_fee': str(branch.delivery_fee),
            },
            'message_ar': '',
            'message_en': '',
        })
