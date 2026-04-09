import Image from "next/image";
import Link from "next/link";

import SongList from "@/components/SongList";
import { SaavnAPI, decodeHtml } from "@/services/api";
import { Artist, Playlist, Album } from "@/types";
import { getSaavnImageUrl } from "@/utils/image";

interface SearchPageProps {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}

const imageForItem = (item: any) => {
  if (Array.isArray(item.images) && item.images.length > 0) {
    return item.images[item.images.length - 1].url || item.images[0].url;
  }
  if (typeof item.image === "string" && item.image) {
    return item.image;
  }
  if (Array.isArray(item.image) && item.image.length > 0) {
    return item.image[item.image.length - 1].url || item.image[0].url;
  }
  return "/assets/icons/logo.png";
};

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

const resultRoute = (type: "song" | "album" | "playlist" | "artist", id: string) => {
  if (type === "song") {
    return `/song/${id}`;
  }
  return `/${type}/${id}`;
};

const ResultGrid = ({
  title,
  type,
  items,
}: {
  title: string;
  type: "album" | "playlist" | "artist";
  items: any[];
}) => (
  <div className="mt-8">
    <h3 className="mb-4 text-xl font-bold text-white">{title}</h3>
    <div className="grid grid-cols-2 gap-6 md:grid-cols-3 lg:grid-cols-5">
      {items.map((item) => (
        <Link key={item.id} href={resultRoute(type, item.id)}>
          <div className="group h-full cursor-pointer rounded-lg bg-[#181818] p-4 transition-colors hover:bg-[#282828]">
            <div
              className={`relative mb-4 aspect-square w-full overflow-hidden shadow-2xl ${
                type === "artist" ? "rounded-full" : "rounded"
              }`}
            >
              <img
                src={getSaavnImageUrl(imageForItem(item), 500)}
                alt={item.title || item.name || title}
                className="h-full w-full object-cover"
                width={180}
                height={180}
                loading="lazy"
                decoding="async"
              />
            </div>
            <div className="mb-1 truncate text-base font-bold text-white">
              {decodeHtml(item.title || item.name || "")}
            </div>
            <div className="truncate text-sm text-[#a7a7a7]">
              {type === "artist" ? "Artist" : decodeHtml(item.artist || item.year || title)}
            </div>
          </div>
        </Link>
      ))}
    </div>
  </div>
);

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const params = await searchParams;
  const rawQuery = params.q;
  const query = typeof rawQuery === "string" ? rawQuery : "";

  if (!query) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center">
        <div className="max-w-[400px] text-center">
          <Image
            src="/assets/icons/search.png"
            alt="Search"
            width={64}
            height={64}
            className="mx-auto mb-6 invert opacity-50 transition-opacity"
          />
          <h2 className="mb-2 text-2xl font-bold text-white">Play what you love</h2>
          <p className="text-base text-[#a7a7a7]">
            Search for artists, songs, albums, playlists, and fast follow-up pages.
          </p>
        </div>
      </div>
    );
  }

  const [globalResults, searchedSongs, searchedArtists] = await Promise.all([
    SaavnAPI.globalSearch(query),
    SaavnAPI.searchSongs(query, 0, 40),
    SaavnAPI.searchArtists(query, 0, 15),
  ]);

  const songs = uniqueById([
    ...(searchedSongs || []),
    ...(globalResults?.songs?.results || []),
  ]);
  const albums = uniqueById<Album>(globalResults?.albums?.results || []);
  const playlists = uniqueById<Playlist>(globalResults?.playlists?.results || []);
  const artists = uniqueById<Artist>([
    ...(searchedArtists?.results || []),
    ...(globalResults?.artists?.results || []),
  ]);
  const topResult =
    songs[0] || artists[0] || albums[0] || playlists[0] || globalResults?.topQuery?.results?.[0] || null;
  const topResultType =
    songs[0] && topResult?.id === songs[0].id
      ? "song"
      : artists[0] && topResult?.id === artists[0].id
        ? "artist"
        : albums[0] && topResult?.id === albums[0].id
          ? "album"
          : "playlist";

  return (
    <div className="flex flex-col gap-8 p-6">
      <div className="mb-2">
        <h2 className="text-2xl font-bold text-white">Results for &quot;{decodeHtml(query)}&quot;</h2>
        <p className="mt-2 text-sm text-white/55">
          Songs, artists, playlists, and album pages all come from the same shared API stack.
        </p>
      </div>

      {topResult ? (
        <Link href={resultRoute(topResultType, topResult.id)} className="max-w-[420px]">
          <div className="rounded-[24px] border border-white/5 bg-gradient-to-br from-[#171717] to-[#0f2f1d] p-5 shadow-[0_18px_48px_rgba(0,0,0,0.45)] transition hover:bg-[#1a1a1a]">
            <div className="mb-4 flex items-center gap-4">
              <div className={`h-20 w-20 overflow-hidden ${topResultType === "artist" ? "rounded-full" : "rounded-2xl"}`}>
                <img
                  src={getSaavnImageUrl(imageForItem(topResult), 500)}
                  alt={topResult.name || topResult.title || "Top result"}
                  className="h-full w-full object-cover"
                />
              </div>
              <div className="min-w-0 flex-1">
                <div className="text-xs font-bold uppercase tracking-[0.22em] text-primary">
                  Top result
                </div>
                <div className="mt-2 line-clamp-2 text-2xl font-black text-white">
                  {decodeHtml(topResult.name || topResult.title || "Untitled")}
                </div>
                <div className="mt-1 text-sm text-white/60">
                  {topResultType === "artist"
                    ? "Artist"
                    : decodeHtml(topResult.artist || topResult.albumName || topResult.year || topResultType)}
                </div>
              </div>
            </div>
          </div>
        </Link>
      ) : null}

      {songs.length > 0 ? (
        <div>
          <h3 className="mb-4 text-xl font-bold text-white">Songs</h3>
          <SongList songs={songs} />
        </div>
      ) : null}

      {artists.length > 0 ? <ResultGrid title="Artists" type="artist" items={artists.slice(0, 10)} /> : null}
      {albums.length > 0 ? <ResultGrid title="Albums" type="album" items={albums.slice(0, 10)} /> : null}
      {playlists.length > 0 ? <ResultGrid title="Playlists" type="playlist" items={playlists.slice(0, 10)} /> : null}

      {songs.length === 0 && albums.length === 0 && playlists.length === 0 && artists.length === 0 ? (
        <div className="py-16 text-center text-white">
          <p className="mb-3 text-xl font-bold">No results found for &quot;{query}&quot;</p>
          <p className="text-base font-normal text-[#a7a7a7]">
            Try a broader query or search with the artist name too.
          </p>
        </div>
      ) : null}
    </div>
  );
}
