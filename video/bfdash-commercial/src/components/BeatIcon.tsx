import React from "react";
import { useCurrentFrame } from "remotion";
import { getIconDrawProgress } from "./BeatIcon.timing";

export type BeatIconType = "sliders" | "grid" | "gauge" | "funnel" | "signal" | "propeller";

interface IconPath {
  d: string;
  length: number;
}

interface IconDef {
  paths: IconPath[];
  dots?: { cx: number; cy: number; r: number }[];
}

// All icons are built from straight line segments (plus filled dots) so each
// path's length is exact, computable geometry -- not an approximation. This
// matters: the stroke "draw-on" effect requires stroke-dasharray to match
// each path's real length, or the reveal is partial/glitchy (arcs and bezier
// curves make that hard to get exactly right, which is why none are used
// here).
const ICONS: Record<BeatIconType, IconDef> = {
  sliders: {
    paths: [
      { d: "M15 35 H85", length: 70 },
      { d: "M40 25 V45", length: 20 },
      { d: "M15 65 H85", length: 70 },
      { d: "M65 55 V75", length: 20 },
    ],
  },
  grid: {
    paths: [
      { d: "M20 20 H80", length: 60 },
      { d: "M20 50 H80", length: 60 },
      { d: "M20 80 H80", length: 60 },
      { d: "M20 20 V80", length: 60 },
      { d: "M50 20 V80", length: 60 },
      { d: "M80 20 V80", length: 60 },
    ],
  },
  gauge: {
    paths: [
      { d: "M20 70 L50 35", length: 46.1 },
      { d: "M50 35 L80 70", length: 46.1 },
      { d: "M50 70 L65 40", length: 33.5 },
    ],
  },
  funnel: {
    paths: [
      { d: "M20 20 L80 20", length: 60 },
      { d: "M20 20 L50 55", length: 46.1 },
      { d: "M80 20 L50 55", length: 46.1 },
      { d: "M50 55 L50 80", length: 25 },
    ],
  },
  signal: {
    paths: [
      { d: "M40 65 L50 55", length: 14.1 },
      { d: "M50 55 L60 65", length: 14.1 },
      { d: "M30 50 L50 30", length: 28.3 },
      { d: "M50 30 L70 50", length: 28.3 },
      { d: "M20 35 L50 5", length: 42.4 },
      { d: "M50 5 L80 35", length: 42.4 },
    ],
    dots: [{ cx: 50, cy: 80, r: 4 }],
  },
  propeller: {
    paths: [
      { d: "M50 20 V80", length: 60 },
      { d: "M20 50 H80", length: 60 },
    ],
    dots: [{ cx: 50, cy: 50, r: 6 }],
  },
};

export const BeatIcon: React.FC<{ icon: BeatIconType }> = ({ icon }) => {
  const frame = useCurrentFrame();
  const progress = getIconDrawProgress(frame);
  const def = ICONS[icon];

  return (
    <div
      style={{
        position: "absolute",
        top: "8%",
        left: "50%",
        transform: "translateX(-50%)",
        width: "14%",
        aspectRatio: "1 / 1",
        opacity: progress,
      }}
    >
      <svg
        viewBox="0 0 100 100"
        style={{
          width: "100%",
          height: "100%",
          color: "#38d6ff",
          filter: "drop-shadow(0 0 12px rgba(56, 214, 255, 0.85))",
        }}
      >
        <g fill="none" stroke="currentColor" strokeWidth={6} strokeLinecap="round" strokeLinejoin="round">
          {def.paths.map((path, i) => (
            <path
              key={i}
              d={path.d}
              style={{
                strokeDasharray: path.length,
                strokeDashoffset: path.length * (1 - progress),
              }}
            />
          ))}
        </g>
        {def.dots?.map((dot, i) => (
          <circle key={i} cx={dot.cx} cy={dot.cy} r={dot.r} fill="currentColor" stroke="none" />
        ))}
      </svg>
    </div>
  );
};
