-- Harden exposed device-bound SECURITY DEFINER RPCs and revoke credentials on Telegram unlink.
-- Applied to Supabase project SOLO-SYSTEM as migration 20261125150516.

ALTER FUNCTION public.claim_progress_device(text, text)
  SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.restore_player_progress(text, text)
  SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.save_player_progress(text, text, jsonb, integer)
  SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.validate_code(text, text, text, text)
  SET search_path = pg_catalog, public, pg_temp;

-- The obsolete three-argument overload has no device-token validation.
-- The current Flutter client calls only the four-argument version.
DROP FUNCTION IF EXISTS public.validate_code(text, text, text);

CREATE OR REPLACE FUNCTION public.revoke_progress_device_tokens_on_telegram_unlink()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
  UPDATE public.progress_device_tokens AS t
  SET revoked_at = COALESCE(t.revoked_at, pg_catalog.now()),
      pairing_token = NULL,
      pairing_expires_at = NULL,
      device_token = NULL
  WHERE t.uid = OLD.uid
    AND t.telegram_user_id = OLD.telegram_user_id
    AND t.revoked_at IS NULL;

  RETURN OLD;
END;
$function$;

REVOKE ALL ON FUNCTION public.revoke_progress_device_tokens_on_telegram_unlink()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS revoke_progress_tokens_after_telegram_unlink
  ON public.telegram_links;

CREATE TRIGGER revoke_progress_tokens_after_telegram_unlink
AFTER DELETE OR UPDATE OF uid, telegram_user_id
ON public.telegram_links
FOR EACH ROW
EXECUTE FUNCTION public.revoke_progress_device_tokens_on_telegram_unlink();
