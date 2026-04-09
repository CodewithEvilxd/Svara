'use client';

import { useEffect } from 'react';
import { usePlayerStore } from '@/store/playerStore';
import { audioService } from '@/services/AudioService';
import { jamSyncService } from '@/services/jam';
import { SourceUrl } from '@/types';
import { useJamStore } from '@/store/jamStore';

export default function AudioController() {
  const { 
    currentSong, 
    nextSong, 
    setProgress, 
    setDuration, 
    setPlaying
  } = usePlayerStore();
  const jamState = useJamStore();

  useEffect(() => {
    const offProgress = audioService.on('progress', (time: number) => setProgress(time));
    const offLoad = audioService.on('load', (duration: number) => setDuration(duration));
    const offPlay = audioService.on('play', () => setPlaying(true));
    const offPause = audioService.on('pause', () => setPlaying(false));
    const offEnd = audioService.on('end', () => {
      if (!jamState.isActive || jamState.isHost) {
        nextSong();
        return;
      }

      setPlaying(false);
    });
    const offError = audioService.on('error', (err: any) => {
      const message = `${err ?? ''}`.toLowerCase();
      const isAutoplayBlocked =
        message.includes('playback was unable to start') ||
        message.includes('notallowederror') ||
        message.includes('user interaction');

      if (!isAutoplayBlocked) {
        console.error('[AudioController] Playback error:', err);
      }
      setPlaying(false);
    });

    return () => {
      offProgress();
      offLoad();
      offPlay();
      offPause();
      offEnd();
      offError();
    };
  }, [currentSong, jamState.isActive, jamState.isHost, setProgress, setDuration, setPlaying, nextSong]);

  useEffect(() => {
    if (!currentSong) return;

    if ('mediaSession' in navigator) {
      const routeJamControl = (action: "play" | "pause" | "previous" | "next" | "seek", seekTime?: number) => {
        if (!jamState.isActive || jamState.isHost) {
          return false;
        }

        void jamSyncService.sendControlRequest(action, {
          ...(typeof seekTime === "number"
            ? { positionMs: Math.max(0, Math.floor(seekTime * 1000)) }
            : {}),
        });
        return true;
      };

      navigator.mediaSession.metadata = new MediaMetadata({
        title: currentSong.title || '',
        artist: currentSong.artist || 'Unknown Artist',
        album: (typeof currentSong.album === 'object' ? currentSong.album?.name : currentSong.album) || '',
        artwork: currentSong.images ? currentSong.images.map((img: SourceUrl) => ({
          src: img.url,
          sizes: '500x500', 
          type: 'image/jpeg'
        })) : []
      });

      navigator.mediaSession.setActionHandler('play', () => {
        if (routeJamControl('play', audioService.getCurrentTime())) {
          return;
        }
        audioService.resume();
      });
      navigator.mediaSession.setActionHandler('pause', () => {
        if (routeJamControl('pause', audioService.getCurrentTime())) {
          return;
        }
        audioService.pause();
      });
      navigator.mediaSession.setActionHandler('previoustrack', () => {
        if (routeJamControl('previous')) {
          return;
        }
        usePlayerStore.getState().prevSong();
      });
      navigator.mediaSession.setActionHandler('nexttrack', () => {
        if (routeJamControl('next')) {
          return;
        }
        usePlayerStore.getState().nextSong();
      });
      navigator.mediaSession.setActionHandler('seekto', (details) => {
        if (details.seekTime !== undefined) {
          if (routeJamControl('seek', details.seekTime)) {
            return;
          }
          audioService.seek(details.seekTime);
        }
      });
    }
  }, [currentSong, jamState.isActive, jamState.isHost]);

  return null; // No hidden <audio> tag needed anymore!
}
