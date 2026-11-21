// ⚠️ এই file এ তোমার actual credentials দাও
// Supabase Dashboard → Settings → API → Publishable key

class SupabaseConfig {
  // Project URL (Settings → API → Project URL)
  static const String supabaseUrl = 'https://dpkkpzodslzlihgtuvfw.supabase.co';

  // Publishable key (Settings → API → Publishable key, starts with 'sb_publishable_')
  static const String publishableKey = 'sb_publishable_x12c49odVJHUan3yAQR1KA_GfqAp1rc';

  // Offline sync retry interval
  static const Duration syncRetryInterval = Duration(minutes: 5);

  // Registration retry attempts
  static const int registrationRetryAttempts = 5;

  // Fallback config (used when offline & never fetched from server)
  static const Map<String, String> fallbackConfig = {
    'code_expiry_minutes': '30',
    'emergency_unlock_minutes': '60',
    'youtube_warning_interval_minutes': '5',
    'youtube_hp_damage_interval_minutes': '30',
    'youtube_hp_damage_base_percent': '5',
    'min_app_version': '1.0.0',
  };

  // Fallback whitelist (used when offline)
  static const List<Map<String, String>> fallbackWhitelist = [
    {'package_name': 'com.bKash.customerapp', 'app_name': 'bKash', 'category': 'allowed'},
    {'package_name': 'com.konasl.nagad', 'app_name': 'Nagad', 'category': 'allowed'},
    {'package_name': 'com.dbbl.mfs', 'app_name': 'Rocket', 'category': 'allowed'},
    {'package_name': 'com.whatsapp', 'app_name': 'WhatsApp', 'category': 'allowed'},
    {'package_name': 'com.android.dialer', 'app_name': 'Phone', 'category': 'allowed'},
    {'package_name': 'com.android.mms', 'app_name': 'SMS', 'category': 'allowed'},
    {'package_name': 'com.google.android.apps.maps', 'app_name': 'Google Maps', 'category': 'allowed'},
    {'package_name': 'com.android.settings', 'app_name': 'Settings', 'category': 'allowed'},
    {'package_name': 'com.google.android.gms', 'app_name': 'Google Play Services', 'category': 'allowed'},
    {'package_name': 'com.google.android.youtube', 'app_name': 'YouTube', 'category': 'youtube_special'},
  ];
}