import React from "react";
import { AbsoluteFill, Audio, Sequence, staticFile } from "remotion";
import { scenes } from "./scenes";
import { Caption } from "./components/Caption";
import { PhotoBeat } from "./components/PhotoBeat";
import { TitleCard } from "./components/TitleCard";
import { OutroCard } from "./components/OutroCard";

export const BFDashShort: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <Audio src={staticFile("audio/hook-track.mp3")} />
      {scenes.map((scene) => (
        <Sequence key={scene.id} from={scene.startFrame} durationInFrames={scene.durationFrames}>
          {scene.type === "outro" ? (
            <OutroCard caption={scene.caption} />
          ) : scene.type === "reveal" && scene.revealVariant === "title" ? (
            <TitleCard title={scene.caption} subtitle={scene.subtitle ?? ""} />
          ) : scene.type === "reveal" && scene.revealVariant === "caption" ? (
            <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
              <Caption text={scene.caption} startFrame={0} />
            </AbsoluteFill>
          ) : scene.image && scene.focalPoint ? (
            <>
              <PhotoBeat
                image={scene.image}
                durationFrames={scene.durationFrames}
                focalPoint={scene.focalPoint}
                calloutRect={scene.calloutRect}
                dim={scene.type === "payoff" || scene.type === "cta"}
              />
              <Caption text={scene.caption} startFrame={0} />
            </>
          ) : null}
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
