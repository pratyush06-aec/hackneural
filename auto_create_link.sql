-- ================================================================
-- Auto-create a referral_links row when an unknown username
-- is first seen in an incoming referral.
--
-- Run this in: Supabase dashboard → SQL Editor → New query
--
-- What it does:
--   Before any INSERT into the referrals table, if the username
--   does not already exist in referral_links.ref_code, it creates
--   one automatically — using the username itself as the initial name.
--   You can rename it to something human-friendly in the dashboard.
-- ================================================================

CREATE OR REPLACE FUNCTION auto_create_referral_link()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.referral_links (name, ref_code, description)
  VALUES (NEW.username, NEW.username, '')
  ON CONFLICT (ref_code) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_create_referral_link ON referrals;
CREATE TRIGGER trg_auto_create_referral_link
  BEFORE INSERT ON referrals
  FOR EACH ROW
  EXECUTE FUNCTION auto_create_referral_link();
