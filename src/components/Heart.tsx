export type MasteryState = 'not_started' | 'reviewing' | 'mastered';

// The single mastery glyph (PRD §5.6): outline = not started, muted fill =
// reviewing, filled ochre = mastered — used identically everywhere progress
// appears. Always labeled; never a bare icon.
const GLYPH: Record<MasteryState, string> = {
  not_started: '♡',
  reviewing: '♥',
  mastered: '♥',
};

const COLOR: Record<MasteryState, string> = {
  not_started: 'text-muted',
  reviewing: 'text-heart-reviewing',
  mastered: 'text-ochre',
};

export function Heart({
  state,
  label,
  size = 15,
}: {
  state: MasteryState;
  label: string;
  size?: number;
}) {
  return (
    <span
      role="img"
      aria-label={label}
      className={COLOR[state]}
      style={{ fontSize: size, lineHeight: 1 }}
    >
      {GLYPH[state]}
    </span>
  );
}
