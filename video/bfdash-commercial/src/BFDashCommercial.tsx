import React from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile } from "remotion";
import { scenes } from "./scenes";
import { Caption } from "./components/Caption";
import { BeatIcon } from "./components/BeatIcon";
import { SplitBeat } from "./components/SplitBeat";
import { TitleCard } from "./components/TitleCard";
import { OutroCard } from "./components/OutroCard";

const CAPTION_DELAY_AFTER_ICON = 10;

export const BFDashCommercial: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <Audio
        src={staticFile("audio/hook-track.mp3")}
        volume={(f) =>
          interpolate(f, [1327, 1350], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })
        }
      />
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
          ) : scene.image ? (
            <SplitBeat
              image={scene.image}
              durationFrames={scene.durationFrames}
              calloutRect={scene.calloutRect}
              dim={scene.type === "payoff" || scene.type === "cta"}
              icon={scene.icon ? <BeatIcon icon={scene.icon} /> : undefined}
              caption={
                <Caption
                  text={scene.caption}
                  startFrame={scene.icon ? CAPTION_DELAY_AFTER_ICON : 0}
                />
              }
            />
          ) : null}
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
