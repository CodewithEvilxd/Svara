import React from 'react';
import Image from 'next/image';

import { siteConfig } from '@/config/site';

const MainFooter = () => {
  return (
    <footer className="mt-20 px-4 md:px-8 pb-4 border-t border-white/5 pt-12 font-spotify">
      <div className="max-w-7xl mx-auto mb-10">
        <h2 className="text-[11px] font-black uppercase tracking-[0.3em] text-text-subdued opacity-60">
          Credits
        </h2>
      </div>
      <div className="flex flex-col md:flex-row items-center justify-between gap-8 max-w-7xl mx-auto">
        <div className="flex flex-col items-center md:items-start gap-2">
          <h2 className="text-2xl font-black text-white flex items-center gap-2">
            Nishant <span className="text-primary text-lg">Builds</span>
          </h2>
          <p className="text-[12px] font-bold text-text-subdued tracking-[0.2em] uppercase">
            Developer links
          </p>

          <div className="flex items-center gap-8 mt-5">
            <SocialLink href={siteConfig.portfolioUrl} icon="/assets/icons/case.png" label="Portfolio" />
            <SocialLink href={siteConfig.githubProfileUrl} icon="/assets/icons/github.png" label="GitHub" />
            <SocialLink href={siteConfig.emailUrl} icon="/assets/icons/atsign.png" label="Email" />
          </div>
        </div>

        <div className="flex flex-col items-center md:items-end gap-5 text-center md:text-right">
          <div className="flex flex-col items-center md:items-end gap-2">
            <h3 className="text-[12px] font-black uppercase tracking-[0.2em] text-white">
              {siteConfig.appName} ecosystem
            </h3>
            <p className="text-[10px] text-text-subdued font-bold mb-1 opacity-70">
              Shared API, shared discovery, and Jam invites that can jump between web and Android.
            </p>
            <a
              href={siteConfig.githubUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="group flex items-center gap-3 px-6 py-2.5 bg-white text-black rounded-full font-black text-[11px] uppercase tracking-widest transition-all hover:scale-[1.03] active:scale-[0.98] shadow-xl"
            >
              <Image
                src="/assets/icons/github.png"
                alt=""
                width={20}
                height={20}
                className="group-hover:rotate-[360deg] transition-transform duration-700"
              />
              <span>Open Repository</span>
            </a>
          </div>

          <div className="flex flex-col items-center md:items-end gap-2.5 text-[10px] font-black uppercase tracking-[0.2em] text-text-subdued pt-2 opacity-80">
            <div className="flex items-center gap-4">
              <span>&copy; {new Date().getFullYear()} {siteConfig.appName}</span>
              <span className="w-1 h-1 rounded-full bg-white/10"></span>
              <span className="flex items-center gap-1.5 pt-0.5">
                Crafted with <Image src="/assets/icons/heart.png" alt="" width={14} height={14} className="brightness-110" /> in India
              </span>
            </div>
            <div className="flex items-center gap-3 opacity-50 hover:opacity-100 transition-opacity duration-500 cursor-default">
              <span>Next.js</span>
              <span className="w-1 h-1 rounded-full bg-white/20"></span>
              <span>Tailwind</span>
              <span className="w-1 h-1 rounded-full bg-white/20"></span>
              <span>Supabase Realtime</span>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
};

const SocialLink = ({
  href,
  icon,
  label,
}: {
  href: string;
  icon: string;
  label: string;
}) => (
  <a
    href={href}
    target="_blank"
    rel="noopener noreferrer"
    className="group flex items-center gap-2 opacity-60 hover:opacity-100 transition-all duration-300"
    title={label}
  >
    <Image src={icon} alt={label} width={30} height={30} className="invert brightness-200" />
  </a>
);

export default MainFooter;
