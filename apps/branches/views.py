from rest_framework import generics, permissions, serializers
from rest_framework.views import APIView

from .models import Branch
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
