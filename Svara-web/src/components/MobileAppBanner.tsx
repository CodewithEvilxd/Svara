import React from 'react';
import Image from 'next/image';

import { siteConfig } from '@/config/site';

const featureItems = [
  { label: 'Play', text: 'Shared queue controls with next, previous, repeat, shuffle, and autoplay-ready playback' },
  { label: 'Sync', text: 'Jam invite links and session codes designed to connect web listeners with the Android app' },
  { label: 'Cache', text: 'Local caching and offline-first playback behavior for smoother listening' },
  { label: 'Search', text: 'Unified search across songs, albums, playlists, and artists' },
  { label: 'Trend', text: 'Trending shelves across Bollywood, global, and regional discovery' },
  { label: 'Share', text: 'Direct links for songs, albums, playlists, and Jam sessions' },
];

const MobileAppBanner = () => {
  return (
    <div className="w-full relative overflow-hidden rounded-2xl bg-gradient-to-br from-[#050505] via-[#121212] to-[#1ed760]/10 p-8 md:p-12 border border-white/5 shadow-2xl flex flex-col gap-8 group my-12 font-spotify">
      <div className="absolute inset-0 bg-white/[0.02] opacity-0 group-hover:opacity-100 transition-opacity duration-700" />

      <div className="relative z-10 flex flex-col items-center md:items-start gap-4 text-center md:text-left">
        <div className="w-16 h-16 md:w-20 md:h-20 flex items-center justify-center transform transition-transform group-hover:scale-105">
          <Image
            src="/assets/icons/logo.png"
            alt={siteConfig.appName}
            width={64}
            height={64}
            className="object-contain transition-all"
          />
        </div>

        <div className="space-y-2">
          <h2 className="text-3xl md:text-4xl font-black text-white leading-tight">
            {siteConfig.appName} for Android
          </h2>
          <p className="text-text-subdued text-sm md:text-base font-bold leading-relaxed max-w-2xl">
            <span className="text-[#1ed760]">Carry the same library across web and phone.</span>{' '}
            <br className="hidden md:block" />
            Search, queue, lyrics, offline playback, and Jam invites stay aligned with the Svara
            app experience.
          </p>
        </div>
      </div>

      <div className="relative z-10 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-y-4 gap-x-8 px-2">
        {featureItems.map((item) => (
          <FeatureItem key={item.label} label={item.label} text={item.text} />
        ))}
      </div>

      <div className="relative z-10 flex flex-col items-center md:items-start gap-6 mt-4">
        <a
          href={siteConfig.androidReleaseUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="px-12 py-4 bg-[#1ed760] text-black rounded-full font-black text-sm md:text-[15px] uppercase tracking-widest transition-all hover:scale-105 active:scale-95 shadow-[0_8px_32px_rgba(30,215,96,0.3)]"
        >
          Get the app
        </a>

        <div className="flex flex-col gap-1 items-center md:items-start opacity-60">
          <p className="text-[11px] font-black text-white uppercase tracking-[0.2em]">
            One listening stack, web to mobile
          </p>
          <p className="text-[10px] text-text-subdued max-w-md text-center md:text-left leading-relaxed font-bold">
            Use the browser when you are on desktop and hand the same session to the Android app
            when you move away. No clutter, just music.
          </p>
        </div>
      </div>
    </div>
  );
};

const FeatureItem = ({ label, text }: { label: string; text: string }) => (
  <div className="flex items-start gap-3">
    <span className="text-[11px] leading-none pt-1 px-2 py-1 rounded-full bg-white/8 text-white/80 uppercase tracking-[0.16em] font-black">
      {label}
    </span>
    <span className="text-[12px] font-bold text-text-subdued leading-tight opacity-70 group-hover:opacity-100 transition-opacity">
      {text}
    </span>
  </div>
);

export default MobileAppBanner;
