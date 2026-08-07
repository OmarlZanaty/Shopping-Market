/**
 * The reason a request failed, not the envelope's generic label.
 *
 * The backend wraps every DRF error as
 *   { success: false, message, errors: [{ field, message }] }
 * and a plain field error (the common case) leaves `message` as the literal
 * string 'Request error' while the useful text sits in `errors`. Pages that
 * toasted `message` alone showed the admin "Request error" and nothing else.
 */
export const apiError = (error, fallback = '') => {
  const data = error?.response?.data;
  const fields = Array.isArray(data?.errors)
    ? data.errors.map((item) => item?.message).filter(Boolean)
    : [];
  if (fields.length) return fields.join(' — ');
  const message = data?.message;
  if (message && message !== 'Request error') return message;
  // No response at all means the request never reached the server.
  if (!error?.response) return fallback || 'تعذّر الاتصال بالخادم — Could not reach the server';
  return fallback;
};

export default apiError;
