// The plain progress line: ochre on a hairline track. Ochre is scoped to
// exactly this and the mastered heart (PRD §5.6).
export function ProgressBar({ fraction }: { fraction: number }) {
  const pct = Math.max(0, Math.min(1, fraction)) * 100;
  return (
    <div className="h-0.5 overflow-hidden rounded-[1px] bg-hairline">
      <div className="h-full bg-ochre" style={{ width: `${pct}%` }} />
    </div>
  );
}
