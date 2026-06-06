-- ================================================================
-- FIX: Re-apply helper functions to match the referrals table schema
--
-- Run this in Supabase → SQL Editor → New query if you need to
-- re-apply just the functions without re-running the full setup.sql.
--
-- Schema: referrals table has columns "username" (ref code) and
-- "count" (total signups). referral_links.ref_code maps to username.
-- ================================================================


-- ── get_link_stats ─────────────────────────────────────────────────
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


-- ── get_daily_stats ────────────────────────────────────────────────
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


-- ── get_recent_referrals ───────────────────────────────────────────
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


-- ── record_referral ────────────────────────────────────────────────
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
