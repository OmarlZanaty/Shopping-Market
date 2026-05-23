import axios from 'axios';

const BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000/api/v1';

export const api = axios.create({
  baseURL: BASE_URL,
  headers: { 'Content-Type': 'application/json' },
});

// Attach JWT token
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('access_token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Auto-refresh token on 401
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const original = error.config;
    if (error.response?.status === 401 && !original._retry) {
      original._retry = true;
      const refresh = localStorage.getItem('refresh_token');
      if (refresh) {
        try {
          const { data } = await axios.post(`${BASE_URL}/auth/token/refresh/`, { refresh });
          localStorage.setItem('access_token', data.access);
          original.headers.Authorization = `Bearer ${data.access}`;
          return api(original);
        } catch {
          localStorage.removeItem('access_token');
          localStorage.removeItem('refresh_token');
          window.location.href = '/login';
        }
      }
    }
    return Promise.reject(error);
  }
);

// Product API helpers
export const productApi = {
  list: (params) => api.get('/products/admin/products/', { params }),
  get: (id) => api.get(`/products/${id}/`),
  create: (data) => api.post('/products/admin/products/create/', data),
  update: (id, data) => api.patch(`/products/admin/products/${id}/`, data),
  delete: (id) => api.delete(`/products/admin/products/${id}/`),
  toggle: (id) => api.post(`/products/admin/products/${id}/toggle/`),
  bulkPrice: (updates) => api.post('/products/admin/products/bulk-price/', { updates }),
  byBarcode: (barcode) => api.get(`/products/barcode/${barcode}/`),
};

export const categoryApi = {
  list: () => api.get('/products/admin/categories/'),
  create: (data) => api.post('/products/admin/categories/', data),
  update: (id, data) => api.patch(`/products/admin/categories/${id}/`, data),
  delete: (id) => api.delete(`/products/admin/categories/${id}/`),
};

export const orderApi = {
  list: (params) => api.get('/orders/admin/all/', { params }),
  get: (orderId) => api.get(`/orders/admin/${orderId}/`),
  assignDriver: (orderId, driverId) => api.post(`/orders/admin/${orderId}/assign-driver/`, { driver_id: driverId }),
};

export const userApi = {
  list: (params) => api.get('/auth/admin/users/', { params }),
  block: (id) => api.post(`/auth/admin/users/${id}/block/`),
  drivers: (params) => api.get('/auth/admin/users/', { params: { ...params, role: 'driver' } }),
  createDriver: (data) => api.post('/auth/admin/staff/create/', { ...data, role: 'driver' }),
  createStaff:  (data) => api.post('/auth/admin/staff/create/', data),
  liveDrivers: () => api.get('/auth/admin/drivers/live/'),
  settle: (driverId, data) => api.post(`/auth/admin/drivers/${driverId}/settle/`, data),
};

export const bannerApi = {
  list: () => api.get('/products/admin/banners/'),
  create: (data) => api.post('/products/admin/banners/', data),
  update: (id, data) => api.patch(`/products/admin/banners/${id}/`, data),
  delete: (id) => api.delete(`/products/admin/banners/${id}/`),
};

export const analyticsApi = {
  dashboard: () => api.get('/analytics/dashboard/'),
  salesDaily: (days) => api.get(`/analytics/sales/daily/?days=${days}`),
  salesProducts: (days) => api.get(`/analytics/sales/products/?days=${days}`),
  salesCategories: (days) => api.get(`/analytics/sales/categories/?days=${days}`),
  drivers: (days) => api.get(`/analytics/drivers/?days=${days}`),
  ratings: (days) => api.get(`/analytics/ratings/?days=${days}`),
  inventory: () => api.get('/analytics/inventory/'),
  points: (days) => api.get(`/analytics/points/?days=${days}`),
  banners: () => api.get('/analytics/banners/'),
  peakHours: (days) => api.get(`/analytics/orders/peak-hours/?days=${days}`),
  churn: () => api.get('/analytics/customers/churn/'),
  substitutes: () => api.get('/analytics/orders/substitutes/'),
  priceAdjustments: (days) => api.get(`/analytics/orders/price-adjustments/?days=${days}`),
  closeMethod: (days) => api.get(`/analytics/orders/close-method/?days=${days}`),
};

export const notificationApi = {
  settings: () => api.get('/notifications/admin/settings/'),
  updateSetting: (id, data) => api.patch(`/notifications/admin/settings/${id}/`, data),
  createSetting: (data) => api.post('/notifications/admin/settings/', data),
  send: (data) => api.post('/notifications/admin/send/', data),
};

export const branchApi = {
  list: () => api.get('/branches/admin/'),
  create: (data) => api.post('/branches/admin/', data),
  update: (id, data) => api.patch(`/branches/admin/${id}/`, data),
  delete: (id) => api.delete(`/branches/admin/${id}/`),
};
