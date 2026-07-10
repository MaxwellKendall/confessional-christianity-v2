-- Supabase Database Schema for Child Catechism Progress Tracking
-- Run this in the Supabase SQL Editor

-- Enable Row Level Security
-- Children table
CREATE TABLE IF NOT EXISTS children (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  birth_date DATE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS children_user_id_idx ON children(user_id);

-- Enable RLS
ALTER TABLE children ENABLE ROW LEVEL SECURITY;

-- RLS Policies for children table
CREATE POLICY "Users can view their own children" ON children
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own children" ON children
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own children" ON children
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own children" ON children
  FOR DELETE USING (auth.uid() = user_id);

-- Catechism Assignments table
CREATE TABLE IF NOT EXISTS catechism_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  catechism_id TEXT NOT NULL, -- WSC, WLC, CFYC, HC
  current_question INTEGER DEFAULT 1,
  started_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  UNIQUE(child_id, catechism_id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS catechism_assignments_child_id_idx ON catechism_assignments(child_id);

-- Enable RLS
ALTER TABLE catechism_assignments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for catechism_assignments table
-- Users can manage assignments for their own children
CREATE POLICY "Users can view assignments for their children" ON catechism_assignments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM children 
      WHERE children.id = catechism_assignments.child_id 
      AND children.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert assignments for their children" ON catechism_assignments
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM children 
      WHERE children.id = catechism_assignments.child_id 
      AND children.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update assignments for their children" ON catechism_assignments
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM children 
      WHERE children.id = catechism_assignments.child_id 
      AND children.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can delete assignments for their children" ON catechism_assignments
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM children 
      WHERE children.id = catechism_assignments.child_id 
      AND children.user_id = auth.uid()
    )
  );

-- Function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = timezone('utc', now());
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
CREATE TRIGGER update_children_updated_at
  BEFORE UPDATE ON children
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_catechism_assignments_updated_at
  BEFORE UPDATE ON catechism_assignments
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
