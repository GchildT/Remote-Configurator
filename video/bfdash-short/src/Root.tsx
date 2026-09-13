import React from "react";
import { Composition } from "remotion";
import { BFDashShort } from "./BFDashShort";
import { Thumbnail } from "./Thumbnail";
import { ThumbnailLandscape } from "./ThumbnailLandscape";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="BFDashShort"
        component={BFDashShort}
        durationInFrames={900}
        fps={30}
        width={2160}
        height={3840}
      />
      <Composition
        id="Thumbnail"
        component={Thumbnail}
        durationInFrames={1}
        fps={30}
        width={2160}
        height={3840}
      />
      <Composition
        id="ThumbnailLandscape"
        component={ThumbnailLandscape}
        durationInFrames={1}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
