const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

// "2026-07-08" -> "July 8, 2026" (long) or "Jul 8" (short). Dates are plain
// ISO strings; parsed manually to stay timezone-proof at build time.
export const formatDate = (iso: string | null, style: 'long' | 'short' = 'long'): string => {
  if (!iso) return '';
  const [year, month, day] = iso.split('-').map(Number);
  if (!year || !month || !day) return iso;
  const name = MONTHS[month - 1];
  return style === 'long'
    ? `${name} ${day}, ${year}`
    : `${name.slice(0, 3)} ${day}`;
};
