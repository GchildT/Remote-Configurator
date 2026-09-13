import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import type { CalloutRect } from "../scenes";
import { CalloutBox } from "./CalloutBox";

// The source photos are the full, uncropped, rotated-upright phone photos,
// copied verbatim from video/bfdash-short/public/photos/ (see
// scripts/copy-photos.mjs) -- all five share the same 3840x2880 (4:3, AR
// 1.3333) dimensions. Displayed via "contain" logic inside the left-half box
// (1920x2160, AR 0.8889): since every photo's AR exceeds the box's AR,
// they're all width-constrained under contain -- full width shown,
// letterboxed top/bottom by the same fixed amount. One shared rect covers
// every photo. (This is the same underlying math as the Short's PhotoBeat,
// recomputed for a differently-shaped box: 0.8889/1.3333 = 0.6667, i.e.
// exactly 2/3 -- hence the clean 66.6667/16.6667 split below.)
const PHOTO_DISPLAY_RECT = { left: 0, top: 16.6667, width: 100, height: 66.6667 };

export const SplitBeat: React.FC<{
  image: string;
  durationFrames: number;
  calloutRect?: CalloutRect;
  icon?: React.ReactNode;
  caption: React.ReactNode;
  dim?: boolean;
}> = ({ image, durationFrames, calloutRect, icon, caption, dim = false }) => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: "50%",
          height: "100%",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            left: `${PHOTO_DISPLAY_RECT.left}%`,
            top: `${PHOTO_DISPLAY_RECT.top}%`,
            width: `${PHOTO_DISPLAY_RECT.width}%`,
            height: `${PHOTO_DISPLAY_RECT.height}%`,
          }}
        >
          <Img
            src={staticFile(image)}
            style={{
              width: "100%",
              height: "100%",
              filter: "contrast(1.12) saturate(1.08) brightness(0.92)",
            }}
          />
          {calloutRect && <CalloutBox rect={calloutRect} durationFrames={durationFrames} />}
        </div>
        <AbsoluteFill
          style={{
            background:
              "radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 40%, rgba(0,5,15,0.85) 100%)",
          }}
        />
        {dim && <AbsoluteFill style={{ backgroundColor: "rgba(2, 6, 15, 0.55)" }} />}
      </div>

      <div
        style={{
          position: "absolute",
          left: "50%",
          top: 0,
          width: "50%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 48,
        }}
      >
        {icon}
        {caption}
      </div>
    </AbsoluteFill>
  );
};
