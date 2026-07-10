-- User Catechism Assignments table for personal progress tracking (not tied to a child)
-- This allows users to track their own catechism memorization progress

CREATE TABLE IF NOT EXISTS user_catechism_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  catechism_id TEXT NOT NULL, -- WSC, WLC, CfYC, HC
  current_question INTEGER DEFAULT 1,
  started_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  UNIQUE(user_id, catechism_id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS user_catechism_assignments_user_id_idx ON user_catechism_assignments(user_id);

-- Enable RLS
ALTER TABLE user_catechism_assignments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_catechism_assignments table
-- Users can only manage their own assignments
CREATE POLICY "Users can view their own catechism assignments" ON user_catechism_assignments
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own catechism assignments" ON user_catechism_assignments
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own catechism assignments" ON user_catechism_assignments
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own catechism assignments" ON user_catechism_assignments
  FOR DELETE USING (auth.uid() = user_id);

-- Trigger for updated_at (reuses existing function)
CREATE TRIGGER update_user_catechism_assignments_updated_at
  BEFORE UPDATE ON user_catechism_assignments
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
