const trimTrailingSlash = (value: string) => value.replace(/\/+$/, "");

const publicEnv = {
  appName: process.env.NEXT_PUBLIC_APP_NAME?.trim() || "Svara",
  siteName: process.env.NEXT_PUBLIC_SITE_NAME?.trim() || "Svara Web",
  siteUrl:
    trimTrailingSlash(process.env.NEXT_PUBLIC_SITE_URL?.trim() || "http://localhost:3000"),
  apiBaseUrl:
    trimTrailingSlash(
      process.env.NEXT_PUBLIC_API_BASE_URL?.trim() || "https://rf-snowy.vercel.app",
    ),
  appDeepLinkScheme:
    process.env.NEXT_PUBLIC_APP_DEEP_LINK_SCHEME?.trim() || "svara",
  androidPackage:
    process.env.NEXT_PUBLIC_ANDROID_PACKAGE?.trim() || "com.codewithevilxd.svara",
  androidReleaseUrl:
    process.env.NEXT_PUBLIC_ANDROID_RELEASE_URL?.trim() ||
    "https://github.com/CodewithEvilxd/Svara/releases/latest",
  githubUrl:
    process.env.NEXT_PUBLIC_GITHUB_URL?.trim() ||
    "https://github.com/CodewithEvilxd/Svara",
  githubProfileUrl:
    process.env.NEXT_PUBLIC_GITHUB_PROFILE_URL?.trim() ||
    "https://github.com/codewithevilxd",
  portfolioUrl:
    process.env.NEXT_PUBLIC_PORTFOLIO_URL?.trim() || "https://nishantdev.space",
  email: process.env.NEXT_PUBLIC_EMAIL?.trim() || "codewithevilxd@gmail.com",
  emailUrl:
    process.env.NEXT_PUBLIC_EMAIL_URL?.trim() || "mailto:codewithevilxd@gmail.com",
  supabaseUrl:
    process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() ||
    "https://uawdefbniizntkabzrpu.supabase.co",
  supabaseAnonKey:
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim() ||
    "sb_publishable_R1RbUieuVKeUcPPYaF8_JQ_trBDSlIY",
  defaultLanguage:
    process.env.NEXT_PUBLIC_DEFAULT_LANGUAGE?.trim().toLowerCase() || "hindi",
  jamPath: process.env.NEXT_PUBLIC_JAM_PATH?.trim() || "/jam",
  jamInviteQueryParam:
    process.env.NEXT_PUBLIC_JAM_INVITE_QUERY_PARAM?.trim() || "svaraJam",
};

export const siteConfig = publicEnv;

export const buildAbsoluteSiteUrl = (path: string) => {
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  return `${siteConfig.siteUrl}${normalizedPath}`;
};
