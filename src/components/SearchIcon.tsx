// hand-drawn inline SVG magnifying glass per the handoff — no icon library.
export function SearchIcon({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" aria-hidden="true">
      <circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" strokeWidth="1.4" />
      <line x1="13" y1="13" x2="18" y2="18" stroke="currentColor" strokeWidth="1.4" />
    </svg>
  );
}
