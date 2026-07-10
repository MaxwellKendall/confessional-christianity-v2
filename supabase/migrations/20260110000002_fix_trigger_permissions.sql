-- Fix: The auto_add_child_owner trigger needs SECURITY DEFINER
-- to insert into user_children table (which has RLS enabled)

-- Recreate the function with SECURITY DEFINER
CREATE OR REPLACE FUNCTION auto_add_child_owner()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_children (user_id, child_id, role)
  VALUES (NEW.user_id, NEW.id, 'owner');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
