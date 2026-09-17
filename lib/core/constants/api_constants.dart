class ApiConstants {
  // Project URL is not a secret. The anon key MUST be injected at build time
  // (--dart-define=SUPABASE_ANON_KEY=...) and must never be hardcoded here.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vvoenmdzavyzlisykhks.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Cloud API Endpoint (NestJS Backend)
  static const String cloudBaseUrl = "https://api.nexawavepass.com";

  // Default MikroTik local router gateway address
  static const String defaultRouterGateway = "http://192.168.88.1";
  static const String routerResourcePath = "/rest/system/resource";
  static const String routerIdentityPath = "/rest/system/identity";
  static const String routerHotspotUserPath = "/rest/ip/hotspot/user";
}
