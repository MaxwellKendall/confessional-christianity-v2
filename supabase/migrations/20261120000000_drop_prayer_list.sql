-- TKL-869: the prayer list was cut (TKL-856, TKL-828 cancelled). Reverses
-- 20261118000000_prayer_list.sql, which stays in history because the live
-- project may already have applied it. IF EXISTS makes this correct either way.
-- Dropping the tables also drops their triggers, indexes and RLS policies.
-- prayer_requests first: it has a foreign key to prayer_people.
DROP TABLE IF EXISTS public.prayer_requests;
DROP TABLE IF EXISTS public.prayer_people;
DROP FUNCTION IF EXISTS public.prayer_list_set_updated_at();
