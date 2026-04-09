"use client";

import { create } from "zustand";

export interface JamParticipant {
  memberId: string;
  displayName: string;
  isHost: boolean;
}

export interface JamSessionState {
  isActive: boolean;
  isHost: boolean;
  sessionId: string;
  shareCode: string;
  sourceName: string;
  hostName: string;
  errorMessage: string;
  participants: JamParticipant[];
}

export const emptyJamState: JamSessionState = {
  isActive: false,
  isHost: false,
  sessionId: "",
  shareCode: "",
  sourceName: "",
  hostName: "",
  errorMessage: "",
  participants: [],
};

interface JamStoreState extends JamSessionState {
  setJamState: (state: Partial<JamSessionState>) => void;
  resetJamState: () => void;
}

export const useJamStore = create<JamStoreState>((set) => ({
  ...emptyJamState,
  setJamState: (state) => set((current) => ({ ...current, ...state })),
  resetJamState: () => set(emptyJamState),
}));
