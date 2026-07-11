// Browser-side fetch of proof-text scripture through /api/esv (the key stays
// on the server). Deduped per osis ref for the lifetime of the page, since
// expanding the same citation twice should not refetch.
const cache = new Map<string, Promise<string | null>>();

export const fetchEsvText = (osis: string): Promise<string | null> => {
  let pending = cache.get(osis);
  if (!pending) {
    pending = fetch(`/api/esv?osis=${encodeURIComponent(osis)}`)
      .then((response) => (response.ok ? response.json() : null))
      .then((data: { text?: string | null } | null) => data?.text ?? null)
      .catch(() => null);
    cache.set(osis, pending);
  }
  return pending;
};
