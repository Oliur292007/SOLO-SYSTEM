-- Restrict direct client access to internal bot messages and read-only whitelist data.
-- The Flutter client only reads whitelist rows; bot message processing uses service_role.
REVOKE ALL PRIVILEGES ON TABLE public.whatsapp_bot_messages
  FROM anon, authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.whitelist
  FROM anon, authenticated;

-- The app uses the anon role for filtered public configuration.
-- Signed-in Supabase users are not part of this app's authentication model.
REVOKE EXECUTE ON FUNCTION public.get_config() FROM authenticated;

-- Cover both foreign keys on uninstall_requests to avoid table scans during FK checks.
CREATE INDEX IF NOT EXISTS idx_uninstall_requests_uid
  ON public.uninstall_requests (uid);

CREATE INDEX IF NOT EXISTS idx_uninstall_requests_code_id
  ON public.uninstall_requests (code_id);
