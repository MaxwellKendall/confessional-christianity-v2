-- Migration: Enable Child Sharing Between Users
-- This migration adds a junction table for user-child relationships and share invites
-- Run this in the Supabase SQL Editor AFTER the initial database.sql

-- ============================================================================
-- STEP 1: Create user_children junction table (many-to-many relationship)
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_children (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'guardian' CHECK (role IN ('owner', 'guardian')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  UNIQUE(user_id, child_id)
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS user_children_user_id_idx ON user_children(user_id);
CREATE INDEX IF NOT EXISTS user_children_child_id_idx ON user_children(child_id);

-- Enable RLS
ALTER TABLE user_children ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 2: Create child_share_invites table for pending invitations
-- ============================================================================
CREATE TABLE IF NOT EXISTS child_share_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  invited_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invite_code TEXT NOT NULL UNIQUE,
  invited_email TEXT, -- Optional: specific email invited
  accepted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  accepted_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (timezone('utc', now()) + interval '7 days') NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);

-- Create indexes
CREATE INDEX IF NOT EXISTS child_share_invites_child_id_idx ON child_share_invites(child_id);
CREATE INDEX IF NOT EXISTS child_share_invites_invite_code_idx ON child_share_invites(invite_code);
CREATE INDEX IF NOT EXISTS child_share_invites_invited_by_idx ON child_share_invites(invited_by);

-- Enable RLS
ALTER TABLE child_share_invites ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 3: Migrate existing children to user_children junction table
-- This creates owner records for all existing children based on their user_id
-- ============================================================================
INSERT INTO user_children (user_id, child_id, role)
SELECT user_id, id, 'owner'
FROM children
ON CONFLICT (user_id, child_id) DO NOTHING;

-- ============================================================================
-- STEP 4: Drop old RLS policies on children table
-- ============================================================================
DROP POLICY IF EXISTS "Users can view their own children" ON children;
DROP POLICY IF EXISTS "Users can insert their own children" ON children;
DROP POLICY IF EXISTS "Users can update their own children" ON children;
DROP POLICY IF EXISTS "Users can delete their own children" ON children;

-- ============================================================================
-- STEP 5: Create new RLS policies for children table (using junction table)
-- ============================================================================

-- Users can view children they have access to via user_children
CREATE POLICY "Users can view children via user_children" ON children
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = children.id 
      AND user_children.user_id = auth.uid()
    )
  );

-- Users can insert children (they become the owner)
CREATE POLICY "Users can insert children" ON children
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update children they have access to
CREATE POLICY "Users can update children via user_children" ON children
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = children.id 
      AND user_children.user_id = auth.uid()
    )
  );

-- Only owners can delete children
CREATE POLICY "Only owners can delete children" ON children
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = children.id 
      AND user_children.user_id = auth.uid()
      AND user_children.role = 'owner'
    )
  );

-- ============================================================================
-- STEP 6: RLS policies for user_children table
-- ============================================================================

-- Users can view their own user_children records
CREATE POLICY "Users can view own user_children" ON user_children
  FOR SELECT USING (auth.uid() = user_id);

-- Users can also view other users who share the same child
CREATE POLICY "Users can view co-guardians" ON user_children
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_children AS my_children
      WHERE my_children.child_id = user_children.child_id
      AND my_children.user_id = auth.uid()
    )
  );

-- Only owners can insert new user_children records (to share)
CREATE POLICY "Owners can add guardians" ON user_children
  FOR INSERT WITH CHECK (
    -- Either inserting self as owner during child creation
    (auth.uid() = user_id AND role = 'owner')
    OR
    -- Or an existing owner is adding a guardian
    EXISTS (
      SELECT 1 FROM user_children AS owner_check
      WHERE owner_check.child_id = user_children.child_id
      AND owner_check.user_id = auth.uid()
      AND owner_check.role = 'owner'
    )
  );

-- Owners can remove guardians, and users can remove themselves
CREATE POLICY "Users can delete user_children appropriately" ON user_children
  FOR DELETE USING (
    -- User removing themselves
    auth.uid() = user_id
    OR
    -- Owner removing a guardian
    EXISTS (
      SELECT 1 FROM user_children AS owner_check
      WHERE owner_check.child_id = user_children.child_id
      AND owner_check.user_id = auth.uid()
      AND owner_check.role = 'owner'
    )
  );

-- ============================================================================
-- STEP 7: RLS policies for child_share_invites table
-- ============================================================================

-- Users can view invites they created or for children they own
CREATE POLICY "Users can view invites for their children" ON child_share_invites
  FOR SELECT USING (
    invited_by = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM user_children
      WHERE user_children.child_id = child_share_invites.child_id
      AND user_children.user_id = auth.uid()
    )
  );

-- Anyone can view an invite by its code (for accepting)
CREATE POLICY "Anyone can lookup invite by code" ON child_share_invites
  FOR SELECT USING (true);

-- Only owners can create invites
CREATE POLICY "Owners can create invites" ON child_share_invites
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_children
      WHERE user_children.child_id = child_share_invites.child_id
      AND user_children.user_id = auth.uid()
      AND user_children.role = 'owner'
    )
  );

-- Owners can update/delete their invites
CREATE POLICY "Owners can update invites" ON child_share_invites
  FOR UPDATE USING (invited_by = auth.uid());

CREATE POLICY "Owners can delete invites" ON child_share_invites
  FOR DELETE USING (invited_by = auth.uid());

-- ============================================================================
-- STEP 8: Update catechism_assignments RLS to use junction table
-- ============================================================================

-- Drop old policies
DROP POLICY IF EXISTS "Users can view assignments for their children" ON catechism_assignments;
DROP POLICY IF EXISTS "Users can insert assignments for their children" ON catechism_assignments;
DROP POLICY IF EXISTS "Users can update assignments for their children" ON catechism_assignments;
DROP POLICY IF EXISTS "Users can delete assignments for their children" ON catechism_assignments;

-- Create new policies using junction table
CREATE POLICY "Users can view assignments via user_children" ON catechism_assignments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = catechism_assignments.child_id 
      AND user_children.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert assignments via user_children" ON catechism_assignments
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = catechism_assignments.child_id 
      AND user_children.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update assignments via user_children" ON catechism_assignments
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = catechism_assignments.child_id 
      AND user_children.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can delete assignments via user_children" ON catechism_assignments
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = catechism_assignments.child_id 
      AND user_children.user_id = auth.uid()
    )
  );

-- ============================================================================
-- STEP 9: Create function to accept a share invite
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_share_invite(p_invite_code TEXT)
RETURNS JSON AS $$
DECLARE
  v_invite child_share_invites%ROWTYPE;
  v_user_id UUID;
  v_result JSON;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Find the invite
  SELECT * INTO v_invite
  FROM child_share_invites
  WHERE invite_code = p_invite_code;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invite not found');
  END IF;
  
  -- Check if expired
  IF v_invite.expires_at < timezone('utc', now()) THEN
    RETURN json_build_object('success', false, 'error', 'Invite has expired');
  END IF;
  
  -- Check if already accepted
  IF v_invite.accepted_at IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'Invite has already been used');
  END IF;
  
  -- Check if user already has access
  IF EXISTS (
    SELECT 1 FROM user_children 
    WHERE user_id = v_user_id AND child_id = v_invite.child_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'You already have access to this child');
  END IF;
  
  -- Add user as guardian
  INSERT INTO user_children (user_id, child_id, role)
  VALUES (v_user_id, v_invite.child_id, 'guardian');
  
  -- Mark invite as accepted
  UPDATE child_share_invites
  SET accepted_by = v_user_id, accepted_at = timezone('utc', now())
  WHERE id = v_invite.id;
  
  -- Get child name for response
  SELECT json_build_object(
    'success', true,
    'child_id', v_invite.child_id,
    'child_name', c.name
  ) INTO v_result
  FROM children c
  WHERE c.id = v_invite.child_id;
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- STEP 10: Create trigger to auto-add owner to user_children when child created
-- ============================================================================
CREATE OR REPLACE FUNCTION auto_add_child_owner()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_children (user_id, child_id, role)
  VALUES (NEW.user_id, NEW.id, 'owner');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS add_child_owner_trigger ON children;

CREATE TRIGGER add_child_owner_trigger
  AFTER INSERT ON children
  FOR EACH ROW
  EXECUTE FUNCTION auto_add_child_owner();
