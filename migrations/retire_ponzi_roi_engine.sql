-- =============================================================================
-- Migration: retire_ponzi_roi_engine
--
-- 1. Re-point admin_trigger_roi_payout() at the HONEST engine
--    (process_daily_income_payout: rent-funded, solvency-gated). Same button.
-- 2. Permanently retire the Ponzi ROI functions + their logged wrappers
--    (formula: tokens * token_price * daily_roi_percent). Bodies replaced with
--    a hard RAISE so no path, cron, RPC, or future code can ever run them.
-- 3. Revoke their PUBLIC/anon/authenticated EXECUTE grants (they were live
--    PostgREST RPC endpoints).
--
-- NOT touched: daily_roi_percent column (still read by display code/views), and
-- the honest engine process_daily_income_payout / _logged (unchanged).
-- =============================================================================

BEGIN;

-- 1. Admin "trigger payout" button -> honest engine. Role gate unchanged.
CREATE OR REPLACE FUNCTION public.admin_trigger_roi_payout()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Only admins can trigger manual payouts
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = (SELECT auth.uid()) AND role IN ('admin','super_admin')
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- HONEST engine (was: run_daily_roi_payouts). Rent-funded, solvency-gated.
  RETURN public.process_daily_income_payout();
END;
$function$;

-- 2. Tombstone the Ponzi engine + logged wrappers.
CREATE OR REPLACE FUNCTION public.run_daily_roi_payouts()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'retired: use process_daily_income_payout (run_daily_roi_payouts was the Ponzi engine and is permanently disabled)';
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_daily_roi(p_payout_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'retired: use process_daily_income_payout (process_daily_roi was the Ponzi engine and is permanently disabled)';
END;
$function$;

CREATE OR REPLACE FUNCTION public.run_daily_roi_payouts_logged()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'retired: use process_daily_income_payout_logged (Ponzi wrapper permanently disabled)';
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_daily_roi_logged()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'retired: use process_daily_income_payout_logged (Ponzi wrapper permanently disabled)';
END;
$function$;

-- 3. Close the RPC surface: these were EXECUTE-granted to PUBLIC/anon/authenticated.
REVOKE EXECUTE ON FUNCTION public.run_daily_roi_payouts()        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_daily_roi(date)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.run_daily_roi_payouts_logged() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_daily_roi_logged()     FROM PUBLIC, anon, authenticated;

COMMIT;
