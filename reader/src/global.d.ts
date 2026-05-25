import type { MirookBridge } from "./types";

declare global {
  interface Window {
    mirook: MirookBridge;
  }
}

export {};
