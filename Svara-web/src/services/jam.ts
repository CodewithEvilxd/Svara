"use client";

import { RealtimeChannel, SupabaseClient, createClient } from "@supabase/supabase-js";

import { siteConfig, buildAbsoluteSiteUrl } from "@/config/site";
import { SongDetail, SourceUrl } from "@/types";
import { JamParticipant, JamSessionState, useJamStore } from "@/store/jamStore";

declare global {
  interface Window {
    __svaraSupabaseClient?: SupabaseClient;
  }
}

export interface JamSyncSnapshot {
  sessionId: string;
  senderId: string;
  sourceName: string;
  hostName: string;
  queue: SongDetail[];
  currentIndex: number;
  positionMs: number;
  isPlaying: boolean;
  sentAtMs: number;
}

export interface JamControlRequest {
  sessionId: string;
  senderId: string;
  action: string;
  positionMs?: number;
  queueIndex?: number;
  sentAtMs: number;
}

interface PresencePayload {
  memberId?: string;
  name?: string;
  isHost?: boolean;
  joinedAt?: string;
}

type SnapshotBuilder = () => Promise<JamSyncSnapshot | null>;
type RemoteApplier = (snapshot: JamSyncSnapshot) => Promise<void>;
type ControlRequestHandler = (request: JamControlRequest) => Promise<void>;

const supabase =
  typeof window !== "undefined" && window.__svaraSupabaseClient
    ? window.__svaraSupabaseClient
    : createClient(siteConfig.supabaseUrl, siteConfig.supabaseAnonKey, {
        auth: {
          // Jam sync uses anonymous realtime channels and should not create/persist auth sessions.
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      });

if (typeof window !== "undefined") {
  window.__svaraSupabaseClient = supabase;
}
const memberStorageKey = "svara-jam-member-id";
const memberSessionStorageKey = "svara-jam-tab-member-id";

const readStoredMemberId = () => {
  if (typeof window === "undefined") {
    return "";
  }

  const fromSession = window.sessionStorage.getItem(memberSessionStorageKey)?.trim() || "";
  if (fromSession) {
    return fromSession;
  }

  const legacyLocal = window.localStorage.getItem(memberStorageKey)?.trim() || "";
  return legacyLocal;
};

const persistMemberId = (memberId: string) => {
  if (typeof window === "undefined") {
    return;
  }

  window.sessionStorage.setItem(memberSessionStorageKey, memberId);
};

const normalizeSourceList = (rawValue: unknown): SourceUrl[] => {
  if (!Array.isArray(rawValue)) {
    return [];
  }

  return rawValue
    .map((item) => {
      if (!item || typeof item !== "object") {
        return null;
      }

      const source = item as Record<string, unknown>;
      const url = `${source.url ?? source.link ?? ""}`.trim();
      if (!url) {
        return null;
      }

      return {
        quality: `${source.quality ?? "default"}`.trim() || "default",
        url,
      } satisfies SourceUrl;
    })
    .filter((item): item is SourceUrl => Boolean(item));
};

type SongArtistSource = Partial<SongDetail> & {
  primaryArtists?: unknown;
  artist?: unknown;
  artists?: unknown;
};

const artistNameForSong = (song: SongArtistSource) => {
  const primaryArtists = song.primaryArtists;
  if (typeof primaryArtists === "string" && primaryArtists.trim()) {
    return primaryArtists.trim();
  }

  const artist = song.artist;
  if (typeof artist === "string" && artist.trim()) {
    return artist.trim();
  }

  const artists = song.artists as Record<string, unknown> | undefined;
  const primary = Array.isArray(artists?.primary) ? artists?.primary : [];
  const artistNames = primary
    .map((entry) => {
      if (!entry || typeof entry !== "object") {
        return "";
      }
      const record = entry as Record<string, unknown>;
      return `${record.name ?? record.title ?? ""}`.trim();
    })
    .filter(Boolean);

  return artistNames.join(", ");
};

const normalizeJamSong = (rawValue: unknown): SongDetail | null => {
  if (!rawValue || typeof rawValue !== "object") {
    return null;
  }

  const rawSong = rawValue as Record<string, unknown>;
  const images = normalizeSourceList(rawSong.images ?? rawSong.image);
  const downloadUrls = normalizeSourceList(rawSong.downloadUrls ?? rawSong.downloadUrl);
  const artistName = artistNameForSong(rawSong);
  const album =
    typeof rawSong.album === "object" && rawSong.album !== null
      ? (rawSong.album as Record<string, unknown>)
      : { name: rawSong.albumName ?? rawSong.album ?? "" };

  const normalized: SongDetail = {
    id: `${rawSong.id ?? ""}`,
    name: `${rawSong.name ?? rawSong.title ?? "Unknown Track"}`,
    title: `${rawSong.title ?? rawSong.name ?? "Unknown Track"}`,
    type: `${rawSong.type ?? "song"}`,
    url: `${rawSong.url ?? ""}`,
    image: images,
    images,
    label: typeof rawSong.label === "string" ? rawSong.label : undefined,
    description: `${rawSong.description ?? ""}`,
    language: typeof rawSong.language === "string" ? rawSong.language : undefined,
    year:
      typeof rawSong.year === "number" || typeof rawSong.year === "string"
        ? rawSong.year
        : null,
    explicitContent: Boolean(rawSong.explicitContent),
    playCount:
      typeof rawSong.playCount === "number" || typeof rawSong.playCount === "string"
        ? rawSong.playCount
        : null,
    album: {
      id: album.id ? `${album.id}` : null,
      name: album.name ? `${album.name}` : `${rawSong.albumName ?? ""}` || null,
      url: album.url ? `${album.url}` : null,
    },
    artists:
      (rawSong.artists as SongDetail["artists"]) || {
        primary:
          artistName
            .split(",")
            .map((name) => name.trim())
            .filter(Boolean)
            .map((name, index) => ({
              id: `${rawSong.id ?? "artist"}-${index}`,
              name,
              role: "artist",
              type: "artist",
              image: [],
              url: "",
            })) || [],
        featured: [],
        all:
          artistName
            .split(",")
            .map((name) => name.trim())
            .filter(Boolean)
            .map((name, index) => ({
              id: `${rawSong.id ?? "artist"}-${index}`,
              name,
              role: "artist",
              type: "artist",
              image: [],
              url: "",
            })) || [],
      },
    duration:
      typeof rawSong.duration === "number"
        ? rawSong.duration
        : Number.parseInt(`${rawSong.duration ?? 0}`, 10) || 0,
    releaseDate: `${rawSong.releaseDate ?? ""}` || null,
    hasLyrics: Boolean(rawSong.hasLyrics ?? rawSong.lyricsId),
    lyricsId: rawSong.lyricsId ? `${rawSong.lyricsId}` : null,
    copyright: rawSong.copyright ? `${rawSong.copyright}` : null,
    downloadUrl: downloadUrls,
    downloadUrls,
    artist: artistName,
    albumName: `${album.name ?? rawSong.albumName ?? ""}`,
  };

  return normalized;
};

const serializeSongForJam = (song: SongDetail) => ({
  id: song.id,
  title: song.title || song.name,
  name: song.name || song.title,
  type: song.type,
  url: song.url,
  description: song.description || "",
  language: song.language || "",
  album: song.album,
  albumName: song.albumName || song.album?.name || "",
  primaryArtists: song.artist || artistNameForSong(song),
  year: song.year,
  releaseDate: song.releaseDate,
  duration: song.duration,
  explicitContent: song.explicitContent,
  image: song.images || song.image || [],
  downloadUrl: song.downloadUrls || song.downloadUrl || [],
  artists: song.artists,
});

export const normalizeJamSessionId = (rawValue: string) => {
  const trimmed = rawValue.trim();
  if (!trimmed) {
    return "";
  }

  if (trimmed.toLowerCase().startsWith("jam-")) {
    return `jam-${trimmed.slice(4).replace(/[^a-zA-Z0-9-]/g, "").toLowerCase()}`;
  }

  const code = trimmed.replace(/[^a-zA-Z0-9]/g, "").toUpperCase();
  if (!code) {
    return "";
  }

  return `jam-${code.slice(-6).toLowerCase()}`;
};

export const shareCodeForSession = (sessionId: string) =>
  normalizeJamSessionId(sessionId).replace(/^jam-/, "").slice(-6).toUpperCase();

export const buildJamDeepLink = (input: {
  sessionId: string;
  shareCode: string;
  sourceName?: string;
  hostName?: string;
}) => {
  const params = new URLSearchParams({
    session: input.sessionId,
    code: input.shareCode,
  });

  if (input.sourceName?.trim()) {
    params.set("source", input.sourceName.trim());
  }
  if (input.hostName?.trim()) {
    params.set("hostName", input.hostName.trim());
  }

  return `${siteConfig.appDeepLinkScheme}://jam?${params.toString()}`;
};

export const buildJamInviteUrl = (input: {
  sessionId: string;
  shareCode: string;
  sourceName?: string;
  hostName?: string;
}) => {
  const url = new URL(buildAbsoluteSiteUrl(siteConfig.jamPath));
  url.searchParams.set(siteConfig.jamInviteQueryParam, input.shareCode);
  url.searchParams.set("session", input.sessionId);

  if (input.sourceName?.trim()) {
    url.searchParams.set("source", input.sourceName.trim());
  }
  if (input.hostName?.trim()) {
    url.searchParams.set("hostName", input.hostName.trim());
  }

  return url.toString();
};

export const parseJamInvite = (input: URLSearchParams | string | URL) => {
  const url =
    input instanceof URL
      ? input
      : input instanceof URLSearchParams
        ? new URL(`${siteConfig.siteUrl}${siteConfig.jamPath}?${input.toString()}`)
        : new URL(input, siteConfig.siteUrl);

  const shareCode =
    url.searchParams.get(siteConfig.jamInviteQueryParam)?.trim().toUpperCase() ||
    url.searchParams.get("code")?.trim().toUpperCase() ||
    "";
  const sessionId = normalizeJamSessionId(
    url.searchParams.get("session") || shareCode,
  );

  return {
    shareCode: shareCode || shareCodeForSession(sessionId),
    sessionId,
    sourceName: url.searchParams.get("source")?.trim() || "",
    hostName: url.searchParams.get("hostName")?.trim() || "",
  };
};

class JamSyncService {
  private channel: RealtimeChannel | null = null;
  private memberId = "";
  private sessionId = "";
  private sourceName = "";
  private isHost = false;
  private initialSnapshotReceived = false;
  private snapshotBuilder: SnapshotBuilder | null = null;
  private remoteApplier: RemoteApplier | null = null;
  private controlRequestHandler: ControlRequestHandler | null = null;
  private syncTimer: number | null = null;

  get isActive() {
    return Boolean(this.sessionId && this.channel);
  }

  get isHostSession() {
    return this.isHost;
  }

  attachPlaybackBridge(
    snapshotBuilder: SnapshotBuilder,
    remoteApplier: RemoteApplier,
    controlRequestHandler: ControlRequestHandler,
  ) {
    this.snapshotBuilder = snapshotBuilder;
    this.remoteApplier = remoteApplier;
    this.controlRequestHandler = controlRequestHandler;
  }

  async ensureMemberId() {
    if (this.memberId) {
      return;
    }

    if (typeof window === "undefined") {
      return;
    }

    const cached = readStoredMemberId();
    if (cached) {
      this.memberId = cached;
      persistMemberId(cached);
      return;
    }

    const generated = `${Date.now()}${Math.random().toString(16).slice(2, 8)}`;
    this.memberId = generated;
    persistMemberId(generated);
  }

  async startSession(sourceName?: string) {
    await this.ensureMemberId();

    if (this.isActive && this.isHost) {
      this.sourceName = sourceName || this.sourceName;
      await this.syncFromPlayback(true);
      return this.sessionId;
    }

    await this.leaveSession();

    this.sessionId = `jam-${Math.floor(Math.random() * 0xffffff)
      .toString(16)
      .padStart(6, "0")}`;
    this.sourceName = sourceName || "Jam Session";
    this.isHost = true;
    this.initialSnapshotReceived = true;

    try {
      await this.subscribeToSession(this.sessionId);
      await this.syncFromPlayback(true);
      return this.sessionId;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unable to start Jam.";
      this.setConnectionError(message);
      throw error;
    }
  }

  async joinSession(sessionOrCode: string) {
    const normalizedSessionId = normalizeJamSessionId(sessionOrCode);
    if (!normalizedSessionId) {
      return;
    }

    await this.ensureMemberId();
    if (this.isActive && this.sessionId === normalizedSessionId) {
      return;
    }

    await this.leaveSession();

    this.sessionId = normalizedSessionId;
    this.sourceName = "Jam Session";
    this.isHost = false;
    this.initialSnapshotReceived = false;

    try {
      await this.subscribeToSession(this.sessionId);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unable to join Jam.";
      this.setConnectionError(message);
      throw error;
    }
  }

  async leaveSession() {
    if (this.syncTimer) {
      clearTimeout(this.syncTimer);
      this.syncTimer = null;
    }

    if (this.channel) {
      try {
        await this.channel.untrack();
      } catch {}
      await supabase.removeChannel(this.channel);
      this.channel = null;
    }

    this.sessionId = "";
    this.sourceName = "";
    this.isHost = false;
    this.initialSnapshotReceived = false;
    useJamStore.getState().resetJamState();
  }

  async syncFromPlayback(force = false) {
    if (!this.isActive) {
      return;
    }

    if (!this.isHost) {
      return;
    }

    if (force) {
      await this.broadcastCurrentSnapshot();
      return;
    }

    if (this.syncTimer) {
      clearTimeout(this.syncTimer);
    }

    this.syncTimer = window.setTimeout(() => {
      void this.broadcastCurrentSnapshot();
    }, 280);
  }

  async sendControlRequest(
    action: string,
    options?: {
      positionMs?: number;
      queueIndex?: number;
    },
  ) {
    if (!this.channel || !this.isActive) {
      return;
    }

    const normalizedAction = action.trim().toLowerCase();
    if (!normalizedAction) {
      return;
    }

    await this.sendBroadcast("control_request", {
      sessionId: this.sessionId,
      senderId: this.memberId,
      action: normalizedAction,
      ...(typeof options?.positionMs === "number" ? { positionMs: options.positionMs } : {}),
      ...(typeof options?.queueIndex === "number" ? { queueIndex: options.queueIndex } : {}),
      sentAtMs: Date.now(),
    });
  }

  private async subscribeToSession(sessionId: string) {
    const topic = `jam:${sessionId}`;

    // With a shared Supabase client (and Fast Refresh), an old joined channel can be reused.
    // Presence callbacks must be registered before subscribe, so remove stale topic channels first.
    const staleChannels = supabase
      .getChannels()
      .filter(
        (existingChannel) =>
          existingChannel.topic === `realtime:${topic}` || existingChannel.topic === topic,
      );

    for (const staleChannel of staleChannels) {
      await supabase.removeChannel(staleChannel);
    }

    let channel = supabase.channel(topic);

    try {
      this.bindChannelHandlers(channel);
    } catch {
      // If a pre-subscribed channel slips through (Fast Refresh race), recreate from a clean slate.
      await supabase.removeAllChannels();
      channel = supabase.channel(topic);
      this.bindChannelHandlers(channel);
    }

    this.channel = channel;

    await new Promise<void>((resolve, reject) => {
      channel.subscribe(async (status, error) => {
        if (status === "SUBSCRIBED") {
          await channel.track(this.presencePayload());
          this.refreshParticipants();
          if (this.isHost) {
            await this.broadcastCurrentSnapshot();
          } else {
            await this.requestCurrentSnapshot();
          }
          resolve();
        }

        if (
          (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") &&
          error
        ) {
          reject(new Error(error.message || "Unable to connect to Jam"));
        }
      });
    });
  }

  private bindChannelHandlers(channel: RealtimeChannel) {
    channel
      .on("broadcast", { event: "request_state" }, ({ payload }) => {
        void this.handleStateRequest(payload as Record<string, unknown>);
      })
      .on("broadcast", { event: "session_state" }, ({ payload }) => {
        void this.handleSessionState(payload as Record<string, unknown>);
      })
      .on("broadcast", { event: "control_request" }, ({ payload }) => {
        void this.handleControlRequest(payload as Record<string, unknown>);
      })
      .on("presence", { event: "sync" }, () => this.refreshParticipants())
      .on("presence", { event: "join" }, () => this.refreshParticipants())
      .on("presence", { event: "leave" }, () => this.refreshParticipants());
  }

  private async requestCurrentSnapshot() {
    if (!this.channel) {
      return;
    }

    await this.sendBroadcast("request_state", {
      targetMemberId: this.memberId,
    });
  }

  private async sendBroadcast(event: string, payload: Record<string, unknown>) {
    if (!this.channel) {
      return;
    }

    const safePayload = payload ?? {};

    const channelWithHttp = this.channel as RealtimeChannel & {
      httpSend?: (event: string, payload: Record<string, unknown>) => Promise<unknown>;
    };

    if (typeof channelWithHttp.httpSend === "function") {
      try {
        await channelWithHttp.httpSend(event, safePayload);
        return;
      } catch (error) {
        // Keep broadcast functional even if the REST helper rejects in edge cases.
        console.warn("Jam httpSend failed, retrying with websocket send", error);
      }
    }

    await this.channel.send({
      type: "broadcast",
      event,
      payload: safePayload,
    });
  }

  private async handleStateRequest(payload: Record<string, unknown>) {
    const targetMemberId = `${payload.targetMemberId ?? ""}`.trim();
    if (!targetMemberId || targetMemberId === this.memberId) {
      return;
    }

    if (!this.shouldReplyWithSnapshot()) {
      return;
    }

    await this.broadcastCurrentSnapshot(targetMemberId);
  }

  private async handleSessionState(payload: Record<string, unknown>) {
    const targetMemberId = `${payload.targetMemberId ?? ""}`.trim();
    if (targetMemberId && targetMemberId !== this.memberId) {
      return;
    }

    const snapshot = this.snapshotFromPayload(payload);
    if (!snapshot || snapshot.senderId === this.memberId || snapshot.queue.length === 0) {
      return;
    }

    this.initialSnapshotReceived = true;
    this.sourceName = snapshot.sourceName;
    useJamStore.getState().setJamState({
      isActive: true,
      isHost: this.isHost,
      sessionId: this.sessionId,
      shareCode: shareCodeForSession(this.sessionId),
      sourceName: snapshot.sourceName,
      hostName: snapshot.hostName,
      errorMessage: "",
    });

    if (this.remoteApplier) {
      await this.remoteApplier(snapshot);
    }
  }

  private async handleControlRequest(payload: Record<string, unknown>) {
    const request = this.controlRequestFromPayload(payload);
    if (
      !request ||
      !this.isHost ||
      request.senderId === this.memberId ||
      !this.controlRequestHandler
    ) {
      return;
    }

    await this.controlRequestHandler(request);
  }

  private snapshotFromPayload(payload: Record<string, unknown>) {
    const rawQueue = Array.isArray(payload.queue) ? payload.queue : [];
    const queue = rawQueue.map(normalizeJamSong).filter((song): song is SongDetail => Boolean(song));

    if (!queue.length) {
      return null;
    }

    return {
      sessionId: `${payload.sessionId ?? ""}`,
      senderId: `${payload.senderId ?? ""}`,
      sourceName: `${payload.sourceName ?? ""}`,
      hostName: `${payload.hostName ?? ""}`,
      queue,
      currentIndex: Number.parseInt(`${payload.currentIndex ?? 0}`, 10) || 0,
      positionMs: Number.parseInt(`${payload.positionMs ?? 0}`, 10) || 0,
      isPlaying: payload.isPlaying === true,
      sentAtMs: Number.parseInt(`${payload.sentAtMs ?? 0}`, 10) || 0,
    } satisfies JamSyncSnapshot;
  }

  private controlRequestFromPayload(payload: Record<string, unknown>) {
    const action = `${payload.action ?? ""}`.trim().toLowerCase();
    if (!action) {
      return null;
    }

    const positionMs =
      typeof payload.positionMs === "number"
        ? payload.positionMs
        : Number.parseInt(`${payload.positionMs ?? ""}`, 10);
    const queueIndex =
      typeof payload.queueIndex === "number"
        ? payload.queueIndex
        : Number.parseInt(`${payload.queueIndex ?? ""}`, 10);

    return {
      sessionId: `${payload.sessionId ?? ""}`,
      senderId: `${payload.senderId ?? ""}`,
      action,
      ...(Number.isFinite(positionMs) ? { positionMs } : {}),
      ...(Number.isFinite(queueIndex) ? { queueIndex } : {}),
      sentAtMs: Number.parseInt(`${payload.sentAtMs ?? 0}`, 10) || 0,
    } satisfies JamControlRequest;
  }

  private async broadcastCurrentSnapshot(targetMemberId?: string) {
    if (!this.channel || !this.snapshotBuilder) {
      return;
    }

    const snapshot = await this.snapshotBuilder();
    if (!snapshot || snapshot.queue.length === 0) {
      return;
    }

    const hostName = (typeof window !== "undefined" ? window.localStorage.getItem("svara-display-name") : "") || "Nishant";
    const outgoing = {
      sessionId: this.sessionId,
      senderId: this.memberId,
      sourceName: snapshot.sourceName || this.sourceName || "Jam Session",
      hostName,
      currentIndex: snapshot.currentIndex,
      positionMs: snapshot.positionMs,
      isPlaying: snapshot.isPlaying,
      sentAtMs: Date.now(),
      queue: snapshot.queue.map(serializeSongForJam),
      ...(targetMemberId ? { targetMemberId } : {}),
    };

    this.sourceName = outgoing.sourceName;
    useJamStore.getState().setJamState({
      isActive: true,
      isHost: this.isHost,
      sessionId: this.sessionId,
      shareCode: shareCodeForSession(this.sessionId),
      sourceName: outgoing.sourceName,
      hostName: outgoing.hostName,
      errorMessage: "",
    });

    await this.sendBroadcast("session_state", outgoing);
  }

  private refreshParticipants() {
    if (!this.channel) {
      return;
    }

    const state = this.channel.presenceState<PresencePayload>();
    const participants: JamParticipant[] = [];

    for (const [presenceKey, presences] of Object.entries(state)) {
      for (const presence of presences) {
        const payload = presence as PresencePayload;
        participants.push({
          memberId: `${payload.memberId || presenceKey}`,
          displayName: `${payload.name || "Listener"}`,
          isHost: payload.isHost === true,
        });
      }
    }

    participants.sort((left, right) => {
      if (left.isHost === right.isHost) {
        return left.displayName.localeCompare(right.displayName);
      }
      return left.isHost ? -1 : 1;
    });

    const hostName = participants.find((participant) => participant.isHost)?.displayName || "";
    useJamStore.getState().setJamState({
      isActive: this.isActive,
      isHost: this.isHost,
      sessionId: this.sessionId,
      shareCode: shareCodeForSession(this.sessionId),
      sourceName: this.sourceName,
      hostName,
      participants,
      errorMessage: "",
    });

    if (!this.initialSnapshotReceived && !this.isHost && participants.length > 0) {
      void this.requestCurrentSnapshot();
    }
  }

  private shouldReplyWithSnapshot() {
    const state: JamSessionState = useJamStore.getState();
    const hasHost = state.participants.some((participant) => participant.isHost);
    return this.isHost || !hasHost;
  }

  private presencePayload() {
    return {
      memberId: this.memberId,
      name:
        (typeof window !== "undefined" ? window.localStorage.getItem("svara-display-name") : "") ||
        "Nishant",
      isHost: this.isHost,
      joinedAt: new Date().toISOString(),
    };
  }

  private setConnectionError(message: string) {
    useJamStore.getState().setJamState({
      isActive: false,
      isHost: false,
      sessionId: "",
      shareCode: "",
      sourceName: this.sourceName,
      hostName: "",
      participants: [],
      errorMessage: message,
    });
  }
}

export const jamSyncService = new JamSyncService();
