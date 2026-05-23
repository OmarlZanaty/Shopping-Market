/**
 * Single source of truth for the design-system color tokens.
 * Mirrors tailwind.config.js — use these when you need a hex literal in JS
 * (charts, status badges, dynamic styles).
 */
export const Colors = {
  sidebar:      '#0F0F1A',
  surface:      '#12121F',
  card:         '#2D2D3A',
  cardHover:    '#3A3A4A',
  text:         '#FFFFFF',
  muted:        '#6B7280',
  orange:       '#FF6B35',
  orangeDark:   '#E55A2B',
  gold:         '#FFC107',
  green:        '#22C55E',
  red:          '#EF4444',
  blue:         '#3B82F6',
  purple:       '#8B5CF6',
  inputBg:      '#2D2D3A',
  inputBorder:  '#3A3A4A',
  tableHeader:  '#1A1A2E',
  divider:      '#3A3A4A',
};

/** Spec lifecycle colors for an order status. */
export function statusColor(status) {
  switch (status) {
    case 'new':              return Colors.gold;
    case 'accepted':         return Colors.blue;
    case 'preparing':        return Colors.orange;
    case 'ready':
    case 'out_for_delivery': return Colors.purple;
    case 'delivered':        return Colors.green;
    case 'cancelled':        return Colors.red;
    default:                 return Colors.muted;
  }
}

/** Arabic label for an order status. */
export function statusLabel(status) {
  return {
    new:              'تم الاستلام',
    accepted:         'تم الموافقة',
    preparing:        'جاري التحضير',
    ready:            'جاهز للتوصيل',
    out_for_delivery: 'في الطريق',
    delivered:        'تم التوصيل',
    cancelled:        'ملغي',
  }[status] || status;
}
