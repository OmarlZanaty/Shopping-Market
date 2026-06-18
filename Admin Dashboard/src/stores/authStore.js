/**
 * Auth store — Zustand with localStorage persistence.
 *
 * - login(): POSTs /auth/login/, accepts admin / branch_manager / support roles
 *   per the spec's RBAC rules.
 * - setTokens() lets the axios refresh interceptor update tokens silently.
 * - logout() wipes both Zustand state and localStorage.
 */
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import axios from 'axios';

const BASE_URL = import.meta.env.VITE_API_BASE_URL
  || 'http://34.124.228.3/api/v1';

// Roles allowed to access the admin dashboard.
const ALLOWED_ROLES = ['admin', 'branch_manager', 'support', 'super_admin'];

export const useAuthStore = create(
  persist(
    (set, get) => ({
      user: null,
      token: null,
      refreshToken: null,

      /**
       * Phone + password login. Accepts the spec envelope or a raw response.
       */
      login: async (phone, password) => {
        const res = await axios.post(`${BASE_URL}/auth/login/`,
          { phone, password },
          { headers: { 'Content-Type': 'application/json' } });
        // Unwrap envelope if present
        const payload = res.data?.success !== undefined ? res.data.data : res.data;
        const { user, access, refresh } = payload || {};
        if (!user || !access) throw new Error('استجابة غير صحيحة من الخادم');
        if (!ALLOWED_ROLES.includes(user.role)) {
          throw new Error('غير مصرح لك بالدخول للوحة التحكم');
        }
        localStorage.setItem('access_token', access);
        localStorage.setItem('refresh_token', refresh);
        set({ user, token: access, refreshToken: refresh });
        return payload;
      },

      setTokens: (access, refresh) => {
        localStorage.setItem('access_token', access);
        if (refresh) localStorage.setItem('refresh_token', refresh);
        set({ token: access, ...(refresh ? { refreshToken: refresh } : {}) });
      },

      logout: () => {
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        set({ user: null, token: null, refreshToken: null });
      },

      updateUser: (userData) => set({ user: { ...get().user, ...userData } }),

      hasRole: (...roles) => {
        const role = get().user?.role;
        return role && roles.includes(role);
      },
    }),
    {
      name: 'sm-admin-auth',
      partialize: (state) => ({
        user: state.user,
        token: state.token,
        refreshToken: state.refreshToken,
      }),
    },
  ),
);
