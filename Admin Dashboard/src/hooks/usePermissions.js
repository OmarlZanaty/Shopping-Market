import { useQuery } from '@tanstack/react-query';
import { api } from '../services/api';
import { useAuthStore } from '../stores/authStore';

export function usePermissions() {
  const { user } = useAuthStore();
  const { data } = useQuery({
    queryKey: ['my-permissions'],
    queryFn: () => api.get('/auth/superadmin/my-permissions/').then(r => r.data),
    enabled: !!user && user.role === 'admin',
    staleTime: 60000,
  });
  const isSuperAdmin = data?.is_super_admin || false;
  const permissions = data?.permissions || [];
  const can = (perm) => isSuperAdmin || permissions.includes(perm);
  const canAny = (...perms) => isSuperAdmin || perms.some(p => permissions.includes(p));
  return { isSuperAdmin, permissions, can, canAny, permissionData: data };
}

export function PermissionGate({ perm, perms, fallback = null, children }) {
  const { can, canAny } = usePermissions();
  if (perm && !can(perm)) return fallback;
  if (perms && !canAny(...perms)) return fallback;
  return children;
}
