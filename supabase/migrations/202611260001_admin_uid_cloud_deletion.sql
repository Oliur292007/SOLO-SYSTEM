-- Permanently remove every cloud record associated with one SOLO SYSTEM UID.
-- This privileged RPC is intended for the Telegram bot using the Supabase service-role key.
-- Shared configuration and whitelist tables are deliberately excluded.

CREATE OR REPLACE FUNCTION public.admin_delete_uid_cloud_data(p_uid text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_phone text;
    v_telegram_id bigint;
    v_count bigint;
    v_deleted jsonb := '{}'::jsonb;
    v_total bigint := 0;
BEGIN
    IF p_uid IS NULL OR p_uid !~* '^SOLO-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$' THEN
        RAISE EXCEPTION 'Invalid UID';
    END IF;

    SELECT u.whatsapp_number
      INTO v_phone
      FROM public.users AS u
     WHERE u.uid = upper(p_uid)
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'not_found', 'uid', upper(p_uid));
    END IF;

    SELECT l.telegram_user_id
      INTO v_telegram_id
      FROM public.telegram_links AS l
     WHERE l.uid = upper(p_uid)
     LIMIT 1;

    DELETE FROM public.telegram_pending_actions
     WHERE uid = upper(p_uid)
        OR (v_telegram_id IS NOT NULL AND telegram_user_id = v_telegram_id)
        OR (v_phone IS NOT NULL AND regexp_replace(COALESCE(phone_number, ''), '[^0-9]', '', 'g')
                                  = regexp_replace(v_phone, '[^0-9]', '', 'g'));
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('telegram_pending_actions', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.telegram_bot_messages
     WHERE (v_telegram_id IS NOT NULL AND
           (telegram_user_id = v_telegram_id OR chat_id = v_telegram_id));
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('telegram_bot_messages', v_count);
    v_total := v_total + v_count;

    IF v_phone IS NOT NULL THEN
        DELETE FROM public.whatsapp_bot_messages
         WHERE regexp_replace(sender_number, '[^0-9]', '', 'g')
             = regexp_replace(v_phone, '[^0-9]', '', 'g');
        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_deleted := v_deleted || jsonb_build_object('whatsapp_bot_messages', v_count);
        v_total := v_total + v_count;
    END IF;

    DELETE FROM public.uninstall_requests WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('uninstall_requests', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.code_requests WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('code_requests', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.codes WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('codes', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.progress_device_tokens WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('progress_device_tokens', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.player_progress WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('player_progress', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.telegram_link_tokens WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('telegram_link_tokens', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.telegram_links WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('telegram_links', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.audit_log
     WHERE uid = upper(p_uid)
        OR metadata ->> 'uid' = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('audit_log', v_count);
    v_total := v_total + v_count;

    DELETE FROM public.users WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('users', v_count);
    v_total := v_total + v_count;

    -- Remove any audit entry created by a delete trigger during the transaction.
    DELETE FROM public.audit_log WHERE uid = upper(p_uid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_deleted := jsonb_set(
        v_deleted,
        '{audit_log}',
        to_jsonb(COALESCE((v_deleted->>'audit_log')::bigint, 0) + v_count),
        true
    );
    v_total := v_total + v_count;

    RETURN jsonb_build_object(
        'status', 'deleted',
        'uid', upper(p_uid),
        'deleted_count', v_total,
        'deleted', v_deleted
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_uid_cloud_data(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_delete_uid_cloud_data(text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_uid_cloud_data(text) TO service_role;
