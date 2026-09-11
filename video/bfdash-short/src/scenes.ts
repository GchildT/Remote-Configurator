export type SceneType = "hook" | "reveal" | "feature" | "payoff" | "cta" | "outro";
export type RevealVariant = "caption" | "title";

export interface FocalPoint {
  xPct: number;
  yPct: number;
}

export interface CalloutRect {
  xPct: number;
  yPct: number;
  wPct: number;
  hPct: number;
}

export interface Scene {
  id: string;
  type: SceneType;
  startFrame: number;
  durationFrames: number;
  caption: string;
  subtitle?: string;
  image?: string;
  focalPoint?: FocalPoint;
  calloutRect?: CalloutRect;
  revealVariant?: RevealVariant;
}

export const scenes: Scene[] = [
  {
    id: "hook",
    type: "hook",
    startFrame: 0,
    durationFrames: 120,
    image: "photos/rates.jpg",
    caption: "Tired of tabbing between goggles and Betaflight mid-tune?",
    focalPoint: { xPct: 50, yPct: 50 },
  },
  {
    id: "reveal-caption",
    type: "reveal",
    revealVariant: "caption",
    startFrame: 120,
    durationFrames: 50,
    caption: "So I vibe-coded my own LUA app.",
  },
  {
    id: "reveal-title",
    type: "reveal",
    revealVariant: "title",
    startFrame: 170,
    durationFrames: 70,
    caption: "BFDash",
    subtitle: "Remote Betaflight Configuration Dashboard",
  },
  {
    id: "feature-pids-sliders",
    type: "feature",
    startFrame: 240,
    durationFrames: 75,
    image: "photos/pids.jpg",
    caption: "8 PID tuning sliders — matched to Configurator",
    focalPoint: { xPct: 30, yPct: 50 },
    calloutRect: { xPct: 5, yPct: 20, wPct: 45, hPct: 60 },
  },
  {
    id: "feature-pids-numbers",
    type: "feature",
    startFrame: 315,
    durationFrames: 75,
    image: "photos/pids.jpg",
    caption: "Live P / I / D / D-Min / FF preview",
    focalPoint: { xPct: 72, yPct: 45 },
    calloutRect: { xPct: 50, yPct: 15, wPct: 45, hPct: 70 },
  },
  {
    id: "feature-rates-data",
    type: "feature",
    startFrame: 390,
    durationFrames: 75,
    image: "photos/rates.jpg",
    caption: "All 4 rate types, every axis",
    focalPoint: { xPct: 50, yPct: 65 },
    calloutRect: { xPct: 15, yPct: 45, wPct: 70, hPct: 45 },
  },
  {
    id: "feature-filters",
    type: "feature",
    startFrame: 465,
    durationFrames: 75,
    image: "photos/filters-p.jpg",
    caption: "Gyro + D-term filters — global & per-profile",
    focalPoint: { xPct: 50, yPct: 45 },
    calloutRect: { xPct: 10, yPct: 15, wPct: 80, hPct: 70 },
  },
  {
    id: "feature-vtx",
    type: "feature",
    startFrame: 540,
    durationFrames: 75,
    image: "photos/vtx.jpg",
    caption: "Band, channel, power",
    focalPoint: { xPct: 40, yPct: 70 },
    calloutRect: { xPct: 10, yPct: 60, wPct: 60, hPct: 30 },
  },
  {
    id: "feature-motor",
    type: "feature",
    startFrame: 615,
    durationFrames: 75,
    image: "photos/motor.jpg",
    caption: "Throttle boost, idle, sag comp",
    focalPoint: { xPct: 50, yPct: 45 },
    calloutRect: { xPct: 10, yPct: 25, wPct: 80, hPct: 55 },
  },
  {
    id: "payoff",
    type: "payoff",
    startFrame: 690,
    durationFrames: 90,
    image: "photos/motor.jpg",
    caption: "Change it in the field.\nNo goggles. No laptop. No USB.",
    focalPoint: { xPct: 50, yPct: 45 },
  },
  {
    id: "cta",
    type: "cta",
    startFrame: 780,
    durationFrames: 60,
    image: "photos/motor.jpg",
    caption: "Tested on Jumper T15 & RadioMaster TX15 — try it, tell me what breaks.",
    focalPoint: { xPct: 50, yPct: 45 },
  },
  {
    id: "outro",
    type: "outro",
    startFrame: 840,
    durationFrames: 60,
    caption: "Subscribe for more FPV builds & tuning\nLink in bio · comments open",
  },
];
