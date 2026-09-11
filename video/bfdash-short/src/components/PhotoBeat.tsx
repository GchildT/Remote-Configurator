import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import type { CalloutRect } from "../scenes";
import { CalloutBox } from "./CalloutBox";

// The source photos are the full, uncropped, rotated-upright phone photos
// (see scripts/prepare-photos.mjs) -- all six share the same 3840x2880 (4:3,
// AR 1.3333) dimensions. Displayed via "contain" logic inside the bottom-half
// box (2160x1920, AR 1.125): since every photo's AR exceeds the box's AR,
// they're all width-constrained under contain -- full width shown, letterboxed
// top/bottom by the same fixed amount. One shared rect covers every photo.
const PHOTO_DISPLAY_RECT = { left: 0, top: 7.8125, width: 100, height: 84.375 };

export const PhotoBeat: React.FC<{
  image: string;
  durationFrames: number;
  calloutRect?: CalloutRect;
  dim?: boolean;
}> = ({ image, durationFrames, calloutRect, dim = false }) => {
  const displayRect = PHOTO_DISPLAY_RECT;

  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: 0,
          width: "100%",
          height: "50%",
          overflow: "hidden",
        }}
      >
        {displayRect && (
          <div
            style={{
              position: "absolute",
              left: `${displayRect.left}%`,
              top: `${displayRect.top}%`,
              width: `${displayRect.width}%`,
              height: `${displayRect.height}%`,
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
        )}
        <AbsoluteFill
          style={{
            background:
              "radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 40%, rgba(0,5,15,0.85) 100%)",
          }}
        />
        {dim && (
          <AbsoluteFill style={{ backgroundColor: "rgba(2, 6, 15, 0.55)" }} />
        )}
      </div>
    </AbsoluteFill>
  );
};
