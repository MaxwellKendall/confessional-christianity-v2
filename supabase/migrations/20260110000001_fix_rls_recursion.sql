-- Fix infinite recursion in user_children RLS policies
-- The previous policy was self-referencing causing infinite recursion

-- Drop the problematic policies
DROP POLICY IF EXISTS "Users can view own user_children" ON user_children;
DROP POLICY IF EXISTS "Users can view co-guardians" ON user_children;
DROP POLICY IF EXISTS "Owners can add guardians" ON user_children;
DROP POLICY IF EXISTS "Users can delete user_children appropriately" ON user_children;

-- Create simplified, non-recursive policies for user_children

-- Users can only view their own user_children records
CREATE POLICY "Users can view own user_children" ON user_children
  FOR SELECT USING (auth.uid() = user_id);

-- Users can insert themselves as owner (during child creation via trigger)
-- or the system can add guardians (handled by the accept_share_invite function with SECURITY DEFINER)
CREATE POLICY "Users can insert own user_children" ON user_children
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can only delete their own guardian records (leave a shared child)
-- Owners removing others is handled by the SECURITY DEFINER function
CREATE POLICY "Users can delete own user_children" ON user_children
  FOR DELETE USING (auth.uid() = user_id);

-- Create a SECURITY DEFINER function to get co-guardians (bypasses RLS)
CREATE OR REPLACE FUNCTION get_child_guardians(p_child_id UUID)
RETURNS TABLE (
  user_id UUID,
  role TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  -- First verify the calling user has access to this child
  IF NOT EXISTS (
    SELECT 1 FROM user_children uc
    WHERE uc.child_id = p_child_id
    AND uc.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  -- Return all guardians for this child
  RETURN QUERY
  SELECT uc.user_id, uc.role, uc.created_at
  FROM user_children uc
  WHERE uc.child_id = p_child_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a SECURITY DEFINER function for owners to remove guardians
CREATE OR REPLACE FUNCTION remove_child_guardian(p_child_id UUID, p_guardian_user_id UUID)
RETURNS JSON AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  -- Get caller's role for this child
  SELECT role INTO v_caller_role
  FROM user_children
  WHERE child_id = p_child_id AND user_id = auth.uid();

  IF v_caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Access denied');
  END IF;

  IF v_caller_role != 'owner' THEN
    RETURN json_build_object('success', false, 'error', 'Only owners can remove guardians');
  END IF;

  IF p_guardian_user_id = auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Cannot remove yourself as owner');
  END IF;

  -- Remove the guardian
  DELETE FROM user_children
  WHERE child_id = p_child_id AND user_id = p_guardian_user_id;

  RETURN json_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
