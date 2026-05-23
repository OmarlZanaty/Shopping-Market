from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.db import transaction
from .admin_roles import (
    AdminProfile, AdminAuditLog, AdminPermission,
    PRESET_ROLES, PERMISSION_GROUPS, log_admin_action
)
from .models import User

User = get_user_model()


# ─── Permissions ──────────────────────────────────────────────────────────────

class IsSuperAdmin(permissions.BasePermission):
    def has_permission(self, request, view):
        if not request.user.is_authenticated or request.user.role != 'admin':
            return False
        try:
            return request.user.admin_profile.is_super_admin
        except AdminProfile.DoesNotExist:
            return False


class HasAdminPermission(permissions.BasePermission):
    """Dynamic permission check - pass required_perm in view"""
    def has_permission(self, request, view):
        if not request.user.is_authenticated or request.user.role != 'admin':
            return False
        required = getattr(view, 'required_perm', None)
        if not required:
            return True
        try:
            return request.user.admin_profile.has_permission(required)
        except AdminProfile.DoesNotExist:
            return False


# ─── Serializers ──────────────────────────────────────────────────────────────

class AdminProfileSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source='user.full_name', read_only=True)
    user_phone = serializers.CharField(source='user.phone', read_only=True)
    user_email = serializers.CharField(source='user.email', read_only=True)
    user_avatar = serializers.SerializerMethodField()
    user_is_active = serializers.BooleanField(source='user.is_active', read_only=True)
    preset_role_label = serializers.SerializerMethodField()
    created_by_name = serializers.CharField(source='created_by.full_name', read_only=True)
    allowed_branch_ids = serializers.SerializerMethodField()

    class Meta:
        model = AdminProfile
        fields = [
            'id', 'user', 'user_name', 'user_phone', 'user_email',
            'user_avatar', 'user_is_active', 'is_super_admin',
            'preset_role', 'preset_role_label', 'permissions',
            'allowed_branch_ids', 'all_branches_access',
            'notes', 'created_by_name', 'last_login_ip',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['user', 'created_by', 'last_login_ip', 'created_at', 'updated_at']

    def get_user_avatar(self, obj):
        req = self.context.get('request')
        if obj.user.avatar and req:
            return req.build_absolute_uri(obj.user.avatar.url)
        return None

    def get_preset_role_label(self, obj):
        if obj.preset_role and obj.preset_role in PRESET_ROLES:
            return {
                'ar': PRESET_ROLES[obj.preset_role]['label_ar'],
                'en': PRESET_ROLES[obj.preset_role]['label_en'],
            }
        return None

    def get_allowed_branch_ids(self, obj):
        return list(obj.allowed_branches.values_list('id', flat=True))


class CreateAdminSerializer(serializers.Serializer):
    # Account info
    phone = serializers.CharField()
    full_name = serializers.CharField()
    email = serializers.EmailField(required=False, allow_blank=True)
    password = serializers.CharField(min_length=6)

    # Role & permissions
    is_super_admin = serializers.BooleanField(default=False)
    preset_role = serializers.ChoiceField(
        choices=list(PRESET_ROLES.keys()) + ['custom'],
        default='manager'
    )
    custom_permissions = serializers.ListField(
        child=serializers.CharField(), required=False, default=list
    )
    allowed_branch_ids = serializers.ListField(
        child=serializers.IntegerField(), required=False, default=list
    )
    notes = serializers.CharField(required=False, allow_blank=True)

    def validate_phone(self, value):
        if User.objects.filter(phone=value).exists():
            raise serializers.ValidationError('Phone number already registered')
        return value

    def validate(self, data):
        if data.get('is_super_admin') and not self.context['request'].user.admin_profile.is_super_admin:
            raise serializers.ValidationError(
                {'is_super_admin': 'Only super admins can create other super admins'}
            )
        return data


class UpdateAdminPermissionsSerializer(serializers.Serializer):
    preset_role = serializers.ChoiceField(
        choices=list(PRESET_ROLES.keys()) + ['custom'],
        required=False
    )
    custom_permissions = serializers.ListField(
        child=serializers.CharField(), required=False
    )
    is_super_admin = serializers.BooleanField(required=False)
    allowed_branch_ids = serializers.ListField(
        child=serializers.IntegerField(), required=False
    )
    notes = serializers.CharField(required=False, allow_blank=True)


class AuditLogSerializer(serializers.ModelSerializer):
    admin_name = serializers.CharField(source='admin.full_name', read_only=True)
    admin_phone = serializers.CharField(source='admin.phone', read_only=True)

    class Meta:
        model = AdminAuditLog
        fields = '__all__'


# ─── Views ────────────────────────────────────────────────────────────────────

class MyPermissionsView(APIView):
    """Any admin can see their own permissions"""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if request.user.role != 'admin':
            return Response({'error': 'Not an admin'}, status=403)
        try:
            profile = request.user.admin_profile
            all_perms = list(AdminPermission)
            return Response({
                'is_super_admin': profile.is_super_admin,
                'preset_role': profile.preset_role,
                'permissions': profile.permissions,
                'all_branches_access': profile.all_branches_access,
                'allowed_branch_ids': list(profile.allowed_branches.values_list('id', flat=True)),
                'all_available_permissions': [
                    {'value': p.value, 'label': p.label, 'group': self._get_group(p.value)}
                    for p in all_perms
                ],
                'permission_groups': {
                    group: [p.value for p in perms]
                    for group, perms in PERMISSION_GROUPS.items()
                },
                'preset_roles': {
                    key: {
                        'label_ar': val['label_ar'],
                        'label_en': val['label_en'],
                        'permissions': [p.value for p in val['permissions']],
                    }
                    for key, val in PRESET_ROLES.items()
                },
            })
        except AdminProfile.DoesNotExist:
            return Response({'is_super_admin': False, 'permissions': []})

    def _get_group(self, perm_value):
        for group, perms in PERMISSION_GROUPS.items():
            if perm_value in [p.value for p in perms]:
                return group
        return 'other'


class AdminListView(generics.ListAPIView):
    """Super admin sees all admin accounts"""
    serializer_class = AdminProfileSerializer
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]
    search_fields = ['user__full_name', 'user__phone']
    filterset_fields = ['is_super_admin', 'preset_role']

    def get_queryset(self):
        return AdminProfile.objects.select_related('user', 'created_by').all()


class CreateAdminView(APIView):
    """Super admin creates a new admin with specific permissions"""
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]

    @transaction.atomic
    def post(self, request):
        serializer = CreateAdminSerializer(data=request.data, context={'request': request})
        if not serializer.is_valid():
            return Response(serializer.errors, status=400)

        data = serializer.validated_data

        # Create user account
        user = User.objects.create_user(
            phone=data['phone'],
            full_name=data['full_name'],
            email=data.get('email', ''),
            password=data['password'],
            role='admin',
        )

        # Determine permissions
        if data['preset_role'] != 'custom':
            role_data = PRESET_ROLES[data['preset_role']]
            permissions_list = [p.value for p in role_data['permissions']]
            is_super = data.get('is_super_admin', False)
        else:
            permissions_list = data.get('custom_permissions', [])
            is_super = data.get('is_super_admin', False)

        # Create admin profile
        profile = AdminProfile.objects.create(
            user=user,
            is_super_admin=is_super,
            preset_role=data['preset_role'] if data['preset_role'] != 'custom' else None,
            permissions=permissions_list,
            created_by=request.user,
            notes=data.get('notes', ''),
        )

        # Assign branches
        branch_ids = data.get('allowed_branch_ids', [])
        if branch_ids:
            from apps.branches.models import Branch
            profile.allowed_branches.set(Branch.objects.filter(id__in=branch_ids))

        # Audit log
        log_admin_action(
            admin_user=request.user,
            action='create',
            resource_type='admin',
            resource_id=str(user.id),
            description=f'Created admin account for {user.full_name} ({user.phone}) with role {data["preset_role"]}',
            new_data={'phone': user.phone, 'role': data['preset_role'],
                      'permissions': permissions_list},
            request=request,
        )

        return Response(AdminProfileSerializer(profile, context={'request': request}).data,
                        status=201)


class AdminDetailView(generics.RetrieveAPIView):
    serializer_class = AdminProfileSerializer
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]
    queryset = AdminProfile.objects.select_related('user', 'created_by').all()


class UpdateAdminPermissionsView(APIView):
    """Super admin updates another admin's permissions"""
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]

    def patch(self, request, pk):
        try:
            profile = AdminProfile.objects.get(pk=pk)
        except AdminProfile.DoesNotExist:
            return Response({'error': 'Admin not found'}, status=404)

        # Prevent modifying another super admin unless you created them
        if profile.is_super_admin and profile.created_by != request.user:
            return Response({'error': 'Cannot modify this super admin'}, status=403)

        serializer = UpdateAdminPermissionsSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=400)

        old_data = {
            'permissions': profile.permissions,
            'is_super_admin': profile.is_super_admin,
            'preset_role': profile.preset_role,
        }
        data = serializer.validated_data

        if 'preset_role' in data and data['preset_role'] != 'custom':
            role_data = PRESET_ROLES[data['preset_role']]
            profile.preset_role = data['preset_role']
            profile.permissions = [p.value for p in role_data['permissions']]
            if data['preset_role'] == 'super_admin':
                profile.is_super_admin = True

        elif 'custom_permissions' in data:
            profile.preset_role = None
            profile.permissions = data['custom_permissions']

        if 'is_super_admin' in data:
            profile.is_super_admin = data['is_super_admin']

        if 'notes' in data:
            profile.notes = data['notes']

        profile.save()

        # Update branch access
        if 'allowed_branch_ids' in data:
            if data['allowed_branch_ids']:
                from apps.branches.models import Branch
                profile.allowed_branches.set(Branch.objects.filter(id__in=data['allowed_branch_ids']))
            else:
                profile.allowed_branches.clear()

        log_admin_action(
            admin_user=request.user,
            action='update',
            resource_type='admin',
            resource_id=str(profile.user.id),
            description=f'Updated permissions for {profile.user.full_name}',
            old_data=old_data,
            new_data={'permissions': profile.permissions, 'is_super_admin': profile.is_super_admin},
            request=request,
        )

        return Response(AdminProfileSerializer(profile, context={'request': request}).data)


class ToggleAdminAccountView(APIView):
    """Super admin activates/deactivates an admin account"""
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]

    def post(self, request, pk):
        try:
            profile = AdminProfile.objects.get(pk=pk)
        except AdminProfile.DoesNotExist:
            return Response({'error': 'Admin not found'}, status=404)

        if profile.user == request.user:
            return Response({'error': 'Cannot deactivate yourself'}, status=400)

        profile.user.is_active = not profile.user.is_active
        profile.user.save(update_fields=['is_active'])

        action = 'activated' if profile.user.is_active else 'deactivated'
        log_admin_action(
            admin_user=request.user,
            action='block',
            resource_type='admin',
            resource_id=str(profile.user.id),
            description=f'Admin account {action}: {profile.user.full_name}',
            request=request,
        )

        return Response({'is_active': profile.user.is_active, 'message': f'Account {action}'})


class DeleteAdminView(APIView):
    """Super admin permanently deletes an admin account"""
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]

    def delete(self, request, pk):
        try:
            profile = AdminProfile.objects.get(pk=pk)
        except AdminProfile.DoesNotExist:
            return Response({'error': 'Admin not found'}, status=404)

        if profile.user == request.user:
            return Response({'error': 'Cannot delete yourself'}, status=400)

        name = profile.user.full_name
        phone = profile.user.phone
        profile.user.delete()

        log_admin_action(
            admin_user=request.user,
            action='delete',
            resource_type='admin',
            resource_id=pk,
            description=f'Deleted admin account: {name} ({phone})',
            request=request,
        )

        return Response({'message': f'Admin {name} deleted'})


class AuditLogListView(generics.ListAPIView):
    """Super admin views full audit log"""
    serializer_class = AuditLogSerializer
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]
    filterset_fields = ['action', 'resource_type', 'admin']
    search_fields = ['description', 'admin__full_name', 'resource_id']
    ordering = ['-created_at']

    def get_queryset(self):
        return AdminAuditLog.objects.select_related('admin').all()


class ResetAdminPasswordView(APIView):
    """Super admin resets another admin's password"""
    permission_classes = [permissions.IsAuthenticated, IsSuperAdmin]

    def post(self, request, pk):
        try:
            profile = AdminProfile.objects.get(pk=pk)
        except AdminProfile.DoesNotExist:
            return Response({'error': 'Admin not found'}, status=404)

        new_password = request.data.get('new_password', '')
        if len(new_password) < 6:
            return Response({'error': 'Password must be at least 6 characters'}, status=400)

        profile.user.set_password(new_password)
        profile.user.save()

        log_admin_action(
            admin_user=request.user,
            action='update',
            resource_type='admin',
            resource_id=str(profile.user.id),
            description=f'Password reset for {profile.user.full_name}',
            request=request,
        )

        return Response({'message': 'Password reset successfully'})
