-- TKL-809: prayer list tables — shape, updated_at trigger, and RLS isolation.
-- Run locally: supabase start && supabase test db
-- Everything runs in one transaction and is rolled back by pgTAP.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(35);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
SELECT has_table('public', 'prayer_people', 'prayer_people exists');
SELECT has_table('public', 'prayer_requests', 'prayer_requests exists');
SELECT columns_are('public', 'prayer_people',
  ARRAY['id', 'user_id', 'name', 'created_at', 'updated_at', 'deleted_at'],
  'prayer_people has exactly the agreed columns');
SELECT columns_are('public', 'prayer_requests',
  ARRAY['id', 'user_id', 'person_id', 'text', 'created_at', 'archived_at', 'answered_at', 'updated_at', 'deleted_at'],
  'prayer_requests has exactly the agreed columns');
SELECT col_is_pk('public', 'prayer_people', 'id', 'prayer_people.id is the primary key');
SELECT col_is_pk('public', 'prayer_requests', 'id', 'prayer_requests.id is the primary key');
SELECT col_hasnt_default('public', 'prayer_people', 'id', 'prayer_people.id is supplied by the client');
SELECT col_hasnt_default('public', 'prayer_requests', 'id', 'prayer_requests.id is supplied by the client');
SELECT has_index('public', 'prayer_people', 'prayer_people_user_id_updated_at_idx',
  ARRAY['user_id', 'updated_at'], 'prayer_people has the pull-since-cursor index');
SELECT has_index('public', 'prayer_requests', 'prayer_requests_user_id_updated_at_idx',
  ARRAY['user_id', 'updated_at'], 'prayer_requests has the pull-since-cursor index');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.prayer_people'::regclass),
  'RLS is enabled on prayer_people');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.prayer_requests'::regclass),
  'RLS is enabled on prayer_requests');

-- ---------------------------------------------------------------------------
-- Fixtures: two users, each with one person and one request.
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@example.test'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@example.test');

-- Act as user A.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

SELECT lives_ok($$
  INSERT INTO prayer_people (id, user_id, name, updated_at)
  VALUES ('a0000000-0000-0000-0000-00000000000a', auth.uid(), 'A person', '2000-01-01')
$$, 'user A can insert their own person');
SELECT lives_ok($$
  INSERT INTO prayer_requests (id, user_id, person_id, text)
  VALUES ('a0000000-0000-0000-0000-0000000000a1', auth.uid(), 'a0000000-0000-0000-0000-00000000000a', 'A request')
$$, 'user A can insert their own request');
SELECT ok((SELECT updated_at > '2000-01-02' FROM prayer_people WHERE id = 'a0000000-0000-0000-0000-00000000000a'),
  'updated_at is set by the server on insert, not taken from the client');

-- updated_at moves forward on every update.
CREATE TEMP TABLE before_update ON COMMIT DROP AS
  SELECT updated_at FROM prayer_requests WHERE id = 'a0000000-0000-0000-0000-0000000000a1';
SELECT pg_sleep(0.01);
UPDATE prayer_requests SET answered_at = now() WHERE id = 'a0000000-0000-0000-0000-0000000000a1';
SELECT ok((SELECT r.updated_at > b.updated_at FROM prayer_requests r, before_update b
           WHERE r.id = 'a0000000-0000-0000-0000-0000000000a1'),
  'updated_at is bumped by trigger on update');
SELECT ok((SELECT answered_at IS NOT NULL FROM prayer_requests WHERE id = 'a0000000-0000-0000-0000-0000000000a1'),
  'user A can mark their own request answered');

-- Act as user B.
SELECT set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
INSERT INTO prayer_people (id, user_id, name)
  VALUES ('b0000000-0000-0000-0000-00000000000b', auth.uid(), 'B person');
INSERT INTO prayer_requests (id, user_id, person_id, text)
  VALUES ('b0000000-0000-0000-0000-0000000000b1', auth.uid(), 'b0000000-0000-0000-0000-00000000000b', 'B request');

-- B cannot read A's rows.
SELECT is((SELECT count(*)::int FROM prayer_people), 1, 'user B sees only their own people');
SELECT is((SELECT count(*)::int FROM prayer_requests), 1, 'user B sees only their own requests');
SELECT is_empty($$ SELECT 1 FROM prayer_people WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'user B cannot select user A''s people');
SELECT is_empty($$ SELECT 1 FROM prayer_requests WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'user B cannot select user A''s requests');

-- B cannot insert rows owned by A.
SELECT throws_ok($$
  INSERT INTO prayer_people (id, user_id, name)
  VALUES ('b0000000-0000-0000-0000-0000000000ff', 'aaaaaaaa-0000-0000-0000-000000000001', 'forged')
$$, '42501', NULL, 'user B cannot insert a person owned by user A');
SELECT throws_ok($$
  INSERT INTO prayer_requests (id, user_id, person_id, text)
  VALUES ('b0000000-0000-0000-0000-0000000000fe', 'aaaaaaaa-0000-0000-0000-000000000001',
          'a0000000-0000-0000-0000-00000000000a', 'forged')
$$, '42501', NULL, 'user B cannot insert a request owned by user A');
-- B cannot attach their own request to A's person.
SELECT throws_ok($$
  INSERT INTO prayer_requests (id, user_id, person_id, text)
  VALUES ('b0000000-0000-0000-0000-0000000000fd', auth.uid(), 'a0000000-0000-0000-0000-00000000000a', 'cross-link')
$$, '23503', NULL, 'user B cannot attach a request to user A''s person');

-- B cannot hand their own rows to A.
SELECT throws_ok($$
  UPDATE prayer_people SET user_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  WHERE id = 'b0000000-0000-0000-0000-00000000000b'
$$, '42501', NULL, 'user B cannot reassign a person to user A');
SELECT throws_ok($$
  UPDATE prayer_requests SET user_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  WHERE id = 'b0000000-0000-0000-0000-0000000000b1'
$$, '42501', NULL, 'user B cannot reassign a request to user A');

-- B's updates and deletes against A's rows touch nothing.
UPDATE prayer_people SET name = 'hacked', deleted_at = now() WHERE id = 'a0000000-0000-0000-0000-00000000000a';
UPDATE prayer_requests SET text = 'hacked', deleted_at = now() WHERE id = 'a0000000-0000-0000-0000-0000000000a1';
DELETE FROM prayer_requests WHERE id = 'a0000000-0000-0000-0000-0000000000a1';
DELETE FROM prayer_people WHERE id = 'a0000000-0000-0000-0000-00000000000a';

-- Anonymous callers see nothing.
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT is_empty($$ SELECT 1 FROM prayer_people $$, 'anon cannot select people');
SELECT is_empty($$ SELECT 1 FROM prayer_requests $$, 'anon cannot select requests');

-- Back to user A: their rows survived B's update and delete untouched.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT is((SELECT name FROM prayer_people WHERE id = 'a0000000-0000-0000-0000-00000000000a'), 'A person',
  'user B''s update did not change user A''s person');
SELECT is((SELECT text FROM prayer_requests WHERE id = 'a0000000-0000-0000-0000-0000000000a1'), 'A request',
  'user B''s update did not change user A''s request');
SELECT ok((SELECT deleted_at IS NULL FROM prayer_people WHERE id = 'a0000000-0000-0000-0000-00000000000a'),
  'user B could not soft-delete user A''s person');
SELECT is((SELECT count(*)::int FROM prayer_requests), 1, 'user B''s delete left user A''s request in place');
SELECT is((SELECT count(*)::int FROM prayer_people), 1, 'user A sees only their own people');

-- A can delete their own rows (hard delete cascades to requests).
DELETE FROM prayer_people WHERE id = 'a0000000-0000-0000-0000-00000000000a';
SELECT is((SELECT count(*)::int FROM prayer_requests), 0, 'deleting a person removes their requests');

-- B's rows are untouched by A's delete.
SELECT set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
SELECT is((SELECT count(*)::int FROM prayer_requests), 1, 'user A''s delete left user B''s request in place');

SELECT * FROM finish();
ROLLBACK;
