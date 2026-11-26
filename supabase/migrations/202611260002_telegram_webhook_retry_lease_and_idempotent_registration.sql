-- Retry-safe Telegram webhook processing and idempotent first-time registration.
-- The bot's service-role backend is the only caller of register_telegram_user.

ALTER TABLE public.telegram_bot_messages
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz;

-- Existing processing rows predate the lease field. Preserve their original
-- creation time as the first known processing start so stale work can recover.
UPDATE public.telegram_bot_messages
   SET processing_started_at = created_at
 WHERE status = 'processing'
   AND processing_started_at IS NULL;

CREATE OR REPLACE FUNCTION public.register_telegram_user(
  p_uid text,
  p_phone text,
  p_telegram_user_id bigint,
  p_telegram_username text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  p_uid := upper(btrim(p_uid));

  -- A previous request may have committed even if the bot timed out before
  -- receiving the response. Treat the exact same identity tuple as success.
  IF EXISTS (
    SELECT 1
      FROM public.users AS u
     WHERE u.uid = p_uid
       AND u.whatsapp_number = p_phone
       AND u.status = 'active'
  ) AND EXISTS (
    SELECT 1
      FROM public.telegram_links AS l
     WHERE l.uid = p_uid
       AND l.telegram_user_id = p_telegram_user_id
  ) THEN
    RETURN jsonb_build_object('status', 'registered', 'uid', p_uid);
  END IF;

  IF EXISTS (SELECT 1 FROM public.users WHERE uid = p_uid) THEN
    RETURN jsonb_build_object('status', 'uid_exists');
  END IF;

  IF EXISTS (SELECT 1 FROM public.users WHERE whatsapp_number = p_phone) THEN
    RETURN jsonb_build_object('status', 'phone_exists');
  END IF;

  IF EXISTS (SELECT 1 FROM public.telegram_links WHERE telegram_user_id = p_telegram_user_id) THEN
    RETURN jsonb_build_object('status', 'telegram_exists');
  END IF;

  INSERT INTO public.users (uid, device_id, player_name, status, whatsapp_number)
  VALUES (p_uid, NULL, 'Shadow Hunter', 'active', p_phone);

  INSERT INTO public.telegram_links (uid, telegram_user_id, telegram_username)
  VALUES (p_uid, p_telegram_user_id, p_telegram_username);

  RETURN jsonb_build_object('status', 'registered', 'uid', p_uid);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('status', 'already_exists');
END;
$$;

REVOKE ALL ON FUNCTION public.register_telegram_user(text, text, bigint, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_telegram_user(text, text, bigint, text)
  TO service_role;
