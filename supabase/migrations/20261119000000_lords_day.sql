-- Serialize each user's writes until commit so a pull cannot skip a late commit.
CREATE SEQUENCE public.lords_day_change_id_seq;
CREATE FUNCTION public.lords_day_set_updated_at() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.updated_at <= OLD.updated_at THEN
    RETURN NULL;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.user_id::text, 0));
  NEW.change_id = nextval('public.lords_day_change_id_seq'::regclass);
  RETURN NEW;
END;
$$;

CREATE TABLE public.lords_day_notes (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  service_date date NOT NULL,
  passage_ref text,
  sermon_title text,
  preacher text,
  church text,
  extracted_text text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  change_id bigint NOT NULL,
  UNIQUE (id, user_id)
);

CREATE TABLE public.lords_day_cards (
  id uuid PRIMARY KEY,
  note_id uuid NOT NULL,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('key_point', 'quote', 'verse')),
  body text NOT NULL,
  verse_ref text,
  attribution text,
  palette text,
  position int NOT NULL,
  edited_by_user boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  change_id bigint NOT NULL,
  FOREIGN KEY (note_id, user_id) REFERENCES public.lords_day_notes (id, user_id) ON DELETE CASCADE
);

CREATE INDEX lords_day_notes_user_id_change_id_idx ON public.lords_day_notes (user_id, change_id);
CREATE INDEX lords_day_cards_user_id_change_id_idx ON public.lords_day_cards (user_id, change_id);
CREATE INDEX lords_day_cards_note_id_user_id_idx ON public.lords_day_cards (note_id, user_id);
CREATE TRIGGER lords_day_notes_set_updated_at BEFORE INSERT OR UPDATE ON public.lords_day_notes FOR EACH ROW EXECUTE FUNCTION public.lords_day_set_updated_at();
CREATE TRIGGER lords_day_cards_set_updated_at BEFORE INSERT OR UPDATE ON public.lords_day_cards FOR EACH ROW EXECUTE FUNCTION public.lords_day_set_updated_at();
ALTER TABLE public.lords_day_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lords_day_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY lords_day_notes_select ON public.lords_day_notes FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY lords_day_notes_insert ON public.lords_day_notes FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY lords_day_notes_update ON public.lords_day_notes FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY lords_day_notes_delete ON public.lords_day_notes FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY lords_day_cards_select ON public.lords_day_cards FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY lords_day_cards_insert ON public.lords_day_cards FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY lords_day_cards_update ON public.lords_day_cards FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY lords_day_cards_delete ON public.lords_day_cards FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));
