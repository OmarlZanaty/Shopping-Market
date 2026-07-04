/**
 * Centralised axios instance for the admin dashboard.
 *
 * - Reads VITE_API_BASE_URL from env (falls back to the staging Django URL).
 * - Attaches Authorization: Bearer <accessToken> from Zustand auth store.
 * - On 401, attempts /auth/refresh/ once, then retries; on failure clears
 *   the auth store and lets the page redirect itself.
 * - Smart-unwraps the backend's `{success, data, message, errors, pagination}`
 *   envelope on every response: `res.data` becomes the unwrapped payload,
 *   and pagination is attached as `res.pagination` if present.
 */
import axios from 'axios';
import toast from 'react-hot-toast';
import { useAuthStore } from '../stores/authStore';

const BASE_URL = import.meta.env.VITE_API_BASE_URL
  || 'http://63.186.157.245/api/v1';

export const api = axios.create({
  baseURL: BASE_URL,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Accept-Language': 'ar',
  },
});

// Request: attach token from Zustand
api.interceptors.request.use((config) => {
  const token = useAuthStore.getState().token;
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

let isRefreshing = false;
let queued = [];

// Response: unwrap envelope + refresh on 401
api.interceptors.response.use(
  (response) => {
    const body = response.data;
    if (body && typeof body === 'object' && 'success' in body) {
      if (body.success === false) {
        return Promise.reject({
          message: body.message || 'Request failed',
          errors: body.errors || [],
          response,
        });
      }
      // Mutate the response so callers see the unwrapped data,
      // but still expose pagination as response.pagination.
      response.data = body.data ?? body;
      response.pagination = body.pagination;
    }
    return response;
  },
  async (error) => {
    const original = error.config;
    if (!original) return Promise.reject(error);

    if (error.response?.status === 401 && !original._retry) {
      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          queued.push({ resolve, reject, original });
        });
      }
      original._retry = true;
      isRefreshing = true;
      try {
        const auth = useAuthStore.getState();
        const refresh = auth.refreshToken;
        if (!refresh) throw new Error('no refresh token');

        const res = await axios.post(`${BASE_URL}/auth/refresh/`, { refresh });
        const newAccess = res.data?.access ?? res.data?.data?.access;
        const newRefresh = res.data?.refresh ?? res.data?.data?.refresh;
        if (!newAccess) throw new Error('refresh returned no access');
        useAuthStore.getState().setTokens(newAccess, newRefresh || refresh);

        // Replay queued requests
        queued.forEach(({ resolve, original }) => {
          original.headers.Authorization = `Bearer ${newAccess}`;
          resolve(api(original));
        });
        queued = [];

        original.headers.Authorization = `Bearer ${newAccess}`;
        return api(original);
      } catch (refreshErr) {
        queued.forEach(({ reject }) => reject(refreshErr));
        queued = [];
        useAuthStore.getState().logout();
        window.location.href = '/login';
        return Promise.reject(refreshErr);
      } finally {
        isRefreshing = false;
      }
    }

    // Standard error handling
    const message = error.response?.data?.message
      || error.response?.data?.detail
      || error.message
      || 'حدث خطأ ما';
    if (error.response?.status >= 500) {
      toast.error('خطأ في الخادم — حاول مرة أخرى');
    } else if (error.response?.status === 403) {
      toast.error('غير مصرح لك بهذا الإجراء');
    }
    return Promise.reject({ message, errors: error.response?.data?.errors || [], response: error.response });
  },
);

/** Helper: returns the list from a (possibly paginated) list endpoint. */
export function unwrapList(response) {
  const data = response.data;
  if (Array.isArray(data)) return data;
  if (data?.results && Array.isArray(data.results)) return data.results;
  return [];
}
