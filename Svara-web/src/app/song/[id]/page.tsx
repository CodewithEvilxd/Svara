import SongDetailView from "@/components/SongDetailView";
import { SaavnAPI } from "@/services/api";
import { fetchLyricsForSong } from "@/services/lyrics";
import { SongDetail } from "@/types";

const dedupeSongs = (songs: SongDetail[]) => {
  const seen = new Set<string>();
  return songs.filter((song) => {
    if (!song?.id || seen.has(song.id)) {
      return false;
    }
    seen.add(song.id);
    return true;
  });
};

export default async function SongPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const songDetails = await SaavnAPI.getSongDetails([id]);
  const song = songDetails[0];

  if (!song) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center text-gray-400">
        <div className="text-center">
          <h2 className="mb-2 text-2xl font-bold">Track not found</h2>
          <p>We could not load this track page right now.</p>
        </div>
      </div>
    );
  }

  const primaryArtist = song.artists?.primary?.[0];
  const artistDetails = primaryArtist?.id
    ? await SaavnAPI.fetchArtistDetailsById(primaryArtist.id, 0, 12, 8)
    : null;
  const relatedSongs = dedupeSongs(
    [
      ...(artistDetails?.topSongs || []),
      ...(await SaavnAPI.searchSongs(
        `${song.title || song.name || ""} ${song.artist || primaryArtist?.name || ""}`.trim(),
        0,
        12,
      )),
    ].filter(Boolean),
  ).filter((entry) => entry.id !== song.id);
  const lyrics = await fetchLyricsForSong(song);

  return (
    <SongDetailView
      song={song}
      artistDetails={artistDetails}
      relatedSongs={relatedSongs}
      lyrics={lyrics}
    />
  );
}
