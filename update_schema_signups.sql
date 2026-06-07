-- ================================================================
-- HACKTROPICA UPDATE SCRIPT: Add link_signups table
-- ================================================================
-- Run this script in the Supabase SQL Editor to add detailed signup
-- tracking (with metadata) without dropping any existing tables.
-- ================================================================

CREATE TABLE IF NOT EXISTS link_signups (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  ref_code     TEXT        NOT NULL,
  signed_up_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  community    TEXT,
  device       TEXT,
  browser      TEXT,
  os           TEXT,
  trigger      TEXT
);

CREATE INDEX IF NOT EXISTS idx_link_signups_ref_code   ON link_signups(ref_code);
CREATE INDEX IF NOT EXISTS idx_link_signups_signed_up  ON link_signups(signed_up_at DESC);

ALTER TABLE link_signups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_insert_signups" ON link_signups;
CREATE POLICY "anon_insert_signups"
  ON link_signups FOR INSERT
  TO anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "auth_read_signups" ON link_signups;
CREATE POLICY "auth_read_signups"
  ON link_signups FOR SELECT
  TO authenticated
  USING (true);
