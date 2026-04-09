"use client";

import Link from "next/link";
import { useMemo, useRef, useState } from "react";

import SongList from "@/components/SongList";
import { buildAbsoluteSiteUrl } from "@/config/site";
import { decodeHtml } from "@/services/api";
import { LyricsResult } from "@/services/lyrics";
import { SongDetail, ArtistDetails } from "@/types";
import { usePlayerStore } from "@/store/playerStore";
import { getSaavnImageUrl } from "@/utils/image";

interface SongDetailViewProps {
  song: SongDetail;
  artistDetails: ArtistDetails | null;
  relatedSongs: SongDetail[];
  lyrics: LyricsResult | null;
}

const imageForSong = (song: SongDetail) => {
  if (Array.isArray(song.images) && song.images.length > 0) {
    return song.images[song.images.length - 1].url || song.images[0].url;
  }

  if (Array.isArray(song.image) && song.image.length > 0) {
    return song.image[song.image.length - 1].url || song.image[0].url;
  }

  return "/assets/icons/logo.png";
};

const artistNameForSong = (song: SongDetail) =>
  decodeHtml(
    song.artist ||
      song.artists?.primary?.map((artist) => artist.name).join(", ") ||
      "Unknown Artist",
  );

const formatDuration = (duration: number | null | undefined) => {
  if (!duration || Number.isNaN(duration)) {
    return "0:00";
  }
  const minutes = Math.floor(duration / 60);
  const seconds = Math.floor(duration % 60);
  return `${minutes}:${`${seconds}`.padStart(2, "0")}`;
};

export default function SongDetailView({
  song,
  artistDetails,
  relatedSongs,
  lyrics,
}: SongDetailViewProps) {
  const { playSong } = usePlayerStore();
  const [shareMessage, setShareMessage] = useState("");
  const shareInProgressRef = useRef(false);

  const queue = useMemo(() => {
    const deduped = new Map<string, SongDetail>();
    [song, ...relatedSongs].forEach((entry) => {
      if (entry?.id && !deduped.has(entry.id)) {
        deduped.set(entry.id, entry);
      }
    });
    return Array.from(deduped.values());
  }, [relatedSongs, song]);

  const primaryArtist = song.artists?.primary?.[0];
  const songUrl = buildAbsoluteSiteUrl(`/song/${song.id}`);

  const handleShare = async () => {
    const shareText = [
      `Listen on Svara: ${decodeHtml(song.title || song.name || "Unknown Track")}`,
      artistNameForSong(song),
      songUrl,
    ].join("\n");

    if (shareInProgressRef.current) {
      return;
    }

    shareInProgressRef.current = true;

    try {
      if (navigator.share) {
        await navigator.share({
          title: decodeHtml(song.title || song.name || "Svara track"),
          text: shareText,
          url: songUrl,
        });
        return;
      }

      await navigator.clipboard.writeText(shareText);
      setShareMessage("Track link copied");
      window.setTimeout(() => setShareMessage(""), 1800);
    } catch (error) {
      const domError = error as DOMException;
      if (domError?.name === "AbortError") {
        return;
      }

      if (domError?.name === "InvalidStateError") {
        await navigator.clipboard.writeText(shareText);
        setShareMessage("Track link copied");
        window.setTimeout(() => setShareMessage(""), 1800);
        return;
      }

      console.error("Song detail share failed", error);
    } finally {
      shareInProgressRef.current = false;
    }
  };

  return (
    <div className="min-h-full px-4 md:px-8 pb-32">
      <div className="relative overflow-hidden rounded-[28px] border border-white/5 bg-gradient-to-br from-[#151515] via-[#0f0f0f] to-[#102618] px-6 py-8 md:px-10 md:py-12 shadow-[0_24px_80px_rgba(0,0,0,0.45)]">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(30,215,96,0.18),transparent_35%)]" />
        <div className="relative flex flex-col gap-8 md:flex-row md:items-end">
          <div className="h-44 w-44 overflow-hidden rounded-[22px] border border-white/10 shadow-[0_18px_44px_rgba(0,0,0,0.55)] md:h-56 md:w-56">
            <img
              src={getSaavnImageUrl(imageForSong(song), 500)}
              alt={song.title || song.name || "Song cover"}
              className="h-full w-full object-cover"
            />
          </div>
          <div className="flex max-w-4xl flex-1 flex-col gap-3">
            <span className="text-xs font-bold uppercase tracking-[0.24em] text-primary">
              Track Page
            </span>
            <h1 className="text-4xl font-black tracking-tight text-white md:text-6xl">
              {decodeHtml(song.title || song.name || "Unknown Track")}
            </h1>
            <div className="flex flex-wrap items-center gap-3 text-sm text-white/75">
              <span>{artistNameForSong(song)}</span>
              <span>{song.albumName || song.album?.name || "Single"}</span>
              <span>{formatDuration(song.duration)}</span>
              {song.year ? <span>{song.year}</span> : null}
            </div>
            <div className="flex flex-wrap gap-3 pt-2">
              <button
                onClick={() => playSong(song, queue)}
                className="rounded-full bg-primary px-5 py-3 text-sm font-bold text-black transition hover:scale-[1.02]"
              >
                Play now
              </button>
              <button
                onClick={handleShare}
                className="rounded-full border border-white/12 px-5 py-3 text-sm font-bold text-white transition hover:bg-white/[0.06]"
              >
                Share track
              </button>
              {primaryArtist?.id ? (
                <Link
                  href={`/artist/${primaryArtist.id}`}
                  className="rounded-full border border-white/12 px-5 py-3 text-sm font-bold text-white transition hover:bg-white/[0.06]"
                >
                  Open artist
                </Link>
              ) : null}
              {song.album?.id ? (
                <Link
                  href={`/album/${song.album.id}`}
                  className="rounded-full border border-white/12 px-5 py-3 text-sm font-bold text-white transition hover:bg-white/[0.06]"
                >
                  Open album
                </Link>
              ) : null}
            </div>
          </div>
        </div>
      </div>

      {shareMessage ? (
        <div className="mt-4 inline-flex rounded-full bg-primary px-4 py-2 text-sm font-bold text-black">
          {shareMessage}
        </div>
      ) : null}

      <div className="mt-10 grid gap-8 xl:grid-cols-[1.4fr_0.9fr]">
        <div className="space-y-8">
          {queue.length > 0 ? (
            <section>
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-2xl font-bold text-white">Queue from this vibe</h2>
                <span className="text-sm text-white/55">Starts with the track you shared</span>
              </div>
              <SongList songs={queue} />
            </section>
          ) : null}

          {artistDetails?.topSongs && artistDetails.topSongs.length > 0 ? (
            <section>
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-2xl font-bold text-white">More from {artistDetails.name}</h2>
                {primaryArtist?.id ? (
                  <Link href={`/artist/${primaryArtist.id}`} className="text-sm font-semibold text-primary">
                    Open artist page
                  </Link>
                ) : null}
              </div>
              <SongList songs={artistDetails.topSongs.slice(0, 10)} />
            </section>
          ) : null}
        </div>

        <div className="space-y-8">
          {lyrics?.plainLyrics || lyrics?.syncedLyrics ? (
            <section className="rounded-[24px] border border-white/5 bg-white/[0.03] p-6">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-2xl font-bold text-white">Lyrics</h2>
                <span className="text-xs font-semibold uppercase tracking-[0.22em] text-white/45">
                  {lyrics?.sourceName || "Source"}
                </span>
              </div>
              <pre className="max-h-[620px] overflow-auto whitespace-pre-wrap text-sm leading-7 text-white/78">
                {lyrics?.plainLyrics || lyrics?.syncedLyrics}
              </pre>
            </section>
          ) : null}

          {artistDetails ? (
            <section className="rounded-[24px] border border-white/5 bg-white/[0.03] p-6">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-2xl font-bold text-white">Artist snapshot</h2>
                {primaryArtist?.id ? (
                  <Link href={`/artist/${primaryArtist.id}`} className="text-sm font-semibold text-primary">
                    Full page
                  </Link>
                ) : null}
              </div>
              <div className="flex items-center gap-4">
                <div className="h-16 w-16 overflow-hidden rounded-full border border-white/10">
                  <img
                    src={getSaavnImageUrl(
                      Array.isArray(artistDetails.images) && artistDetails.images.length > 0
                        ? artistDetails.images[artistDetails.images.length - 1].url
                        : "/assets/icons/logo.png",
                      150,
                    )}
                    alt={artistDetails.name || "Artist"}
                    className="h-full w-full object-cover"
                  />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="text-lg font-bold text-white">{decodeHtml(artistDetails.name || "Artist")}</div>
                  <div className="text-sm text-white/55">
                    {artistDetails.followerCount
                      ? `${artistDetails.followerCount.toLocaleString("en-US")} followers`
                      : artistDetails.dominantLanguage || "Artist page available"}
                  </div>
                </div>
              </div>
            </section>
          ) : null}
        </div>
      </div>
    </div>
  );
}
