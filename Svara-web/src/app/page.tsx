import { cookies } from "next/headers";

import MainContent from "@/components/MainContent";
import { siteConfig } from "@/config/site";
import { LatestSaavnFetcher, SaavnAPI } from "@/services/api";
import { Album, Artist, Playlist } from "@/types";

function uniqueById<T extends { id: string }>(items: T[]) {
  const seen = new Set<string>();
  return items.filter((item) => {
    if (!item?.id || seen.has(item.id)) {
      return false;
    }
    seen.add(item.id);
    return true;
  });
}

function safeResults<T>(value: { results?: T[] } | null | undefined) {
  return value?.results || [];
}

export default async function Home() {
  const cookieStore = await cookies();
  const preferredLanguage =
    cookieStore.get("music-language")?.value?.toLowerCase() || siteConfig.defaultLanguage;
  const fallbackLanguages = Array.from(
    new Set([preferredLanguage, siteConfig.defaultLanguage, "hindi", "english"]),
  );

  const [
    languagePlaylists,
    languageAlbums,
    hindiPlaylists,
    englishPlaylists,
    bollywoodTrendingResponse,
    globalTrendingResponse,
    regionalHeatResponse,
    nightDriveResponse,
    romanceResponse,
    indianArtistsResponse,
    globalArtistsResponse,
  ] = await Promise.all([
    LatestSaavnFetcher.getLatestPlaylists(fallbackLanguages[0], 18, 40).catch(() => []),
    LatestSaavnFetcher.getLatestAlbums(fallbackLanguages[0], 16, 40).catch(() => []),
    LatestSaavnFetcher.getLatestPlaylists("hindi", 16, 40).catch(() => []),
    LatestSaavnFetcher.getLatestPlaylists("english", 16, 40).catch(() => []),
    SaavnAPI.searchPlaylists("bollywood trending hits", 0, 14).catch(() => null),
    SaavnAPI.searchPlaylists("global trending hits", 0, 14).catch(() => null),
    SaavnAPI.searchPlaylists(`${preferredLanguage} trending`, 0, 14).catch(() => null),
    SaavnAPI.searchPlaylists("night drive hits", 0, 14).catch(() => null),
    SaavnAPI.searchPlaylists("romantic hits", 0, 14).catch(() => null),
    SaavnAPI.searchArtists("top bollywood artists", 0, 10).catch(() => null),
    SaavnAPI.searchArtists("global pop artists", 0, 10).catch(() => null),
  ]);

  const featuredCards = uniqueById<Playlist>([
    ...languagePlaylists.slice(0, 3),
    ...safeResults<Playlist>(bollywoodTrendingResponse).slice(0, 3),
    ...safeResults<Playlist>(globalTrendingResponse).slice(0, 2),
  ]).slice(0, 8);

  const madeForYou = uniqueById<Playlist>([
    ...languagePlaylists,
    ...hindiPlaylists,
  ]).slice(0, 14);

  const bollywoodTrending = uniqueById<Playlist>([
    ...safeResults<Playlist>(bollywoodTrendingResponse),
    ...hindiPlaylists,
  ]).slice(0, 14);

  const globalCharts = uniqueById<Playlist>([
    ...safeResults<Playlist>(globalTrendingResponse),
    ...englishPlaylists,
  ]).slice(0, 14);

  const regionalHeat = uniqueById<Playlist>([
    ...safeResults<Playlist>(regionalHeatResponse),
    ...languagePlaylists.slice(0, 10),
  ]).slice(0, 14);

  const nightDrive = uniqueById<Playlist>([
    ...safeResults<Playlist>(nightDriveResponse),
    ...safeResults<Playlist>(romanceResponse),
  ]).slice(0, 14);

  const romanceMix = uniqueById<Playlist>([
    ...safeResults<Playlist>(romanceResponse),
    ...hindiPlaylists.slice(0, 10),
  ]).slice(0, 14);

  const freshReleases = uniqueById<Album>(languageAlbums).slice(0, 14);
  const artists = uniqueById<Artist>([
    ...safeResults<Artist>(indianArtistsResponse),
    ...safeResults<Artist>(globalArtistsResponse),
  ]).slice(0, 14);

  return (
    <MainContent
      featuredCards={featuredCards}
      madeForYou={madeForYou}
      bollywoodTrending={bollywoodTrending}
      globalCharts={globalCharts}
      regionalHeat={regionalHeat}
      nightDrive={nightDrive}
      romanceMix={romanceMix}
      freshReleases={freshReleases}
      artists={artists}
      preferredLanguage={preferredLanguage}
    />
  );
}
