import React, { useState, useEffect } from 'react';
import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useAuthStore } from '../../stores/authStore';

/**
 * Spec-exact dark-themed admin layout.
 *
 * - Sidebar: 260px (collapsed: 80px), bg-sidebar (#0F0F1A)
 * - Topbar: 64px sticky, bg-surface with bottom 1px divider
 * - Active nav item: orange background, white text
 * - WebSocket subscription: bumps new-order count + toast
 */
const NAV = [
  { path: '/dashboard',           icon: '📊', label_ar: 'لوحة التحكم',     label_en: 'Dashboard' },
  { path: '/orders',              icon: '📦', label_ar: 'الطلبات',          label_en: 'Orders',            badge: 'pending_orders' },
  { path: '/live-map',            icon: '🗺️', label_ar: 'الخريطة المباشرة', label_en: 'Live Map' },
  { divider: true, label_ar: 'المنتجات', label_en: 'Products' },
  { path: '/products',            icon: '🛍️', label_ar: 'المنتجات',         label_en: 'Products' },
  { path: '/categories',          icon: '📂', label_ar: 'الأقسام',          label_en: 'Categories' },
  { path: '/banners',             icon: '🖼️', label_ar: 'الإعلانات',        label_en: 'Banners' },
  { path: '/media',               icon: '🗄️', label_ar: 'مكتبة الوسائط',    label_en: 'Media' },
  { divider: true, label_ar: 'الأشخاص', label_en: 'People' },
  { path: '/users',               icon: '👥', label_ar: 'العملاء',          label_en: 'Customers' },
  { path: '/drivers',             icon: '🛵', label_ar: 'الموظفون',         label_en: 'Staff' },
  { path: '/branches',            icon: '🏪', label_ar: 'الفروع',           label_en: 'Branches' },
  { divider: true, label_ar: 'التقارير', label_en: 'Reports' },
  { path: '/analytics/sales',     icon: '💰', label_ar: 'المبيعات',         label_en: 'Sales' },
  { path: '/analytics/drivers',   icon: '⚡', label_ar: 'أداء المناديب',    label_en: 'Driver Perf' },
  { path: '/analytics/inventory', icon: '📦', label_ar: 'المخزون',          label_en: 'Inventory' },
  { path: '/analytics/ratings',   icon: '⭐', label_ar: 'التقييمات',        label_en: 'Ratings' },
  { path: '/analytics/points',    icon: '🏆', label_ar: 'نقاط الولاء',      label_en: 'Loyalty' },
  { divider: true, label_ar: 'الإعدادات', label_en: 'Settings' },
  { path: '/notifications',       icon: '🔔', label_ar: 'الإشعارات',        label_en: 'Notifications' },
  { path: '/admin-management',    icon: '👑', label_ar: 'المديرون',         label_en: 'Admin Management', role: 'admin' },
  { path: '/settings',            icon: '⚙️', label_ar: 'الإعدادات',        label_en: 'Settings' },
];

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [lang, setLang] = useState(localStorage.getItem('lang') || 'ar');
  const [pendingOrders, setPendingOrders] = useState(0);
  const { user, token, hasRole, logout } = useAuthStore();
  const navigate = useNavigate();

  useEffect(() => {
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.documentElement.lang = lang;
  }, [lang]);

  // Admin WebSocket — new-order push + toast.
  useEffect(() => {
    if (!token) return;
    const apiBase = import.meta.env.VITE_API_BASE_URL || 'http://63.33.70.240:8000/api/v1';
    const wsBase = apiBase
      .replace('/api/v1', '')
      .replace('http://', 'ws://')
      .replace('https://', 'wss://');
    const ws = new WebSocket(`${wsBase}/ws/admin/?token=${token}`);
    ws.onmessage = (e) => {
      try {
        const data = JSON.parse(e.data);
        if (data.type === 'new_order') {
          setPendingOrders((p) => p + 1);
          toast.success(`طلب جديد: #${data.order_number || data.order_id}`, {
            duration: 6000,
            style: { background: '#2D2D3A', color: '#FFFFFF', border: '1px solid #FF6B35' },
          });
          try { new Audio('/sounds/new_order.mp3').play().catch(() => {}); } catch { /* */ }
        }
        if (data.type === 'order_status_changed') {
          // Surfaces to TanStack Query via custom event so feature pages can invalidate.
          window.dispatchEvent(new CustomEvent('order:status_changed', { detail: data }));
        }
      } catch (_) {}
    };
    return () => ws.close();
  }, [token]);

  const toggleLang = () => {
    const next = lang === 'ar' ? 'en' : 'ar';
    setLang(next);
    localStorage.setItem('lang', next);
  };

  const label = (item) => (lang === 'ar' ? item.label_ar : item.label_en);

  return (
    <div className="flex h-screen bg-surface overflow-hidden">
      {/* Sidebar */}
      <aside
        className={`
          ${collapsed ? 'w-sidebar-collapsed' : 'w-sidebar'}
          ${mobileOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0'}
          fixed md:relative inset-y-0 right-0
          bg-sidebar text-text flex-shrink-0 flex flex-col
          transition-all duration-300 z-30
          border-l border-divider
        `}
      >
        {/* Logo */}
        <div className="h-appbar px-4 border-b border-divider flex items-center gap-3">
          <div className="w-10 h-10 bg-orange rounded-lg flex items-center justify-center flex-shrink-0 shadow-card">
            <span className="text-xl">🛒</span>
          </div>
          {!collapsed && (
            <div className="overflow-hidden">
              <div className="font-bold text-text text-sm whitespace-nowrap">Shopping Market</div>
              <div className="text-muted text-xs tracking-wider">ADMIN PANEL</div>
            </div>
          )}
        </div>

        {/* Nav */}
        <nav className="flex-1 overflow-y-auto py-3 scrollbar-thin">
          {NAV.map((item, i) => {
            if (item.role && !hasRole(item.role, 'super_admin')) return null;
            if (item.divider) {
              return !collapsed ? (
                <div key={i} className="px-4 pt-4 pb-1">
                  <div className="text-muted text-xs font-bold uppercase tracking-widest opacity-70">
                    {label(item)}
                  </div>
                </div>
              ) : <div key={i} className="my-2 mx-3 border-t border-divider" />;
            }
            return (
              <NavLink
                key={item.path}
                to={item.path}
                onClick={() => setMobileOpen(false)}
                className={({ isActive }) =>
                  `flex items-center gap-3 mx-2 my-0.5 px-3 py-2.5 rounded-btn transition-all text-sm
                  ${isActive
                    ? 'bg-orange text-white font-bold shadow-card'
                    : 'text-muted hover:bg-card hover:text-text'}`
                }
              >
                <span className="text-base flex-shrink-0">{item.icon}</span>
                {!collapsed && <span className="truncate">{label(item)}</span>}
                {!collapsed && item.badge === 'pending_orders' && pendingOrders > 0 && (
                  <span className="ml-auto bg-red text-white text-xs rounded-full min-w-[20px] h-5 px-1 flex items-center justify-center font-bold font-money">
                    {pendingOrders}
                  </span>
                )}
              </NavLink>
            );
          })}
        </nav>

        {/* User + actions */}
        <div className="p-3 border-t border-divider">
          {!collapsed && user && (
            <div className="flex items-center gap-2 mb-3 px-1">
              <div className="w-9 h-9 bg-orange rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0">
                {user.full_name?.[0]?.toUpperCase() || 'A'}
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-text text-xs font-bold truncate">{user.full_name}</div>
                <div className="text-muted text-xs">{user.role}</div>
              </div>
            </div>
          )}
          <div className="flex gap-2">
            <button onClick={toggleLang} className="flex-1 btn-ghost text-xs py-1.5 bg-card">
              {collapsed ? '🌐' : (lang === 'ar' ? 'EN' : 'عربي')}
            </button>
            <button
              onClick={() => { logout(); navigate('/login'); }}
              className="flex-1 text-xs py-1.5 rounded-btn bg-card text-muted hover:bg-red hover:text-white transition-colors"
            >
              {collapsed ? '🚪' : (lang === 'ar' ? 'خروج' : 'Logout')}
            </button>
          </div>
        </div>
      </aside>

      {/* Mobile backdrop */}
      {mobileOpen && (
        <div className="fixed inset-0 bg-black/60 z-20 md:hidden" onClick={() => setMobileOpen(false)} />
      )}

      {/* Main */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* AppBar */}
        <header className="h-appbar bg-sidebar border-b border-divider px-6 flex items-center justify-between flex-shrink-0 sticky top-0 z-10">
          <button
            onClick={() => {
              if (window.innerWidth < 768) setMobileOpen(true);
              else setCollapsed((c) => !c);
            }}
            className="btn-ghost p-2"
            aria-label="Toggle sidebar"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
          <div className="flex items-center gap-3">
            <div className="text-sm text-muted hidden sm:block">
              {new Date().toLocaleDateString(lang === 'ar' ? 'ar-EG' : 'en-US', {
                weekday: 'long', day: 'numeric', month: 'long',
              })}
            </div>
            {pendingOrders > 0 && (
              <button
                onClick={() => { navigate('/orders'); setPendingOrders(0); }}
                className="flex items-center gap-2 bg-orange text-white px-3 py-1.5 rounded-full text-xs font-bold animate-pulse"
              >
                🔔 <span className="font-money">{pendingOrders}</span>
                {lang === 'ar' ? 'طلب جديد' : 'New'}
              </button>
            )}
          </div>
        </header>

        <main className="flex-1 overflow-auto bg-surface p-6 scrollbar-thin">
          <Outlet context={{ lang }} />
        </main>
      </div>
    </div>
  );
}
