import { SongDetail } from "@/types";

export interface LyricsResult {
  id: number | null;
  plainLyrics: string;
  syncedLyrics: string;
  sourceName: string;
}

const clean = (value: string | null | undefined) => value?.trim() || "";

const artistNameForSong = (song: SongDetail) => {
  if (song.artist?.trim()) {
    return song.artist.trim();
  }

  const primaryArtists = Array.isArray(song.artists?.primary)
    ? song.artists.primary
        .map((artist) => artist.name || "")
        .filter(Boolean)
        .join(", ")
    : "";

  return primaryArtists.trim();
};

const buildLyricsSearchUrl = (song: SongDetail) => {
  const params = new URLSearchParams();
  params.set("track_name", clean(song.title || song.name));

  const artistName = artistNameForSong(song);
  if (artistName) {
    params.set("artist_name", artistName);
  }

  const albumName = clean(song.albumName || song.album?.name || "");
  if (albumName) {
    params.set("album_name", albumName);
  }

  return `https://lrclib.net/api/search?${params.toString()}`;
};

const scoreLyricsCandidate = (song: SongDetail, candidate: Record<string, unknown>) => {
  const title = clean(song.title || song.name).toLowerCase();
  const artistName = artistNameForSong(song).toLowerCase();
  const albumName = clean(song.albumName || song.album?.name || "").toLowerCase();

  let score = 0;
  if (`${candidate.trackName ?? ""}`.toLowerCase() === title) {
    score += 6;
  }
  if (`${candidate.artistName ?? ""}`.toLowerCase().includes(artistName) && artistName) {
    score += 4;
  }
  if (`${candidate.albumName ?? ""}`.toLowerCase() === albumName && albumName) {
    score += 2;
  }
  if (candidate.syncedLyrics) {
    score += 1;
  }
  if (candidate.plainLyrics) {
    score += 1;
  }
  return score;
};

export const fetchLyricsForSong = async (song: SongDetail): Promise<LyricsResult | null> => {
  try {
    const response = await fetch(buildLyricsSearchUrl(song), {
      headers: {
        Accept: "application/json",
      },
      next: { revalidate: 3600 },
    });

    if (!response.ok) {
      return null;
    }

    const payload = (await response.json()) as Array<Record<string, unknown>>;
    if (!Array.isArray(payload) || payload.length === 0) {
      return null;
    }

    const bestCandidate = [...payload].sort(
      (left, right) => scoreLyricsCandidate(song, right) - scoreLyricsCandidate(song, left),
    )[0];

    if (!bestCandidate) {
      return null;
    }

    return {
      id: typeof bestCandidate.id === "number" ? bestCandidate.id : null,
      plainLyrics: clean(`${bestCandidate.plainLyrics ?? ""}`),
      syncedLyrics: clean(`${bestCandidate.syncedLyrics ?? ""}`),
      sourceName: "LRCLIB",
    };
  } catch {
    return null;
  }
};
