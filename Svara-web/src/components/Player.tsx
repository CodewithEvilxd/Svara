"use client";

import React, { useEffect, useRef, useState } from "react";
import Image from "next/image";

import { buildAbsoluteSiteUrl, siteConfig } from "@/config/site";
import { decodeHtml } from "@/services/api";
import { pipService } from "@/services/pipService";
import { buildJamDeepLink, buildJamInviteUrl, jamSyncService } from "@/services/jam";
import { useJamStore } from "@/store/jamStore";
import { useLikesStore } from "@/store/likesStore";
import { usePlayerStore } from "@/store/playerStore";
import { SongDetail, SourceUrl } from "@/types";
import { getSaavnImageUrl } from "@/utils/image";

type ArtistNameRef = {
  name?: string;
  title?: string;
};

type PlayerSongLike = Partial<SongDetail> & {
  primaryArtists?: string | ArtistNameRef[];
  singers?: string | ArtistNameRef[];
  image?: string | SourceUrl[];
};

const Player = () => {
  const {
    currentSong,
    isPlaying,
    togglePlayPause,
    nextSong,
    prevSong,
    isShuffling,
    toggleShuffle,
    repeatMode,
    toggleRepeat,
    currentTime,
    duration,
    volume,
    seek,
    setVolume,
    showQueue,
    setShowQueue,
    queue,
    currentIndex,
  } = usePlayerStore();
  const { toggleLike, isLiked } = useLikesStore();
  const jamState = useJamStore();

  const [isHoveringProgress, setIsHoveringProgress] = useState(false);
  const shareInProgressRef = useRef(false);

  const shareTextSafely = async (input: { title: string; text: string; url: string }) => {
    if (shareInProgressRef.current) {
      return;
    }

    shareInProgressRef.current = true;

    try {
      if (navigator.share) {
        await navigator.share(input);
        return;
      }

      await navigator.clipboard.writeText(input.text);
    } catch (error) {
      const domError = error as DOMException;
      if (domError?.name === "AbortError") {
        return;
      }

      if (domError?.name === "InvalidStateError") {
        await navigator.clipboard.writeText(input.text);
        return;
      }

      console.error("Share failed", error);
    } finally {
      shareInProgressRef.current = false;
    }
  };

  const formatTime = (seconds: number) => {
    if (Number.isNaN(seconds)) {
      return "0:00";
    }
    const minutes = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${minutes}:${secs.toString().padStart(2, "0")}`;
  };

  const getArtistsString = (song?: PlayerSongLike | null) => {
    if (!song) {
      return "";
    }
    if (typeof song.primaryArtists === "string") {
      return song.primaryArtists;
    }
    if (Array.isArray(song.primaryArtists)) {
      const names = song.primaryArtists
        .map((artist) => artist.name || artist.title || "")
        .filter(Boolean);
      if (names.length > 0) {
        return names.join(", ");
      }
    }
    const artistValue = song.artist || song.singers;
    if (typeof artistValue === "string") {
      return artistValue;
    }
    if (Array.isArray(artistValue)) {
      return artistValue.map((artist) => artist.name || artist.title || "").join(", ");
    }
    return "Unknown Artist";
  };

  const getImageUrl = (item?: PlayerSongLike | null) => {
    if (!item) {
      return "/assets/icons/logo.png";
    }
    if (Array.isArray(item.images) && item.images.length > 0) {
      return item.images[item.images.length - 1].url || item.images[0].url;
    }
    if (item.image) {
      if (typeof item.image === "string") {
        return item.image;
      }
      if (Array.isArray(item.image) && item.image.length > 0) {
        return item.image[item.image.length - 1].url || item.image[0].url;
      }
    }
    return "/assets/icons/logo.png";
  };

  const artistsStr = getArtistsString(currentSong);

  useEffect(() => {
    if (isPlaying && currentSong) {
      const songTitle = decodeHtml(currentSong.title || currentSong.name || "Unknown Track");
      const songArtist = decodeHtml(artistsStr);
      document.title = `${songTitle} | ${songArtist} - ${siteConfig.appName}`;
      return;
    }

    document.title = `${siteConfig.siteName} | Search, play, and share music`;
  }, [artistsStr, currentSong, isPlaying]);

  if (!currentSong) {
    return null;
  }

  const highestResImage = getImageUrl(currentSong);
  const shouldRouteJamControl = jamState.isActive && !jamState.isHost;

  const handleJamAwarePlayPause = async () => {
    if (shouldRouteJamControl) {
      await jamSyncService.sendControlRequest(isPlaying ? "pause" : "play", {
        positionMs: Math.max(0, Math.floor(currentTime * 1000)),
      });
      return;
    }

    togglePlayPause();
  };

  const handleJamAwareNext = async () => {
    if (shouldRouteJamControl) {
      await jamSyncService.sendControlRequest("next");
      return;
    }

    nextSong();
  };

  const handleJamAwarePrevious = async () => {
    if (shouldRouteJamControl) {
      await jamSyncService.sendControlRequest("previous");
      return;
    }

    prevSong();
  };

  const handleJamAwareSeek = async (timeInSeconds: number) => {
    if (shouldRouteJamControl) {
      await jamSyncService.sendControlRequest("seek", {
        positionMs: Math.max(0, Math.floor(timeInSeconds * 1000)),
      });
      return;
    }

    seek(timeInSeconds);
  };

  const handleSongShare = async () => {
    try {
      const shareUrl = buildAbsoluteSiteUrl(`/song/${currentSong.id}`);
      const shareText = [
        `Listen on ${siteConfig.appName}`,
        decodeHtml(currentSong.title || currentSong.name || "Unknown Track"),
        decodeHtml(artistsStr || "Unknown Artist"),
        shareUrl,
      ].join("\n");

      await shareTextSafely({
        title: decodeHtml(currentSong.title || currentSong.name || siteConfig.appName),
        text: shareText,
        url: shareUrl,
      });
    } catch (error) {
      console.error("Song share failed", error);
    }
  };

  const handleJamShare = async () => {
    try {
      if (!currentSong || queue.length === 0 || currentIndex < 0) {
        return;
      }

      if (!jamState.isActive || !jamState.sessionId) {
        await jamSyncService.startSession(
          currentSong.albumName || currentSong.album?.name || currentSong.title,
        );
      } else {
        await jamSyncService.syncFromPlayback(true);
      }

      const latestJamState = useJamStore.getState();
      if (!latestJamState.sessionId || !latestJamState.shareCode) {
        return;
      }

      const hostName = latestJamState.hostName || "Nishant";
      const sourceName =
        latestJamState.sourceName ||
        currentSong.albumName ||
        currentSong.album?.name ||
        currentSong.title;

      const inviteUrl = buildJamInviteUrl({
        sessionId: latestJamState.sessionId,
        shareCode: latestJamState.shareCode,
        sourceName,
        hostName,
      });
      const deepLink = buildJamDeepLink({
        sessionId: latestJamState.sessionId,
        shareCode: latestJamState.shareCode,
        sourceName,
        hostName,
      });

      const shareText = [
        "Join my Svara Jam",
        "",
        `Now playing: ${decodeHtml(currentSong.title || currentSong.name || "Unknown Track")}`,
        `Host: ${hostName}`,
        `Session code: ${latestJamState.shareCode}`,
        `Listeners: ${latestJamState.participants.length || 1}`,
        "",
        `Join URL: ${inviteUrl}`,
        `Open in app: ${deepLink}`,
      ].join("\n");

      await shareTextSafely({
        title: "Join my Svara Jam",
        text: shareText,
        url: inviteUrl,
      });
    } catch (error) {
      console.error("Jam share failed", error);
    }
  };

  return (
    <div className="flex h-full w-full items-center justify-between px-2 font-spotify md:px-0">
      <div className="flex min-w-0 flex-1 items-center gap-2 md:flex-none md:gap-4">
        <div className="relative h-10 w-10 shrink-0 overflow-hidden rounded-md shadow-lg md:h-13 md:w-13">
          <Image
            src={getSaavnImageUrl(highestResImage, 500)}
            alt={currentSong.title || currentSong.name || "Album art"}
            fill
            sizes="52px"
            className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-110"
            unoptimized
          />
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <div className="truncate text-[13px] font-bold text-white transition-colors hover:underline md:text-[14px]">
            {decodeHtml(currentSong.title || currentSong.name || "Unknown Track")}
          </div>
          <div className="truncate text-[11px] text-text-subdued transition-colors md:text-[12px]">
            {decodeHtml(artistsStr)}
          </div>
        </div>
        <button
          onClick={() => toggleLike(currentSong, "song")}
          className="ml-2 hidden h-8 w-8 shrink-0 items-center justify-center transition-all hover:scale-110 active:scale-90 md:flex"
        >
          {isLiked(currentSong.id) ? (
            <Image src="/assets/icons/heart.png" alt="Liked" width={18} height={18} className="brightness-110" />
          ) : (
            <Image
              src="/assets/icons/like.png"
              alt="Like"
              width={18}
              height={18}
              className="invert opacity-70 hover:opacity-100"
            />
          )}
        </button>
      </div>

      <div className="flex flex-none flex-col items-center gap-1.5 px-2 md:flex-1">
        <div className="flex items-center gap-3 md:gap-8">
          <button
            onClick={toggleShuffle}
            className="hidden flex-col items-center justify-center transition-all hover:scale-110 active:scale-90 md:flex"
          >
            <div className="relative flex flex-col items-center">
              <Image
                src="/assets/icons/shuffle.png"
                alt="Shuffle"
                width={16}
                height={16}
                className={`transition-all ${
                  isShuffling ? "opacity-100" : "invert opacity-50 hover:opacity-100"
                }`}
                style={
                  isShuffling
                    ? {
                        filter:
                          "invert(62%) sepia(100%) saturate(404%) hue-rotate(84deg) brightness(89%) contrast(92%)",
                      }
                    : {}
                }
              />
              {isShuffling ? (
                <div className="absolute -bottom-1.5 left-1/2 h-0.75 w-0.75 -translate-x-1/2 rounded-full bg-primary shadow-[0_0_8px_rgba(30,215,96,0.6)]" />
              ) : null}
            </div>
          </button>

          <button
            onClick={() => {
              void handleJamAwarePrevious();
            }}
            className="text-text-subdued transition-all hover:scale-110 hover:text-white active:scale-90"
          >
            <svg role="img" height="20" width="20" viewBox="0 0 16 16" fill="currentColor" className="md:h-4 md:w-4"><path d="M3.3 1a.7.7 0 0 1 .7.7v5.15l9.95-5.744a.7.7 0 0 1 1.05.606v12.575a.7.7 0 0 1-1.05.607L4 9.149V14.3a.7.7 0 0 1-.7.7H1.7a.7.7 0 0 1-.7-.7V1.7a.7.7 0 0 1 .7-.7h1.6z"></path></svg>
          </button>

          <button
            onClick={() => {
              void handleJamAwarePlayPause();
            }}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-white text-black shadow-lg transition-all hover:scale-105 active:scale-95 md:h-10 md:w-10"
          >
            {isPlaying ? (
              <svg role="img" height="18" width="18" viewBox="0 0 16 16" fill="currentColor" className="md:h-4 md:w-4"><path d="M2.7 1a.7.7 0 0 0-.7.7v12.6a.7.7 0 0 0 .7.7h2.6a.7.7 0 0 0 .7-.7V1.7a.7.7 0 0 0-.7-.7H2.7zm8 0a.7.7 0 0 0-.7.7v12.6a.7.7 0 0 0 .7.7h2.6a.7.7 0 0 0 .7-.7V1.7a.7.7 0 0 0-.7-.7h-2.6z"></path></svg>
            ) : (
              <svg role="img" height="18" width="18" viewBox="0 0 16 16" fill="currentColor" className="ml-0.5 md:h-4 md:w-4"><path d="M3 1.713a.7.7 0 0 1 1.05-.607l10.89 6.288a.7.7 0 0 1 0 1.212L4.05 14.894A.7.7 0 0 1 3 14.288V1.713z"></path></svg>
            )}
          </button>

          <button
            onClick={() => {
              void handleJamAwareNext();
            }}
            className="text-text-subdued transition-all hover:scale-110 hover:text-white active:scale-90"
          >
            <svg role="img" height="20" width="20" viewBox="0 0 16 16" fill="currentColor" className="md:h-4 md:w-4"><path d="M12.7 1a.7.7 0 0 0-.7.7v5.15L2.05 1.107A.7.7 0 0 0 1 1.712v12.575a.7.7 0 0 0 1.05.607L12 9.149V14.3a.7.7 0 0 0 .7.7h1.6a.7.7 0 0 0 .7-.7V1.7a.7.7 0 0 0-.7-.7h-1.6z"></path></svg>
          </button>

          <button
            onClick={toggleRepeat}
            className="hidden transition-all hover:scale-110 active:scale-90 md:flex"
          >
            <div className="relative">
              <Image
                src="/assets/icons/repeat.png"
                alt="Repeat"
                width={16}
                height={16}
                className={`invert transition-all ${
                  repeatMode !== "NONE" ? "opacity-100" : "opacity-50 hover:opacity-100"
                }`}
              />
              {repeatMode === "ONE" ? (
                <span className="absolute -right-1 -top-1 flex h-2.5 w-2.5 items-center justify-center rounded-full bg-primary text-[8px] font-bold text-black">
                  1
                </span>
              ) : null}
            </div>
          </button>
        </div>

        <div className="hidden w-full max-w-125 items-center gap-2 md:flex">
          <span className="min-w-8 text-right text-[11px] text-text-subdued">
            {formatTime(currentTime)}
          </span>
          <div
            className="group/progress relative flex h-3 flex-1 cursor-pointer items-center"
            onMouseEnter={() => setIsHoveringProgress(true)}
            onMouseLeave={() => setIsHoveringProgress(false)}
            onClick={(event) => {
              const rect = event.currentTarget.getBoundingClientRect();
              const x = event.clientX - rect.left;
              const percent = x / rect.width;
              void handleJamAwareSeek(percent * duration);
            }}
          >
            <div className="h-1 w-full overflow-hidden rounded-full bg-white/10">
              <div
                className={`h-full transition-colors duration-200 ${
                  isHoveringProgress ? "bg-primary" : "bg-white"
                }`}
                style={{ width: `${duration ? (currentTime / duration) * 100 : 0}%` }}
              />
            </div>
          </div>
          <span className="min-w-8 text-[11px] text-text-subdued">{formatTime(duration)}</span>
        </div>
      </div>

      <div className="hidden w-45 items-center justify-end gap-1.5 md:flex md:w-60 md:gap-3 lg:w-85">
        <button
          onClick={() => {
            void handleSongShare();
          }}
          className="hidden items-center gap-1.5 rounded-full border border-white/10 px-3 py-1.5 text-[11px] font-bold uppercase tracking-[0.18em] text-white/70 transition hover:border-white/20 hover:bg-white/6 hover:text-white lg:flex"
          title="Share current song"
        >
          Share
        </button>
        <button
          onClick={() => {
            void handleJamShare();
          }}
          className={`hidden items-center gap-1.5 rounded-full border px-3 py-1.5 text-[11px] font-bold uppercase tracking-[0.18em] transition lg:flex ${
            jamState.isActive
              ? "border-primary/50 bg-primary/10 text-primary"
              : "border-white/10 text-white/70 hover:border-white/20 hover:bg-white/6 hover:text-white"
          }`}
          title="Start or share Jam"
        >
          <span className={`h-1.5 w-1.5 rounded-full ${jamState.isActive ? "bg-primary" : "bg-white/35"}`} />
          Jam
        </button>
        <button
          onClick={() => setShowQueue(!showQueue)}
          className="hidden p-1.5 transition-all hover:scale-110 active:scale-95 sm:flex"
        >
          <div className="relative flex flex-col items-center">
            <Image
              src="/assets/icons/queue.png"
              alt="Queue"
              width={16}
              height={16}
              className={`transition-all ${
                showQueue ? "opacity-100" : "invert opacity-50 hover:opacity-100"
              }`}
              style={
                showQueue
                  ? {
                      filter:
                        "invert(62%) sepia(100%) saturate(404%) hue-rotate(84deg) brightness(89%) contrast(92%)",
                    }
                  : {}
              }
            />
            {showQueue ? (
              <div className="absolute -bottom-1.5 left-1/2 h-0.75 w-0.75 -translate-x-1/2 rounded-full bg-primary shadow-[0_0_8px_rgba(30,215,96,0.6)]" />
            ) : null}
          </div>
        </button>

        <button
          onClick={async () => {
            const image =
              currentSong.images?.[currentSong.images.length - 1]?.url ||
              currentSong.image?.[currentSong.image.length - 1]?.url ||
              "/assets/icons/logo.png";

            const artistName =
              currentSong.artist ||
              (Array.isArray(currentSong.artists?.primary)
                ? currentSong.artists.primary[0]?.name
                : "") ||
              "Unknown Artist";

            if (pipService) {
              await pipService.enterPiP(image, currentSong.title || currentSong.name, artistName);
            }
          }}
          className="shrink-0 p-1.5 text-text-subdued transition-all hover:scale-110 hover:text-white active:scale-90"
          title="Mini Player"
        >
          <svg role="img" height="16" width="16" aria-hidden="true" viewBox="0 0 16 16" fill="currentColor"><path d="M11.848 1H4.152A1.152 1.152 0 0 0 3 2.152v11.696A1.152 1.152 0 0 0 4.152 15h7.696A1.152 1.152 0 0 0 13 13.848V2.152A1.152 1.152 0 0 0 11.848 1zM4 2.152a.152.152 0 0 1 .152-.152h7.696a.152.152 0 0 1 .152.152v11.696a.152.152 0 0 1-.152.152H4.152a.152.152 0 0 1-.152-.152V2.152z"></path><path d="M8 8a1 1 0 1 1-1-1 1 1 0 0 1 1 1z"></path></svg>
        </button>

        <div className="group/volume flex w-24 items-center gap-2 md:w-32">
          <button className="shrink-0 p-1.5 text-text-subdued transition-all hover:scale-110 hover:text-white active:scale-90">
            <Image
              src="/assets/icons/sound.png"
              alt="Volume"
              width={16}
              height={16}
              className="invert opacity-70 group-hover/volume:opacity-100"
            />
          </button>
          <div
            className="group/vol-prog relative flex h-3 flex-1 cursor-pointer items-center overflow-visible"
            onClick={(event) => {
              const rect = event.currentTarget.getBoundingClientRect();
              const x = Math.max(0, Math.min(event.clientX - rect.left, rect.width));
              const percent = x / rect.width;
              setVolume(percent);
            }}
          >
            <div className="h-1 w-full overflow-hidden rounded-full bg-white/10">
              <div
                className="h-full bg-white transition-colors group-hover/vol-prog:bg-primary"
                style={{ width: `${volume * 100}%` }}
              />
            </div>
            <div
              className="pointer-events-none absolute h-3 w-3 rounded-full bg-white shadow-lg transition-transform group-hover/vol-prog:scale-125"
              style={{ left: `calc(${volume * 100}% - 6px)` }}
            />
          </div>
        </div>
      </div>
    </div>
  );
};

export default Player;
