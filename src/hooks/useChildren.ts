'use client';

// Typed port of v1's useChildren, against the same live schema. Children are
// fetched through the user_children junction (owner/guardian roles from the
// sharing migrations); creation relies on the auto_add_child_owner trigger,
// so inserts never .select() (the SELECT policy checks user_children, which
// the trigger populates after insert).
import { useCallback, useEffect, useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';
import type { ChildWithRole, GuardianRole } from '@/lib/database.types';

interface UserChildJoinRow {
  role: GuardianRole;
  child: (Omit<ChildWithRole, 'userRole' | 'isOwner'>) | null;
}

export const useChildren = () => {
  const [children, setChildren] = useState<ChildWithRole[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { user } = useAuth();
  const supabase = getSupabaseBrowserClient();

  const fetchChildren = useCallback(async () => {
    if (!user || !supabase) {
      setChildren([]);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const { data, error: fetchError } = await supabase
        .from('user_children')
        .select(`
          role,
          child:children (
            *,
            catechism_assignments (*)
          )
        `)
        .eq('user_id', user.id)
        .order('created_at', { ascending: true });

      if (fetchError) throw fetchError;

      const rows = (data ?? []) as unknown as UserChildJoinRow[];
      setChildren(rows
        .filter((uc) => uc.child)
        .map((uc) => ({
          ...(uc.child as Omit<ChildWithRole, 'userRole' | 'isOwner'>),
          userRole: uc.role,
          isOwner: uc.role === 'owner',
        })));
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [user, supabase]);

  useEffect(() => {
    fetchChildren();
  }, [fetchChildren]);

  // name + age only (PRD §12): age drives pacing defaults, not birthdate.
  const addChild = async (name: string, age: number | null) => {
    if (!user || !supabase) throw new Error('Must be logged in');
    const { error: insertError } = await supabase
      .from('children')
      .insert({ user_id: user.id, name, age });
    if (insertError) throw insertError;
    await fetchChildren();
  };

  const updateChild = async (childId: string, updates: Partial<Pick<ChildWithRole, 'name' | 'age'>>) => {
    if (!supabase) throw new Error('Supabase not configured');
    const { error: updateError } = await supabase
      .from('children')
      .update(updates)
      .eq('id', childId);
    if (updateError) throw updateError;
    await fetchChildren();
  };

  const deleteChild = async (childId: string) => {
    if (!supabase) throw new Error('Supabase not configured');
    const { error: deleteError } = await supabase
      .from('children')
      .delete()
      .eq('id', childId);
    if (deleteError) throw deleteError;
    await fetchChildren();
  };

  return {
    children,
    loading,
    error,
    addChild,
    updateChild,
    deleteChild,
    refetch: fetchChildren,
  };
};
