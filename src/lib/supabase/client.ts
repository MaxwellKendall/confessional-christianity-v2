import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const isSupabaseConfigured = (): boolean => Boolean(
  supabaseUrl && supabasePublishableKey,
);

let browserClient: SupabaseClient | null = null;

// Lazy singleton; returns null when env is absent (e.g. CI builds) so the
// static surfaces never depend on Supabase being configured.
export const getSupabaseBrowserClient = (): SupabaseClient | null => {
  if (!isSupabaseConfigured()) return null;
  if (!browserClient) {
    browserClient = createBrowserClient(supabaseUrl!, supabasePublishableKey!);
  }
  return browserClient;
};
