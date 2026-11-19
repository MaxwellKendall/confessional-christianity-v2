-- v1.1 prayer list sync (TKL-809, Outcome 2 / TKL-828). Additive only: two new
-- per-user tables, no change to any existing table.
--
-- Sync model: the phone creates rows offline, so ids are client-supplied UUIDs
-- (no default). Deletes are soft (deleted_at) so they propagate on pull; a
-- client pulls "rows where updated_at > my cursor" per user, served by the
-- (user_id, updated_at) indexes. updated_at is always server time, set by
-- trigger on insert and update, so a skewed phone clock can't hide a row from
-- another device's cursor.

CREATE OR REPLACE FUNCTION public.prayer_list_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = clock_timestamp();
  RETURN NEW;
END;
$$;

-- ============================================================================
-- prayer_people: someone the user prays for (DomainKit PrayerPerson).
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.prayer_people (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  -- Target of prayer_requests' composite FK, which pins a request to a person
  -- owned by the same user.
  UNIQUE (id, user_id)
);

CREATE INDEX IF NOT EXISTS prayer_people_user_id_updated_at_idx
  ON public.prayer_people (user_id, updated_at);

CREATE TRIGGER prayer_people_set_updated_at
  BEFORE INSERT OR UPDATE ON public.prayer_people
  FOR EACH ROW EXECUTE FUNCTION public.prayer_list_set_updated_at();

-- ============================================================================
-- prayer_requests: one request for a person (DomainKit PrayerRequestEntry).
-- archived_at = moved off the front burner; answered_at = marked answered.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.prayer_requests (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id UUID NOT NULL,
  text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  archived_at TIMESTAMPTZ,
  answered_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  -- (person_id, user_id), not person_id alone: FK checks bypass RLS, so a
  -- plain FK would let one user attach rows to (and probe for) another
  -- user's person ids.
  FOREIGN KEY (person_id, user_id)
    REFERENCES public.prayer_people (id, user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS prayer_requests_user_id_updated_at_idx
  ON public.prayer_requests (user_id, updated_at);
CREATE INDEX IF NOT EXISTS prayer_requests_person_id_user_id_idx
  ON public.prayer_requests (person_id, user_id);

CREATE TRIGGER prayer_requests_set_updated_at
  BEFORE INSERT OR UPDATE ON public.prayer_requests
  FOR EACH ROW EXECUTE FUNCTION public.prayer_list_set_updated_at();

-- ============================================================================
-- RLS: a signed-in user reads and writes only their own rows. anon gets
-- nothing (no policy grants it access).
-- ============================================================================
ALTER TABLE public.prayer_people ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prayer_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own prayer people" ON public.prayer_people
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY "Users can insert their own prayer people" ON public.prayer_people
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "Users can update their own prayer people" ON public.prayer_people
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "Users can delete their own prayer people" ON public.prayer_people
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can view their own prayer requests" ON public.prayer_requests
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY "Users can insert their own prayer requests" ON public.prayer_requests
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "Users can update their own prayer requests" ON public.prayer_requests
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "Users can delete their own prayer requests" ON public.prayer_requests
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));
