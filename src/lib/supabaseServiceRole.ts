import { createClient } from '@supabase/supabase-js';

// Server-only Supabase client with the service-role key, which bypasses Row
// Level Security and can call auth.admin.*. Import it only from route
// handlers under src/app/api/**; never from client components, and never
// ship the key to the iOS app.
export function getSupabaseServiceRole() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    throw new Error('NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for service-role Supabase access.');
  }
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
