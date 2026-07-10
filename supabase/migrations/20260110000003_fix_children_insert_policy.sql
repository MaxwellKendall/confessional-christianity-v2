-- Fix children INSERT policy
-- Drop ALL possible policy names and recreate cleanly

-- Drop any existing INSERT policies (trying all possible names)
DROP POLICY IF EXISTS "Users can insert their own children" ON children;
DROP POLICY IF EXISTS "Users can insert children" ON children;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON children;

-- Recreate the INSERT policy
CREATE POLICY "Users can insert children" ON children
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

-- Also ensure SELECT/UPDATE/DELETE policies exist and use user_children
DROP POLICY IF EXISTS "Users can view children via user_children" ON children;
DROP POLICY IF EXISTS "Users can update children via user_children" ON children;
DROP POLICY IF EXISTS "Only owners can delete children" ON children;

CREATE POLICY "Users can view children via user_children" ON children
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = children.id 
      AND user_children.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update children via user_children" ON children
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = children.id 
      AND user_children.user_id = auth.uid()
    )
  );

CREATE POLICY "Only owners can delete children" ON children
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM user_children 
      WHERE user_children.child_id = children.id 
      AND user_children.user_id = auth.uid()
      AND user_children.role = 'owner'
    )
  );
