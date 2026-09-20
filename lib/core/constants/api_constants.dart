class ApiConstants {
  // Public project URL and public anon publishable key (client key protected by RLS).
  // Overridable at build time via --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vvoenmdzavyzlisykhks.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_Lyp5cAFr5o0gSSvKEtp3QQ_4p0nPEKR',
  );

  // Cloud API Endpoint (NestJS Backend)
  static const String cloudBaseUrl = "https://api.nexawavepass.com";

  // Default MikroTik local router gateway address
  static const String defaultRouterGateway = "http://192.168.88.1";
  static const String routerResourcePath = "/rest/system/resource";
  static const String routerIdentityPath = "/rest/system/identity";
  static const String routerHotspotUserPath = "/rest/ip/hotspot/user";
}
