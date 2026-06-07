-- ================================================================
-- HACKTROPICA REFERRAL DASHBOARD — SUPABASE SCHEMA
-- ================================================================
-- Run this entire file in: Supabase dashboard → SQL Editor → New query
--
-- IMPORTANT: This assumes you already have a "referrals" table
-- with columns "username" (TEXT, the ref code) and "count" (INTEGER,
-- total signups for that code). That table is NOT recreated or altered
-- beyond adding a UNIQUE constraint on "username" if one doesn't exist.
--
-- What this creates / configures:
--   1. referral_links   — links you create and manage in this dashboard
--   2. link_clicks      — one row per click through track.html
--   3. Indexes          — fast lookups on both tables + referrals.username
--   4. RLS policies     — public can insert click events; only your
--                         authenticated account can read or manage data
--   5. Helper functions — aggregation queries used by the dashboard
--   6. record_referral  — atomic upsert function for the helloneural.ai snippet
--
-- After running, create your login account:
--   Supabase → Authentication → Users → Add user (set email + password)
-- ================================================================


-- ================================================================
-- TABLES (only our new tables — referrals already exists)
-- ================================================================

-- Links you create in the dashboard. ref_code maps to referrals.username.
CREATE TABLE IF NOT EXISTS referral_links (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  ref_code    TEXT        NOT NULL UNIQUE,
  description TEXT        NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row every time someone visits your click-tracking redirect link.
CREATE TABLE IF NOT EXISTS link_clicks (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  ref_code   TEXT        NOT NULL,
  clicked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  community  TEXT,
  device     TEXT,
  browser    TEXT,
  os         TEXT,
  trigger    TEXT
);


-- ================================================================
-- UNIQUE CONSTRAINT ON referrals.username
-- Required for the atomic record_referral upsert to work correctly.
-- Skipped safely if a unique constraint already exists on that column.
-- ================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   information_schema.table_constraints tc
    JOIN   information_schema.key_column_usage  kcu
           ON kcu.constraint_name = tc.constraint_name
          AND kcu.table_schema    = tc.table_schema
          AND kcu.table_name      = tc.table_name
    WHERE  tc.table_schema    = 'public'
      AND  tc.table_name      = 'referrals'
      AND  tc.constraint_type = 'UNIQUE'
      AND  kcu.column_name    = 'username'
  ) THEN
    ALTER TABLE public.referrals
      ADD CONSTRAINT referrals_username_key UNIQUE (username);
  END IF;
END;
$$;


-- ================================================================
-- INDEXES
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_referral_links_ref_code ON referral_links(ref_code);
CREATE INDEX IF NOT EXISTS idx_link_clicks_ref_code    ON link_clicks(ref_code);
CREATE INDEX IF NOT EXISTS idx_link_clicks_clicked_at  ON link_clicks(clicked_at DESC);
CREATE INDEX IF NOT EXISTS idx_referrals_username      ON referrals(username);


-- ================================================================
-- ROW LEVEL SECURITY
-- ================================================================

ALTER TABLE referral_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE link_clicks    ENABLE ROW LEVEL SECURITY;

-- referral_links: only authenticated dashboard users can manage
DROP POLICY IF EXISTS "auth_manage_links" ON referral_links;
CREATE POLICY "auth_manage_links"
  ON referral_links FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

-- link_clicks: public (anon) inserts from track.html; authenticated can read
DROP POLICY IF EXISTS "anon_insert_clicks" ON link_clicks;
CREATE POLICY "anon_insert_clicks"
  ON link_clicks FOR INSERT
  TO anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "auth_read_clicks" ON link_clicks;
CREATE POLICY "auth_read_clicks"
  ON link_clicks FOR SELECT
  TO authenticated
  USING (true);

-- referrals: dashboard reads via SECURITY DEFINER functions, so no RLS
-- policy is required for those. We add an explicit SELECT policy anyway
-- so the authenticated user can also query the table directly if needed.
DROP POLICY IF EXISTS "auth_read_referrals" ON referrals;
CREATE POLICY "auth_read_referrals"
  ON referrals FOR SELECT
  TO authenticated
  USING (true);


-- ================================================================
-- HELPER FUNCTIONS
-- ================================================================
-- Called via db.rpc() in the dashboard. SECURITY DEFINER lets them
-- bypass RLS and join across referral_links, link_clicks, and referrals.
-- ================================================================

-- get_link_stats()
-- Every managed link with its total click count (from link_clicks) and
-- total signup count (from referrals.count where username = ref_code).
-- Only links that exist in referral_links are returned.
DROP FUNCTION IF EXISTS get_link_stats();
CREATE FUNCTION get_link_stats()
RETURNS TABLE (
  id          UUID,
  name        TEXT,
  ref_code    TEXT,
  description TEXT,
  created_at  TIMESTAMPTZ,
  clicks      BIGINT,
  ref_count   BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    rl.id,
    rl.name,
    rl.ref_code,
    rl.description,
    rl.created_at,
    COALESCE(lc.cnt, 0)            AS clicks,
    COALESCE(rv."count"::BIGINT, 0) AS ref_count
  FROM public.referral_links rl
  LEFT JOIN (
    SELECT lc2.ref_code, COUNT(*) AS cnt
    FROM   public.link_clicks lc2
    GROUP  BY lc2.ref_code
  ) lc ON lc.ref_code = rl.ref_code
  LEFT JOIN public.referrals rv ON rv.username = rl.ref_code
  ORDER BY rl.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_link_stats TO authenticated;


-- get_daily_stats(p_ref_code, p_days)
-- One row per day for the last p_days days with click counts.
-- Referral totals are not time-tracked in the existing referrals table,
-- so ref_count is always 0 here — use get_link_stats for all-time totals.
-- Pass NULL for p_ref_code to aggregate all managed links.
DROP FUNCTION IF EXISTS get_daily_stats(TEXT, INTEGER);
CREATE FUNCTION get_daily_stats(
  p_ref_code TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 30
)
RETURNS TABLE (
  day       DATE,
  clicks    BIGINT,
  ref_count BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH date_series AS (
    SELECT (CURRENT_DATE - i)::date AS dy
    FROM   generate_series(p_days - 1, 0, -1) AS gs(i)
  ),
  managed_codes AS (
    SELECT rl2.ref_code AS rc
    FROM   public.referral_links rl2
    WHERE  p_ref_code IS NULL OR rl2.ref_code = p_ref_code
  ),
  daily_clicks AS (
    SELECT lc.clicked_at::date AS dy, COUNT(*) AS cnt
    FROM   public.link_clicks lc
    WHERE  lc.ref_code IN (SELECT mc.rc FROM managed_codes mc)
      AND  lc.clicked_at >= CURRENT_DATE - p_days
    GROUP  BY lc.clicked_at::date
  )
  SELECT
    ds.dy               AS day,
    COALESCE(dc.cnt, 0) AS clicks,
    0::BIGINT           AS ref_count
  FROM date_series ds
  LEFT JOIN daily_clicks dc ON dc.dy = ds.dy
  ORDER BY ds.dy;
END;
$$;
GRANT EXECUTE ON FUNCTION get_daily_stats TO authenticated;


-- get_recent_referrals(p_ref_code, p_limit)
-- Returns per-link signup totals for managed links, ordered by count desc.
-- Since the referrals table stores aggregates (no per-event timestamps),
-- this shows current totals rather than individual events.
DROP FUNCTION IF EXISTS get_recent_referrals(TEXT, INTEGER);
CREATE FUNCTION get_recent_referrals(
  p_ref_code TEXT    DEFAULT NULL,
  p_limit    INTEGER DEFAULT 100
)
RETURNS TABLE (
  id           UUID,
  ref_code     TEXT,
  link_name    TEXT,
  signup_count BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    rl.id,
    rl.ref_code,
    rl.name                              AS link_name,
    COALESCE(rv."count"::BIGINT, 0)      AS signup_count
  FROM public.referral_links rl
  LEFT JOIN public.referrals rv ON rv.username = rl.ref_code
  WHERE p_ref_code IS NULL OR rl.ref_code = p_ref_code
  ORDER BY COALESCE(rv."count", 0) DESC
  LIMIT p_limit;
END;
$$;
GRANT EXECUTE ON FUNCTION get_recent_referrals TO authenticated;


-- record_referral(p_username)
-- Atomically increments the signup count in the referrals table.
-- Called by the helloneural.ai snippet when someone submits their email.
-- Granted to anon so the snippet can fire without authentication.
DROP FUNCTION IF EXISTS record_referral(TEXT);
CREATE FUNCTION record_referral(p_username TEXT)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.referrals (username, "count")
  VALUES (p_username, 1)
  ON CONFLICT (username) DO UPDATE
    SET "count" = public.referrals."count" + 1;
END;
$$;
GRANT EXECUTE ON FUNCTION record_referral TO anon;


-- ================================================================
-- DONE
-- ================================================================
-- Next steps:
--   1. Fill in config.js with your Supabase URL and anon key
--   2. Create your login account:
--      Authentication → Users → Add user (set email + password)
--   3. Run auto_create_link.sql to set up the auto-link trigger
--   4. Upload all files to Bluehost and sign in
--   5. In Settings, copy the helloneural.ai snippet and deploy it
-- ================================================================
