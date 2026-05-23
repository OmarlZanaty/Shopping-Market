/**
 * Spec-exact dark-theme palette for the Admin Dashboard.
 * Every color used in the UI MUST come from here — no inline hex values.
 */
export default {
  content: ['./index.html', './src/**/*.{js,jsx,ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        sans: ['Cairo', 'Inter', 'system-ui', 'sans-serif'],
        cairo: ['Cairo', 'system-ui', 'sans-serif'],
        inter: ['Inter', 'system-ui', 'sans-serif'],
        money: ['Inter', 'monospace'],
      },
      colors: {
        // Spec design system
        sidebar:       '#0F0F1A',
        surface:       '#12121F',
        card:          '#2D2D3A',
        'card-hover':  '#3A3A4A',
        text:          '#FFFFFF',
        muted:         '#6B7280',
        orange:        '#FF6B35',
        'orange-dark': '#E55A2B',
        gold:          '#FFC107',
        green:         '#22C55E',
        red:           '#EF4444',
        blue:          '#3B82F6',
        purple:        '#8B5CF6',
        'input-bg':    '#2D2D3A',
        'input-border': '#3A3A4A',
        'table-header': '#1A1A2E',
        divider:       '#3A3A4A',
        // Legacy aliases — kept so existing pages keep compiling. New code MUST
        // use the spec names above.
        primary: { DEFAULT: '#FF6B35', dark: '#0F0F1A', light: '#FFC107', ice: '#2D2D3A' },
        coral: '#FF6B35', mint: '#22C55E', watermelon: '#EF4444',
      },
      borderRadius: {
        card: '12px',
        btn:  '8px',
        badge:'4px',
      },
      boxShadow: {
        card: '0 4px 12px rgba(255,107,53,0.08)',
      },
      spacing: {
        sidebar: '260px',
        'sidebar-collapsed': '80px',
        appbar: '64px',
      },
    },
  },
  plugins: [],
};
