"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";

import {
  buildJamDeepLink,
  buildJamInviteUrl,
  jamSyncService,
  parseJamInvite,
} from "@/services/jam";
import { useJamStore } from "@/store/jamStore";
import { siteConfig } from "@/config/site";

const JamPage = () => {
  const searchParams = useSearchParams();
  const jamState = useJamStore();
  const [input, setInput] = useState("");
  const [statusMessage, setStatusMessage] = useState("");

  const parsedInvite = useMemo(() => parseJamInvite(searchParams), [searchParams]);

  useEffect(() => {
    if (!parsedInvite.sessionId) {
      return;
    }

    void (async () => {
      try {
        await jamSyncService.joinSession(parsedInvite.sessionId);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unable to join Jam session.";
        setStatusMessage(message);
      }
    })();
  }, [parsedInvite.sessionId]);

  const joinCurrentInput = async () => {
    const rawInput = input.trim();
    let parsedInputSessionId = "";

    if (rawInput) {
      try {
        const parsedInput = parseJamInvite(rawInput);
        parsedInputSessionId = parsedInput.sessionId;
      } catch {
        parsedInputSessionId = "";
      }
    }

    const target =
      parsedInputSessionId || rawInput || parsedInvite.sessionId || parsedInvite.shareCode;
    if (!target) {
      setStatusMessage("Enter a session code or open a valid invite link.");
      return;
    }

    try {
      await jamSyncService.joinSession(target);
      setStatusMessage("Jam connected. If the host is already playing, the shared queue will load here.");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unable to join Jam session.";
      setStatusMessage(message);
    }
  };

  const shareCode =
    jamState.shareCode || parsedInvite.shareCode || (jamState.sessionId ? jamState.sessionId.replace(/^jam-/, "").toUpperCase() : "");
  const sessionId = jamState.sessionId || parsedInvite.sessionId;
  const hostName = jamState.hostName || parsedInvite.hostName || "Nishant";
  const sourceName = jamState.sourceName || parsedInvite.sourceName || "Jam Session";
  const inputValue = input || parsedInvite.shareCode;
  const visibleStatusMessage =
    statusMessage ||
    jamState.errorMessage ||
    (parsedInvite.sessionId ? "Joining shared Jam session..." : "");
  const deepLink =
    sessionId && shareCode
      ? buildJamDeepLink({ sessionId, shareCode, hostName, sourceName })
      : `${siteConfig.appDeepLinkScheme}://jam`;
  const inviteUrl =
    sessionId && shareCode
      ? buildJamInviteUrl({ sessionId, shareCode, hostName, sourceName })
      : "";

  return (
    <div suppressHydrationWarning className="min-h-full px-4 md:px-8 py-10 md:py-14 font-spotify">
      <div className="max-w-5xl mx-auto grid lg:grid-cols-[1.2fr_0.8fr] gap-8">
        <section className="rounded-[28px] border border-white/8 bg-gradient-to-br from-[#111111] via-[#161616] to-[#091f1a] p-6 md:p-8 shadow-[0_24px_80px_rgba(0,0,0,0.45)]">
          <div className="inline-flex items-center gap-2 rounded-full bg-white/8 px-3 py-1 text-[11px] uppercase tracking-[0.18em] text-white/70 font-black">
            <span>Jam Connect</span>
          </div>
          <h1 className="mt-5 text-4xl md:text-5xl font-black tracking-tight text-white">
            Join a Svara listening session from the web.
          </h1>
          <p className="mt-4 max-w-2xl text-sm md:text-base leading-7 text-white/70 font-semibold">
            Open a shared invite, paste a session code, or hand the queue off to the Android app. This page is the browser fallback for Jam links, so users never get a dead share URL.
          </p>

          <div className="mt-8 rounded-3xl border border-white/8 bg-black/30 p-5 md:p-6">
            <label htmlFor="jam-code" className="block text-[12px] uppercase tracking-[0.18em] text-white/55 font-black">
              Session code or invite
            </label>
            <div className="mt-3 flex flex-col sm:flex-row gap-3">
              <input
                id="jam-code"
                value={inputValue}
                onChange={(event) => setInput(event.target.value)}
                placeholder="FED94D or full invite URL"
                className="flex-1 rounded-2xl border border-white/8 bg-white/6 px-4 py-4 text-white font-bold outline-none placeholder:text-white/30 focus:border-primary"
              />
              <button
                onClick={joinCurrentInput}
                suppressHydrationWarning
                className="rounded-2xl bg-primary px-6 py-4 text-black font-black uppercase tracking-[0.14em] transition-transform hover:scale-[1.01] active:scale-[0.98]"
              >
                Join on web
              </button>
            </div>

            <div className="mt-4 flex flex-wrap gap-3">
              <a
                href={deepLink}
                suppressHydrationWarning
                className="rounded-full border border-white/12 px-4 py-2.5 text-sm font-bold text-white/85 hover:bg-white/8 transition-colors"
              >
                Open in Android app
              </a>
              {inviteUrl ? (
                <button
                  onClick={async () => {
                    await navigator.clipboard.writeText(inviteUrl);
                    setStatusMessage("Jam invite copied.");
                  }}
                  suppressHydrationWarning
                  className="rounded-full border border-white/12 px-4 py-2.5 text-sm font-bold text-white/85 hover:bg-white/8 transition-colors"
                >
                  Copy invite URL
                </button>
              ) : null}
              {shareCode ? (
                <button
                  onClick={async () => {
                    await navigator.clipboard.writeText(shareCode);
                    setStatusMessage("Session code copied.");
                  }}
                  suppressHydrationWarning
                  className="rounded-full border border-white/12 px-4 py-2.5 text-sm font-bold text-white/85 hover:bg-white/8 transition-colors"
                >
                  Copy code
                </button>
              ) : null}
              {jamState.isActive ? (
                <button
                  onClick={async () => {
                    await jamSyncService.leaveSession();
                    setStatusMessage("Left current Jam session.");
                  }}
                  suppressHydrationWarning
                  className="rounded-full border border-white/12 px-4 py-2.5 text-sm font-bold text-white/85 hover:bg-white/8 transition-colors"
                >
                  Leave Jam
                </button>
              ) : null}
            </div>
          </div>

          {visibleStatusMessage ? (
            <p className="mt-4 text-sm font-bold text-primary">{visibleStatusMessage}</p>
          ) : null}

          <div className="mt-10 grid gap-4 md:grid-cols-3">
            <InfoStat label="Session code" value={shareCode || "Waiting"} />
            <InfoStat label="Host" value={hostName || "Waiting"} />
            <InfoStat label="Listeners" value={`${jamState.participants.length || 1}`} />
          </div>
        </section>

        <aside className="rounded-[28px] border border-white/8 bg-[#101010] p-6 md:p-7 shadow-[0_24px_80px_rgba(0,0,0,0.4)]">
          <h2 className="text-xl font-black text-white">What this page does</h2>
          <div className="mt-5 space-y-4 text-sm leading-7 text-white/70 font-semibold">
            <p>It gives you a valid browser URL for Jam sharing instead of only a custom deep link.</p>
            <p>It can join the same Supabase-backed session code that the Android app uses.</p>
            <p>It also exposes the Android deep link, so a shared URL still has an app-open path when the app is installed.</p>
          </div>

          <div className="mt-8 rounded-3xl border border-white/8 bg-white/[0.03] p-5">
            <div className="text-[11px] uppercase tracking-[0.18em] text-white/45 font-black">
              Active source
            </div>
            <div className="mt-2 text-lg font-black text-white">
              {sourceName}
            </div>
            <div className="mt-4 text-[13px] font-bold text-white/55 leading-6">
              After the host starts playback, the shared queue and transport state flow into the web player through the same room id.
            </div>
          </div>

          <div className="mt-8">
            <Link href="/" className="text-sm font-black text-primary hover:text-white transition-colors">
              Back to home
            </Link>
          </div>
        </aside>
      </div>
    </div>
  );
};

const InfoStat = ({ label, value }: { label: string; value: string }) => (
  <div className="rounded-3xl border border-white/8 bg-white/[0.04] px-5 py-4">
    <div className="text-[11px] uppercase tracking-[0.18em] text-white/40 font-black">{label}</div>
    <div className="mt-2 text-lg font-black text-white break-all">{value}</div>
  </div>
);

export default JamPage;
