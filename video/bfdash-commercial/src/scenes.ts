export type SceneType = "hook" | "reveal" | "feature" | "payoff" | "cta" | "outro";
export type RevealVariant = "caption" | "title";
export type BeatIconType = "sliders" | "grid" | "gauge" | "funnel" | "signal" | "propeller";

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
  calloutRect?: CalloutRect;
  revealVariant?: RevealVariant;
  icon?: BeatIconType;
}

export const scenes: Scene[] = [
  {
    id: "hook",
    type: "hook",
    startFrame: 0,
    durationFrames: 180,
    image: "photos/rates.jpg",
    caption: "Tired of tabbing between goggles and Betaflight mid-tune?",
  },
  {
    id: "reveal-caption",
    type: "reveal",
    revealVariant: "caption",
    startFrame: 180,
    durationFrames: 75,
    caption: "So I vibe-coded my own LUA app.",
  },
  {
    id: "reveal-title",
    type: "reveal",
    revealVariant: "title",
    startFrame: 255,
    durationFrames: 105,
    caption: "BFDash",
    subtitle: "Remote Betaflight Configuration Dashboard",
  },
  {
    id: "feature-pids-sliders",
    type: "feature",
    startFrame: 360,
    durationFrames: 113,
    image: "photos/pids.jpg",
    caption: "8 PID tuning sliders — matched to Configurator",
    calloutRect: { xPct: 9, yPct: 40, wPct: 30, hPct: 37 },
    icon: "sliders",
  },
  {
    id: "feature-pids-numbers",
    type: "feature",
    startFrame: 473,
    durationFrames: 112,
    image: "photos/pids.jpg",
    caption: "Live P / I / D / D-Min / FF preview",
    calloutRect: { xPct: 50, yPct: 40, wPct: 44, hPct: 20 },
    icon: "grid",
  },
  {
    id: "feature-rates-data",
    type: "feature",
    startFrame: 585,
    durationFrames: 113,
    image: "photos/rates.jpg",
    caption: "All 4 rate types, every axis",
    calloutRect: { xPct: 6, yPct: 40, wPct: 69, hPct: 26 },
    icon: "gauge",
  },
  {
    id: "feature-filters",
    type: "feature",
    startFrame: 698,
    durationFrames: 112,
    image: "photos/filters-p.jpg",
    caption: "Gyro + D-term filters — global & per-profile",
    calloutRect: { xPct: 9, yPct: 37, wPct: 80, hPct: 30 },
    icon: "funnel",
  },
  {
    id: "feature-vtx",
    type: "feature",
    startFrame: 810,
    durationFrames: 113,
    image: "photos/vtx.jpg",
    caption: "Band, channel, power",
    calloutRect: { xPct: 11, yPct: 34, wPct: 15, hPct: 17 },
    icon: "signal",
  },
  {
    id: "feature-motor",
    type: "feature",
    startFrame: 923,
    durationFrames: 112,
    image: "photos/motor.jpg",
    caption: "Throttle boost, idle, sag comp",
    calloutRect: { xPct: 11, yPct: 34, wPct: 56, hPct: 26 },
    icon: "propeller",
  },
  {
    id: "payoff",
    type: "payoff",
    startFrame: 1035,
    durationFrames: 135,
    image: "photos/motor.jpg",
    caption: "Change it in the field.\nNo goggles. No laptop. No USB.",
  },
  {
    id: "cta",
    type: "cta",
    startFrame: 1170,
    durationFrames: 90,
    image: "photos/motor.jpg",
    caption: "Tested on Jumper T15 & RadioMaster TX15 —\ntry it, tell me what breaks.",
  },
  {
    id: "outro",
    type: "outro",
    startFrame: 1260,
    durationFrames: 90,
    caption: "Subscribe for more FPV\nLink in Bio - Comments Open",
  },
];
