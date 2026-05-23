import React, { Suspense, lazy } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'react-hot-toast';
import { useAuthStore } from './stores/authStore';
import Layout from './components/layout/Layout';
import LoginPage from './pages/LoginPage';
import LoadingSpinner from './components/shared/LoadingSpinner';

const Dashboard          = lazy(() => import('./pages/Dashboard'));
const OrdersPage         = lazy(() => import('./pages/OrdersPage'));
const OrderDetailPage    = lazy(() => import('./pages/OrderDetailPage'));
const ProductsPage       = lazy(() => import('./pages/ProductsPage'));
const ProductFormPage    = lazy(() => import('./pages/ProductFormPage'));
const CategoriesPage     = lazy(() => import('./pages/CategoriesPage'));
const UsersPage          = lazy(() => import('./pages/UsersPage'));
const DriversPage        = lazy(() => import('./pages/DriversPage'));
const DriverFormPage     = lazy(() => import('./pages/DriverFormPage'));
const BannersPage        = lazy(() => import('./pages/BannersPage'));
const MediaLibraryPage   = lazy(() => import('./pages/MediaLibraryPage'));
const LiveMapPage        = lazy(() => import('./pages/LiveMapPage'));
const BranchesPage       = lazy(() => import('./pages/BranchesPage'));
const NotificationsPage  = lazy(() => import('./pages/NotificationsPage'));
const SettingsPage       = lazy(() => import('./pages/SettingsPage'));
const AdminManagement    = lazy(() => import('./pages/AdminManagementPage'));
const SalesPage          = lazy(() => import('./pages/analytics/SalesPage'));
const DriversAnalytics   = lazy(() => import('./pages/analytics/DriversPage'));
const InventoryPage      = lazy(() => import('./pages/analytics/InventoryPage'));
const RatingsPage        = lazy(() => import('./pages/analytics/RatingsPage'));
const PointsPage         = lazy(() => import('./pages/analytics/PointsPage'));

const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 30000 } } });

function ProtectedRoute({ children }) {
  const { token } = useAuthStore();
  if (!token) return <Navigate to="/login" replace />;
  return children;
}

const S = ({ children }) => <Suspense fallback={<LoadingSpinner />}>{children}</Suspense>;

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Toaster position="top-right" toastOptions={{ duration: 3000 }} />
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/" element={<ProtectedRoute><Layout /></ProtectedRoute>}>
            <Route index element={<Navigate to="/dashboard" replace />} />
            <Route path="dashboard"             element={<S><Dashboard /></S>} />
            <Route path="orders"                element={<S><OrdersPage /></S>} />
            <Route path="orders/:orderId"       element={<S><OrderDetailPage /></S>} />
            <Route path="products"              element={<S><ProductsPage /></S>} />
            <Route path="products/new"          element={<S><ProductFormPage /></S>} />
            <Route path="products/:id/edit"     element={<S><ProductFormPage /></S>} />
            <Route path="categories"            element={<S><CategoriesPage /></S>} />
            <Route path="users"                 element={<S><UsersPage /></S>} />
            <Route path="drivers"               element={<S><DriversPage /></S>} />
            <Route path="drivers/new"           element={<S><DriverFormPage /></S>} />
            <Route path="live-map"              element={<S><LiveMapPage /></S>} />
            <Route path="banners"               element={<S><BannersPage /></S>} />
            <Route path="media"                 element={<S><MediaLibraryPage /></S>} />
            <Route path="branches"              element={<S><BranchesPage /></S>} />
            <Route path="notifications"         element={<S><NotificationsPage /></S>} />
            <Route path="settings"              element={<S><SettingsPage /></S>} />
            <Route path="admin-management"      element={<S><AdminManagement /></S>} />
            <Route path="analytics/sales"       element={<S><SalesPage /></S>} />
            <Route path="analytics/drivers"     element={<S><DriversAnalytics /></S>} />
            <Route path="analytics/inventory"   element={<S><InventoryPage /></S>} />
            <Route path="analytics/ratings"     element={<S><RatingsPage /></S>} />
            <Route path="analytics/points"      element={<S><PointsPage /></S>} />
          </Route>
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
