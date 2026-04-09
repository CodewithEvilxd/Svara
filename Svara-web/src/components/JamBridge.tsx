"use client";

import { useEffect, useRef } from "react";

import { audioService } from "@/services/AudioService";
import { jamSyncService } from "@/services/jam";
import { usePlayerStore } from "@/store/playerStore";

const JamBridge = () => {
  const { currentSong, currentIndex, currentTime, isPlaying } = usePlayerStore();
  const lastAppliedSnapshotAtRef = useRef(0);

  useEffect(() => {
    jamSyncService.attachPlaybackBridge(
      async () => {
        const state = usePlayerStore.getState();
        if (!state.currentSong || state.currentIndex < 0 || state.queue.length === 0) {
          return null;
        }

        return {
          sessionId: "",
          senderId: "",
          sourceName: state.currentSong.albumName || state.currentSong.album?.name || "Jam Session",
          hostName: "",
          queue: state.queue,
          currentIndex: state.currentIndex,
          positionMs: Math.max(0, Math.floor(state.currentTime * 1000)),
          isPlaying: state.isPlaying,
          sentAtMs: Date.now(),
        };
      },
      async (snapshot) => {
        if (snapshot.sentAtMs && snapshot.sentAtMs < lastAppliedSnapshotAtRef.current) {
          return;
        }

        lastAppliedSnapshotAtRef.current = snapshot.sentAtMs || Date.now();

        const safeIndex = Math.max(0, Math.min(snapshot.currentIndex, snapshot.queue.length - 1));
        const song = snapshot.queue[safeIndex];
        if (!song) {
          return;
        }

        const previousSongId = usePlayerStore.getState().currentSong?.id || "";
        const targetSeconds = snapshot.isPlaying
          ? Math.max(0, snapshot.positionMs / 1000 + (Date.now() - snapshot.sentAtMs) / 1000)
          : Math.max(0, snapshot.positionMs / 1000);

        usePlayerStore.setState({
          originalQueue: [...snapshot.queue],
          queue: [...snapshot.queue],
          currentIndex: safeIndex,
          currentSong: song,
          isPlaying: snapshot.isPlaying,
          currentTime: targetSeconds,
        });

        if (previousSongId !== song.id) {
          const offLoad = audioService.on("load", () => {
            audioService.seek(targetSeconds);
            if (snapshot.isPlaying) {
              audioService.resume();
            } else {
              audioService.pause();
            }
            offLoad();
          });

          await audioService.play(song);
          return;
        }

        audioService.seek(targetSeconds);
        if (snapshot.isPlaying) {
          audioService.resume();
        } else {
          audioService.pause();
        }
      },
      async (request) => {
        const state = usePlayerStore.getState();
        switch (request.action) {
          case "play": {
            const targetSeconds =
              typeof request.positionMs === "number"
                ? Math.max(0, request.positionMs / 1000)
                : state.currentTime;
            audioService.seek(targetSeconds);
            usePlayerStore.setState({ currentTime: targetSeconds });
            audioService.resume();
            return;
          }
          case "pause": {
            const targetSeconds =
              typeof request.positionMs === "number"
                ? Math.max(0, request.positionMs / 1000)
                : state.currentTime;
            audioService.seek(targetSeconds);
            usePlayerStore.setState({ currentTime: targetSeconds, isPlaying: false });
            audioService.pause();
            return;
          }
          case "seek": {
            if (typeof request.positionMs !== "number") {
              return;
            }
            const targetSeconds = Math.max(0, request.positionMs / 1000);
            usePlayerStore.getState().seek(targetSeconds);
            return;
          }
          case "next":
            usePlayerStore.getState().nextSong();
            return;
          case "previous":
            usePlayerStore.getState().prevSong();
            return;
          case "jump": {
            if (typeof request.queueIndex !== "number") {
              return;
            }
            const queueIndex = request.queueIndex;
            const queueSong = state.queue[queueIndex];
            if (!queueSong) {
              return;
            }

            usePlayerStore.setState({
              currentIndex: queueIndex,
              currentSong: queueSong,
              isPlaying: true,
            });
            await audioService.play(queueSong);
            return;
          }
        }
      },
    );

    void jamSyncService.ensureMemberId();
  }, []);

  useEffect(() => {
    if (!currentSong) {
      return;
    }

    void jamSyncService.syncFromPlayback();
  }, [currentSong?.id, currentIndex, isPlaying, Math.floor(currentTime)]);

  return null;
};

export default JamBridge;
