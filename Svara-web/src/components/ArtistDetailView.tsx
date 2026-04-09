"use client";

import Link from "next/link";

import SongList from "@/components/SongList";
import { decodeHtml } from "@/services/api";
import { ArtistDetails, ArtistMini, Album } from "@/types";
import { getSaavnImageUrl } from "@/utils/image";

interface ArtistDetailViewProps {
  artist: ArtistDetails;
}

const artistImage = (artist: ArtistDetails | ArtistMini) => {
  if ("images" in artist && Array.isArray(artist.images) && artist.images.length > 0) {
    return artist.images[artist.images.length - 1].url || artist.images[0].url;
  }

  if (Array.isArray(artist.image) && artist.image.length > 0) {
    return artist.image[artist.image.length - 1].url || artist.image[0].url;
  }

  return "/assets/icons/logo.png";
};

const albumImage = (album: Album) => {
  if (Array.isArray(album.images) && album.images.length > 0) {
    return album.images[album.images.length - 1].url || album.images[0].url;
  }

  if (Array.isArray(album.image) && album.image.length > 0) {
    return album.image[album.image.length - 1].url || album.image[0].url;
  }

  return "/assets/icons/logo.png";
};

export default function ArtistDetailView({ artist }: ArtistDetailViewProps) {
  const topSongs = artist.topSongs || [];
  const topAlbums = artist.topAlbums || artist.singles || [];
  const similarArtists = artist.similarArtists || [];
  const bio =
    artist.bio
      ?.map((entry) => decodeHtml(entry.text || ""))
      .find((entry) => entry.trim().length > 0) || "";

  return (
    <div className="min-h-full px-4 md:px-8 pb-32">
      <div className="relative overflow-hidden rounded-[28px] border border-white/5 bg-gradient-to-br from-[#151515] via-[#101010] to-[#082415] px-6 py-8 md:px-10 md:py-12 shadow-[0_24px_80px_rgba(0,0,0,0.45)]">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(30,215,96,0.2),transparent_35%)]" />
        <div className="relative flex flex-col gap-8 md:flex-row md:items-end">
          <div className="h-40 w-40 overflow-hidden rounded-full border border-white/10 shadow-[0_18px_44px_rgba(0,0,0,0.55)] md:h-52 md:w-52">
            <img
              src={getSaavnImageUrl(artistImage(artist), 500)}
              alt={artist.name || artist.title || "Artist"}
              className="h-full w-full object-cover"
            />
          </div>
          <div className="flex max-w-4xl flex-1 flex-col gap-3">
            <span className="text-xs font-bold uppercase tracking-[0.24em] text-primary">
              Artist Radar
            </span>
            <h1 className="text-4xl font-black tracking-tight text-white md:text-6xl">
              {decodeHtml(artist.name || artist.title || "Unknown Artist")}
            </h1>
            <div className="flex flex-wrap items-center gap-3 text-sm text-white/75">
              {artist.isVerified ? (
                <span className="rounded-full border border-primary/40 bg-primary/10 px-3 py-1 font-semibold text-primary">
                  Verified
                </span>
              ) : null}
              {artist.followerCount ? (
                <span>{artist.followerCount.toLocaleString("en-US")} followers</span>
              ) : null}
              {artist.dominantLanguage ? <span>{decodeHtml(artist.dominantLanguage)}</span> : null}
            </div>
            {bio ? (
              <p className="max-w-3xl text-sm leading-6 text-white/70 md:text-base">{bio}</p>
            ) : null}
          </div>
        </div>
      </div>

      {topSongs.length > 0 ? (
        <section className="mt-10">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-2xl font-bold text-white">Top songs</h2>
            <span className="text-sm text-white/55">Queue starts from the first track</span>
          </div>
          <SongList songs={topSongs} />
        </section>
      ) : null}

      {topAlbums.length > 0 ? (
        <section className="mt-12">
          <div className="mb-5 flex items-center justify-between">
            <h2 className="text-2xl font-bold text-white">Top releases</h2>
            <span className="text-sm text-white/55">Albums and singles connected to this artist</span>
          </div>
          <div className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-5">
            {topAlbums.slice(0, 10).map((album) => (
              <Link
                key={album.id}
                href={`/album/${album.id}`}
                className="group rounded-2xl border border-white/5 bg-white/[0.03] p-3 transition hover:bg-white/[0.06]"
              >
                <div className="aspect-square overflow-hidden rounded-xl shadow-lg">
                  <img
                    src={getSaavnImageUrl(albumImage(album), 500)}
                    alt={album.name || album.title || "Album"}
                    className="h-full w-full object-cover transition duration-500 group-hover:scale-105"
                  />
                </div>
                <div className="mt-3 text-sm font-bold text-white line-clamp-2">
                  {decodeHtml(album.name || album.title || "Untitled release")}
                </div>
                <div className="mt-1 text-xs text-white/55 line-clamp-1">
                  {album.year || album.songCount || "Release"}
                </div>
              </Link>
            ))}
          </div>
        </section>
      ) : null}

      {similarArtists.length > 0 ? (
        <section className="mt-12">
          <div className="mb-5 flex items-center justify-between">
            <h2 className="text-2xl font-bold text-white">Similar artists</h2>
            <span className="text-sm text-white/55">Good next clicks if you like this sound</span>
          </div>
          <div className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-5">
            {similarArtists.slice(0, 10).map((similarArtist) => (
              <Link
                key={similarArtist.id}
                href={`/artist/${similarArtist.id}`}
                className="group rounded-2xl border border-white/5 bg-white/[0.03] p-3 transition hover:bg-white/[0.06]"
              >
                <div className="aspect-square overflow-hidden rounded-full border border-white/10 shadow-lg">
                  <img
                    src={getSaavnImageUrl(artistImage(similarArtist), 500)}
                    alt={similarArtist.name || "Artist"}
                    className="h-full w-full object-cover transition duration-500 group-hover:scale-105"
                  />
                </div>
                <div className="mt-3 text-center text-sm font-bold text-white line-clamp-2">
                  {decodeHtml(similarArtist.name || "Unknown Artist")}
                </div>
                <div className="mt-1 text-center text-xs text-white/55">Artist</div>
              </Link>
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
