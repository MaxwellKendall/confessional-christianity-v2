-- TKL-869: the prayer list was cut (TKL-856). 20261118000000_prayer_list.sql
-- stays in history (live may already have run it); a later migration drops
-- everything it created. After all migrations, none of it may remain.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);
SELECT hasnt_table('public', 'prayer_requests', 'prayer_requests is dropped');
SELECT hasnt_table('public', 'prayer_people', 'prayer_people is dropped');
SELECT hasnt_function('public', 'prayer_list_set_updated_at', 'prayer_list_set_updated_at() is dropped');
SELECT * FROM finish();
ROLLBACK;
