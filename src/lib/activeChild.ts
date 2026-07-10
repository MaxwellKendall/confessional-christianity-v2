// The homepage shows one child's context at a time (PRD §5.5/§8); the active
// selection is a client-side preference, not server state.
const KEY = 'cc-active-child-id';

export const getActiveChildId = (): string | null => {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(KEY);
};

export const setActiveChildId = (childId: string): void => {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(KEY, childId);
};
