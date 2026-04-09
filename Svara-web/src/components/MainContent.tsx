"use client";

import React from "react";
import Link from "next/link";

import MainFooter from "@/components/MainFooter";
import MobileAppBanner from "@/components/MobileAppBanner";
import { SaavnAPI, decodeHtml } from "@/services/api";
import { historyService } from "@/services/history";
import { useLikesStore } from "@/store/likesStore";
import { Album, Artist, Playlist } from "@/types";
import { getSaavnImageUrl } from "@/utils/image";

type ShelfType = "playlist" | "album" | "artist";

interface MainContentProps {
  featuredCards: Playlist[];
  madeForYou: Playlist[];
  bollywoodTrending: Playlist[];
  globalCharts: Playlist[];
  regionalHeat: Playlist[];
  nightDrive: Playlist[];
  romanceMix: Playlist[];
  freshReleases: Album[];
  artists: Artist[];
  preferredLanguage: string;
}

interface CategoryState {
  title: string;
  items: any[];
  type: ShelfType;
}

interface PersonalShelf {
  title: string;
  type: "playlist" | "album";
  items: any[];
}

const mediaImage = (item: any) => {
  if (Array.isArray(item.images) && item.images.length > 0) {
    return item.images[item.images.length - 1].url || item.images[0].url || "/assets/icons/logo.png";
  }
  if (typeof item.image === "string" && item.image) {
    return item.image;
  }
  if (Array.isArray(item.image) && item.image.length > 0) {
    return item.image[item.image.length - 1].url || item.image[0].url || "/assets/icons/logo.png";
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

const routeForType = (type: ShelfType, id: string) => `/${type}/${id}`;

const itemSubtitle = (item: any, type: ShelfType) => {
  if (type === "artist") {
    return "Artist";
  }
  if (type === "playlist") {
    return item.artist || (item.songCount ? `${item.songCount} songs` : "Playlist");
  }
  return item.artist || item.year || "Album";
};

const MainContent: React.FC<MainContentProps> = ({
  featuredCards,
  madeForYou,
  bollywoodTrending,
  globalCharts,
  regionalHeat,
  nightDrive,
  romanceMix,
  freshReleases,
  artists,
  preferredLanguage,
}) => {
  const { getLikedAlbums, getLikedPlaylists, likedItems } = useLikesStore();
  const [activeCategory, setActiveCategory] = React.useState<CategoryState | null>(null);
  const [personalShelves, setPersonalShelves] = React.useState<PersonalShelf[]>([]);

  React.useEffect(() => {
    const scrollContainer = document.querySelector("main > div");
    if (scrollContainer) {
      scrollContainer.scrollTo({ top: 0, behavior: "auto" });
    }
  }, [activeCategory]);

  React.useEffect(() => {
    let cancelled = false;

    const buildPersonalShelves = async () => {
      const likedPlaylists = getLikedPlaylists().slice(0, 10);
      const likedAlbums = getLikedAlbums().slice(0, 10);
      const recentHistory = await historyService.getHistory();

      if (cancelled) {
        return;
      }

      const shelves: PersonalShelf[] = [];

      const recentPlaylistItems = recentHistory
        .filter((entry) => entry.type === "playlist")
        .map((entry) => ({
          ...entry,
          title: entry.title || entry.name,
          name: entry.name || entry.title,
          images: entry.images,
          artist: entry.artist || entry.primaryArtists || "Playlist",
        }));
      const recentAlbumItems = recentHistory
        .filter((entry) => entry.type === "album")
        .map((entry) => ({
          ...entry,
          title: entry.title || entry.name,
          name: entry.name || entry.title,
          images: entry.images,
          artist: entry.artist || entry.primaryArtists || "Album",
        }));

      if (recentPlaylistItems.length > 0) {
        shelves.push({
          title: "Continue from your last vibe",
          type: "playlist",
          items: recentPlaylistItems.slice(0, 10),
        });
      }

      if (recentAlbumItems.length > 0) {
        shelves.push({
          title: "Back to recent releases",
          type: "album",
          items: recentAlbumItems.slice(0, 10),
        });
      }

      if (likedPlaylists.length > 0) {
        shelves.push({
          title: "Saved playlists",
          type: "playlist",
          items: likedPlaylists,
        });
      }

      if (likedAlbums.length > 0) {
        shelves.push({
          title: "Saved albums",
          type: "album",
          items: likedAlbums,
        });
      }

      const discoverySeed =
        likedPlaylists[0]?.name ||
        likedAlbums[0]?.name ||
        recentHistory[0]?.name ||
        preferredLanguage;

      if (discoverySeed) {
        const discoveryResponse = await SaavnAPI.searchPlaylists(`${discoverySeed} mix`, 0, 10);
        if (!cancelled && discoveryResponse?.results?.length) {
          shelves.unshift({
            title: `Because you like ${decodeHtml(discoverySeed)}`,
            type: "playlist",
            items: uniqueById(discoveryResponse.results).slice(0, 10),
          });
        }
      }

      if (!cancelled) {
        setPersonalShelves(shelves);
      }
    };

    void buildPersonalShelves();

    return () => {
      cancelled = true;
    };
  }, [getLikedAlbums, getLikedPlaylists, likedItems, preferredLanguage]);

  if (activeCategory) {
    return (
      <div className="relative z-10 px-4 pb-32 pt-4">
        <div className="group mb-8 flex items-center gap-4">
          <button
            onClick={() => setActiveCategory(null)}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-black/40 transition-colors hover:bg-black/60"
          >
            <svg role="img" height="16" width="16" aria-hidden="true" viewBox="0 0 16 16" fill="white"><path d="M11.03.47a.75.75 0 0 1 0 1.06L4.56 8l6.47 6.47a.75.75 0 1 1-1.06 1.06L2.44 8.53a.75.75 0 0 1 0-1.06L9.97.47a.75.75 0 0 1 1.06 0z"></path></svg>
          </button>
          <h1
            className="cursor-pointer text-3xl font-black text-white group-hover:underline"
            onClick={() => setActiveCategory(null)}
          >
            {activeCategory.title}
          </h1>
        </div>

        <div className="flex flex-wrap justify-start gap-x-2 gap-y-4 md:gap-x-4 md:gap-y-6">
          {activeCategory.items.map((item: any, index: number) => (
            <Link
              key={item.id || index}
              href={routeForType(activeCategory.type, item.id)}
              className={`group block rounded-lg bg-transparent p-2 transition-all duration-300 hover:bg-white/5 active:scale-[0.98] md:p-3 ${
                activeCategory.type === "artist"
                  ? "w-[calc(50%-8px)] md:w-[calc(25%-12px)] lg:w-[calc(20%-13px)]"
                  : "w-[calc(50%-8px)] md:w-[calc(25%-12px)] lg:w-[calc(20%-13px)]"
              }`}
            >
              <div
                className={`relative mb-3 aspect-square overflow-hidden shadow-2xl ${
                  activeCategory.type === "artist" ? "rounded-full" : "rounded-md"
                }`}
              >
                <img
                  src={getSaavnImageUrl(mediaImage(item), 500)}
                  alt={item.title || item.name || "Artwork"}
                  className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-105"
                />
                {activeCategory.type !== "artist" ? (
                  <div className="absolute bottom-2 right-2 flex h-10 w-10 translate-y-3 items-center justify-center rounded-full bg-primary text-black opacity-0 shadow-[0_8px_16px_rgba(0,0,0,0.5)] transition-all group-hover:translate-y-0 group-hover:opacity-100 hover:scale-105 active:scale-95">
                    <svg role="img" height="20" width="20" aria-hidden="true" viewBox="0 0 24 24" fill="currentColor"><path d="M7.05 3.606l13.49 7.788a.7.7 0 0 1 0 1.212L7.05 20.394A.7.7 0 0 1 6 19.788V4.212a.7.7 0 0 1 1.05-.606z"></path></svg>
                  </div>
                ) : null}
              </div>
              <div className={`mb-0.5 line-clamp-1 text-[14px] font-bold text-white transition-colors group-hover:text-primary ${activeCategory.type === "artist" ? "text-center" : ""}`}>
                {decodeHtml(item.name || item.title || "")}
              </div>
              <div className={`line-clamp-2 text-[12px] leading-snug text-text-subdued ${activeCategory.type === "artist" ? "text-center" : ""}`}>
                {decodeHtml(itemSubtitle(item, activeCategory.type))}
              </div>
            </Link>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="relative min-h-screen font-spotify">
      <div className="absolute left-[-32px] right-[-32px] top-[-80px] z-0 h-[340px] bg-gradient-to-b from-[#0c3320]/65 via-[#121212]/85 to-[#121212] pointer-events-none" />

      <div className="relative z-10 mt-10 px-4 pt-4 md:px-8">
        <div className="mb-4 max-w-3xl">
          <div className="text-[11px] font-bold uppercase tracking-[0.26em] text-primary">
            Home mix
          </div>
          <h1 className="mt-3 text-3xl font-black tracking-tight text-white md:text-5xl">
            Svara keeps web and Android on the same music lane
          </h1>
          <p className="mt-3 max-w-2xl text-sm leading-6 text-white/65 md:text-base">
            Trending shelves, shared API search, Jam links, queue playback, and deeper artist
            pages now line up much closer with the app experience.
          </p>
        </div>

        <div className="mb-8 grid grid-cols-2 gap-x-2 gap-y-1.5 md:gap-x-4 md:gap-y-3 lg:grid-cols-4">
          <Link href="/playlist/liked">
            <FeaturedCard title="Liked Songs" image="/assets/icons/heart.png" special />
          </Link>
          {featuredCards.slice(0, 7).map((playlist, index) => (
            <Link key={`${playlist.id}-${index}`} href={`/playlist/${playlist.id}`}>
              <FeaturedCard title={decodeHtml(playlist.name || playlist.title || "")} image={mediaImage(playlist)} />
            </Link>
          ))}
        </div>

        <div className="mb-8 md:hidden">
          <MobileAppBanner />
        </div>

        {personalShelves.map((shelf) =>
          shelf.items.length > 0 ? (
            <Section
              key={shelf.title}
              title={shelf.title}
              items={shelf.items}
              type={shelf.type}
              onShowAll={() => setActiveCategory({ title: shelf.title, items: shelf.items, type: shelf.type })}
            />
          ) : null,
        )}

        {madeForYou.length > 0 ? (
          <Section
            title="Made for you"
            items={madeForYou}
            type="playlist"
            onShowAll={() => setActiveCategory({ title: "Made for you", items: madeForYou, type: "playlist" })}
          />
        ) : null}

        {bollywoodTrending.length > 0 ? (
          <Section
            title="Bollywood Trending"
            items={bollywoodTrending}
            type="playlist"
            onShowAll={() =>
              setActiveCategory({
                title: "Bollywood Trending",
                items: bollywoodTrending,
                type: "playlist",
              })
            }
          />
        ) : null}

        {globalCharts.length > 0 ? (
          <Section
            title="Global Charts"
            items={globalCharts}
            type="playlist"
            onShowAll={() =>
              setActiveCategory({ title: "Global Charts", items: globalCharts, type: "playlist" })
            }
          />
        ) : null}

        {freshReleases.length > 0 ? (
          <Section
            title="Fresh Releases"
            items={freshReleases}
            type="album"
            onShowAll={() =>
              setActiveCategory({ title: "Fresh Releases", items: freshReleases, type: "album" })
            }
          />
        ) : null}

        {artists.length > 0 ? (
          <ArtistSection
            title="Artists to open next"
            artists={artists}
            onShowAll={() => setActiveCategory({ title: "Artists to open next", items: artists, type: "artist" })}
          />
        ) : null}

        <div className="mb-8 hidden md:block">
          <MobileAppBanner />
        </div>

        {regionalHeat.length > 0 ? (
          <Section
            title="Regional Heat"
            items={regionalHeat}
            type="playlist"
            onShowAll={() =>
              setActiveCategory({ title: "Regional Heat", items: regionalHeat, type: "playlist" })
            }
          />
        ) : null}

        {nightDrive.length > 0 ? (
          <Section
            title="Night Drive"
            items={nightDrive}
            type="playlist"
            onShowAll={() => setActiveCategory({ title: "Night Drive", items: nightDrive, type: "playlist" })}
          />
        ) : null}

        {romanceMix.length > 0 ? (
          <Section
            title="Romance Mix"
            items={romanceMix}
            type="playlist"
            onShowAll={() => setActiveCategory({ title: "Romance Mix", items: romanceMix, type: "playlist" })}
          />
        ) : null}

        <MainFooter />
      </div>
    </div>
  );
};

const FeaturedCard = ({ title, image, special }: { title: string; image: string; special?: boolean }) => (
  <div className="group relative flex h-[48px] items-center gap-3 overflow-hidden rounded-md bg-white/5 pr-3 transition-all duration-300 hover:bg-white/10 active:scale-[0.99] md:h-[64px] md:gap-4">
    <div
      className={`flex h-full w-[48px] flex-shrink-0 items-center justify-center shadow-2xl md:w-[64px] ${
        special ? "bg-gradient-to-br from-[#1ed760] to-[#dfffe9] p-3 md:p-4" : "bg-[#282828]"
      }`}
    >
      <img
        src={special ? image : getSaavnImageUrl(image, 150)}
        alt={title}
        className={`h-full w-full object-cover transition-transform duration-500 group-hover:scale-105 ${
          special ? "invert" : ""
        }`}
      />
    </div>
    <span className="line-clamp-2 flex-1 text-[12px] font-bold leading-tight text-white md:pr-10 md:text-[14px]">
      {title}
    </span>
    <div className="absolute right-3 hidden h-8 w-8 translate-y-2 items-center justify-center rounded-full bg-primary text-black opacity-0 shadow-2xl transition-all group-hover:translate-y-0 group-hover:opacity-100 hover:scale-105 active:scale-95 lg:flex md:h-11 md:w-11">
      <svg role="img" height="24" width="24" aria-hidden="true" viewBox="0 0 24 24" fill="currentColor"><path d="M7.05 3.606l13.49 7.788a.7.7 0 0 1 0 1.212L7.05 20.394A.7.7 0 0 1 6 19.788V4.212a.7.7 0 0 1 1.05-.606z"></path></svg>
    </div>
  </div>
);

const Section = ({
  title,
  items,
  type,
  onShowAll,
}: {
  title: string;
  items: any[];
  type: "playlist" | "album";
  onShowAll: () => void;
}) => {
  const scrollRef = React.useRef<HTMLDivElement>(null);
  const [showLeft, setShowLeft] = React.useState(false);
  const [showRight, setShowRight] = React.useState(true);

  const checkScroll = React.useCallback(() => {
    if (!scrollRef.current) {
      return;
    }
    const { scrollLeft, scrollWidth, clientWidth } = scrollRef.current;
    setShowLeft(scrollLeft > 10);
    setShowRight(scrollLeft + clientWidth < scrollWidth - 10);
  }, []);

  React.useEffect(() => {
    const element = scrollRef.current;
    if (!element) {
      return;
    }
    checkScroll();
    element.addEventListener("scroll", checkScroll);
    window.addEventListener("resize", checkScroll);
    return () => {
      element.removeEventListener("scroll", checkScroll);
      window.removeEventListener("resize", checkScroll);
    };
  }, [checkScroll]);

  const scroll = (direction: "left" | "right") => {
    scrollRef.current?.scrollBy({
      left: direction === "left" ? -600 : 600,
      behavior: "smooth",
    });
  };

  return (
    <section className="group/section relative mb-10">
      <div className="mb-3 flex items-center justify-between px-1">
        <h2
          onClick={onShowAll}
          className="cursor-pointer text-[20px] font-bold tracking-tight text-white underline-offset-4 hover:underline md:text-[22px]"
        >
          {title}
        </h2>
        {items.length > 5 ? (
          <button
            onClick={onShowAll}
            className="text-[14px] font-bold text-text-subdued transition-all hover:text-white hover:underline"
          >
            Show all
          </button>
        ) : null}
      </div>

      <div className="relative">
        <div className={`pointer-events-none absolute bottom-4 left-[-12px] top-0 z-20 flex w-64 items-center justify-start bg-gradient-to-r from-[#121212] to-transparent opacity-0 transition-opacity duration-300 lg:group-hover/section:opacity-100 ${!showLeft ? "!opacity-0 pointer-events-none" : ""}`}>
          <button
            onClick={() => scroll("left")}
            className="pointer-events-auto ml-2 flex h-10 w-10 items-center justify-center rounded-full bg-[#333]/90 shadow-2xl transition-all hover:bg-[#444] active:scale-95 md:ml-4"
          >
            <svg role="img" height="20" width="20" aria-hidden="true" viewBox="0 0 16 16" fill="white"><path d="M11.03.47a.75.75 0 0 1 0 1.06L4.56 8l6.47 6.47a.75.75 0 1 1-1.06 1.06L2.44 8.53a.75.75 0 0 1 0-1.06L9.97.47a.75.75 0 0 1 1.06 0z"></path></svg>
          </button>
        </div>

        <div className={`pointer-events-none absolute bottom-4 right-[-12px] top-0 z-20 flex w-64 items-center justify-end bg-gradient-to-l from-[#121212] to-transparent opacity-0 transition-opacity duration-300 lg:group-hover/section:opacity-100 ${!showRight ? "!opacity-0 pointer-events-none" : ""}`}>
          <button
            onClick={() => scroll("right")}
            className="pointer-events-auto mr-2 flex h-10 w-10 items-center justify-center rounded-full bg-[#333]/90 shadow-2xl transition-all hover:bg-[#444] active:scale-95 md:mr-4"
          >
            <svg role="img" height="20" width="20" aria-hidden="true" viewBox="0 0 16 16" fill="white"><path d="M4.97.47a.75.75 0 0 0 0 1.06L11.44 8l-6.47 6.47a.75.75 0 1 0 1.06 1.06L13.56 8.53a.75.75 0 0 0 0-1.06L6.03.47a.75.75 0 0 0-1.06 0z"></path></svg>
          </button>
        </div>

        <div ref={scrollRef} className="-mx-2 flex gap-4 overflow-x-auto px-2 pb-4 scrollbar-hide scroll-smooth">
          {items.slice(0, 15).map((item: any, index: number) => (
            <Link
              key={item.id || index}
              href={routeForType(type, item.id)}
              className="group block min-w-[160px] rounded-lg bg-transparent p-2 transition-all duration-300 hover:bg-white/5 active:scale-[0.98] md:min-w-[180px] md:p-3"
            >
              <div className="relative mb-3 aspect-square overflow-hidden rounded-md shadow-2xl">
                <img
                  src={getSaavnImageUrl(mediaImage(item), 500)}
                  alt={item.title || item.name || "Artwork"}
                  className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-105"
                />
                <div className="absolute bottom-2 right-2 flex h-10 w-10 translate-y-3 items-center justify-center rounded-full bg-primary text-black opacity-0 shadow-[0_8px_16px_rgba(0,0,0,0.5)] transition-all group-hover:translate-y-0 group-hover:opacity-100 hover:scale-105 active:scale-95">
                  <svg role="img" height="20" width="20" aria-hidden="true" viewBox="0 0 24 24" fill="currentColor"><path d="M7.05 3.606l13.49 7.788a.7.7 0 0 1 0 1.212L7.05 20.394A.7.7 0 0 1 6 19.788V4.212a.7.7 0 0 1 1.05-.606z"></path></svg>
                </div>
              </div>
              <div className="mb-0.5 line-clamp-1 text-[14px] font-bold text-white transition-colors group-hover:text-primary">
                {decodeHtml(item.name || item.title || "")}
              </div>
              <div className="line-clamp-2 text-[12px] leading-snug text-text-subdued">
                {decodeHtml(itemSubtitle(item, type))}
              </div>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
};

const ArtistSection = ({
  title,
  artists,
  onShowAll,
}: {
  title: string;
  artists: Artist[];
  onShowAll: () => void;
}) => {
  const scrollRef = React.useRef<HTMLDivElement>(null);
  const [showLeft, setShowLeft] = React.useState(false);
  const [showRight, setShowRight] = React.useState(true);

  const checkScroll = React.useCallback(() => {
    if (!scrollRef.current) {
      return;
    }
    const { scrollLeft, scrollWidth, clientWidth } = scrollRef.current;
    setShowLeft(scrollLeft > 10);
    setShowRight(scrollLeft + clientWidth < scrollWidth - 10);
  }, []);

  React.useEffect(() => {
    const element = scrollRef.current;
    if (!element) {
      return;
    }
    checkScroll();
    element.addEventListener("scroll", checkScroll);
    window.addEventListener("resize", checkScroll);
    return () => {
      element.removeEventListener("scroll", checkScroll);
      window.removeEventListener("resize", checkScroll);
    };
  }, [checkScroll]);

  const scroll = (direction: "left" | "right") => {
    scrollRef.current?.scrollBy({
      left: direction === "left" ? -600 : 600,
      behavior: "smooth",
    });
  };

  return (
    <section className="group/artist relative mb-10">
      <div className="mb-3 flex items-center justify-between px-1">
        <h2
          onClick={onShowAll}
          className="cursor-pointer text-[20px] font-bold tracking-tight text-white underline-offset-4 hover:underline md:text-[22px]"
        >
          {title}
        </h2>
        {artists.length > 5 ? (
          <button
            onClick={onShowAll}
            className="text-[13px] font-bold text-text-subdued transition-all hover:text-white hover:underline"
          >
            Show all
          </button>
        ) : null}
      </div>

      <div className="relative">
        <div className={`pointer-events-none absolute bottom-4 left-[-12px] top-0 z-20 flex w-64 items-center justify-start bg-gradient-to-r from-[#121212] to-transparent opacity-0 transition-opacity duration-300 lg:group-hover/artist:opacity-100 ${!showLeft ? "!opacity-0 pointer-events-none" : ""}`}>
          <button
            onClick={() => scroll("left")}
            className="pointer-events-auto ml-2 flex h-10 w-10 items-center justify-center rounded-full bg-[#333]/90 shadow-2xl transition-all hover:bg-[#444] active:scale-95 md:ml-4"
          >
            <svg role="img" height="20" width="20" aria-hidden="true" viewBox="0 0 16 16" fill="white"><path d="M11.03.47a.75.75 0 0 1 0 1.06L4.56 8l6.47 6.47a.75.75 0 1 1-1.06 1.06L2.44 8.53a.75.75 0 0 1 0-1.06L9.97.47a.75.75 0 0 1 1.06 0z"></path></svg>
          </button>
        </div>

        <div className={`pointer-events-none absolute bottom-4 right-[-12px] top-0 z-20 flex w-64 items-center justify-end bg-gradient-to-l from-[#121212] to-transparent opacity-0 transition-opacity duration-300 lg:group-hover/artist:opacity-100 ${!showRight ? "!opacity-0 pointer-events-none" : ""}`}>
          <button
            onClick={() => scroll("right")}
            className="pointer-events-auto mr-2 flex h-10 w-10 items-center justify-center rounded-full bg-[#333]/90 shadow-2xl transition-all hover:bg-[#444] active:scale-95 md:mr-4"
          >
            <svg role="img" height="20" width="20" aria-hidden="true" viewBox="0 0 16 16" fill="white"><path d="M4.97.47a.75.75 0 0 0 0 1.06L11.44 8l-6.47 6.47a.75.75 0 1 0 1.06 1.06L13.56 8.53a.75.75 0 0 0 0-1.06L6.03.47a.75.75 0 0 0-1.06 0z"></path></svg>
          </button>
        </div>

        <div ref={scrollRef} className="-mx-2 flex gap-4 overflow-x-auto px-2 pb-4 scrollbar-hide scroll-smooth">
          {artists.slice(0, 15).map((artist, index) => (
            <Link
              key={artist.id || index}
              href={`/artist/${artist.id}`}
              className="group min-w-[140px] rounded-lg bg-transparent p-2 transition-all duration-300 hover:bg-white/5 active:scale-[0.98] md:min-w-[180px] md:p-3"
            >
              <div className="relative mb-3 aspect-square overflow-hidden rounded-full border border-white/5 shadow-2xl">
                <img
                  src={getSaavnImageUrl(mediaImage(artist), 500)}
                  alt={artist.name || "Artist"}
                  className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-105"
                />
              </div>
              <div className="mb-0.5 line-clamp-1 text-center text-[14px] font-bold text-white transition-colors group-hover:text-primary">
                {decodeHtml(artist.name || "")}
              </div>
              <div className="line-clamp-2 text-center text-[12px] leading-snug text-text-subdued">Artist</div>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
};

export default MainContent;
