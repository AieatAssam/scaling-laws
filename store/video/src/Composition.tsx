import {AbsoluteFill, Audio, Easing, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig} from "remotion";
import {PIXEL} from "./font";

// Palette from art/palette.hex
const BG = "#0B0E1A";
const BEZEL = "#1E2644";
const CYAN = "#3FD6CF";
const AMBER = "#FFB347";
const TEXT = "#E8E2D0";
const MUTED = "#B9C6D6";

const EASE = Easing.bezier(0.16, 1, 0.3, 1);

// Scene timing in seconds; converted to frames with fps on the JSX nodes.
const SCENES = {
  title: [0, 4],
  lab: [4, 9],
  training: [9, 14],
  research: [14, 19],
  funding: [19, 24],
  hud: [24, 29],
  end: [29, 33],
} as const;

export const PROMO_FRAMES = 33 * 30;

const slideIn = (frame: number, fps: number) =>
  interpolate(frame, [0, 0.4 * fps], [1, 0], {extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE});

const fadeIn = (frame: number, start: number, dur: number) =>
  interpolate(frame, [start, start + dur], [0, 1], {extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE});

const Backdrop: React.FC = () => (
  <AbsoluteFill
    style={{
      background: BG,
      backgroundImage: `linear-gradient(${BEZEL}55 1px, transparent 1px), linear-gradient(90deg, ${BEZEL}55 1px, transparent 1px)`,
      backgroundSize: "96px 96px",
    }}
  />
);

const Title: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{justifyContent: "center", alignItems: "center", fontFamily: PIXEL}}>
      <div
        style={{
          color: AMBER,
          fontSize: 200,
          lineHeight: 1.1,
          textAlign: "center",
          opacity: fadeIn(frame, 0, 0.3 * fps),
          translate: `0px ${interpolate(frame, [0, 0.5 * fps], [40, 0], {extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE})}px`,
        }}
      >
        SCALING
        <br />
        LAWS
      </div>
      <div
        style={{
          marginTop: 48,
          color: MUTED,
          fontSize: 30,
          opacity: fadeIn(frame, 1.2 * fps, 0.5 * fps),
        }}
      >
        A pixel-art idle game about growing an AI lab.
      </div>
    </AbsoluteFill>
  );
};

// Portrait footage in a phone bezel on the right; the caption sits on the left.
const Phone: React.FC<{clip: string}> = ({clip}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <div
      style={{
        position: "absolute",
        left: 1236,
        top: 48,
        width: 564,
        height: 984,
        boxSizing: "border-box",
        padding: 12,
        borderRadius: 36,
        background: BEZEL,
        translate: `${slideIn(frame, fps) * 160}px 0px`,
        opacity: fadeIn(frame, 0, 0.2 * fps),
      }}
    >
      <OffthreadVideo
        src={staticFile(`clips/${clip}.mp4`)}
        style={{width: 540, height: 960, imageRendering: "pixelated", display: "block", borderRadius: 24}}
      />
    </div>
  );
};

// One caption line, visible between two frames of its scene.
const Caption: React.FC<{text: string; from: number; to: number; top?: number}> = ({text, from, to, top = 300}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const local = frame;
  const visible = local >= from && local < to;
  if (!visible) return null;
  const rise = interpolate(local - from, [0, 0.3 * fps], [30, 0], {extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE});
  const bar = interpolate(local - from, [0.2 * fps, 0.7 * fps], [0, 520], {extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE});
  return (
    <div style={{position: "absolute", left: 120, top, fontFamily: PIXEL}}>
      <div
        style={{
          color: TEXT,
          fontSize: 60,
          lineHeight: 1.4,
          whiteSpace: "nowrap",
          opacity: fadeIn(local - from, 0, 0.2 * fps),
          translate: `0px ${rise}px`,
        }}
      >
        {text}
      </div>
      <div style={{height: 8, width: bar, background: CYAN, marginTop: 16}} />
    </div>
  );
};

const PortraitScene: React.FC<{clip: string; captions: {text: string; from: number; to: number; top?: number}[]}> = ({clip, captions}) => {
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill>
      <Backdrop />
      <Phone clip={clip} />
      {captions.map((c) => (
        <Caption key={c.text} text={c.text} from={c.from * fps} to={c.to * fps} top={c.top} />
      ))}
    </AbsoluteFill>
  );
};

const LandscapeScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: BG}}>
      <OffthreadVideo
        src={staticFile("clips/hud.mp4")}
        style={{width: 1920, height: 1080, imageRendering: "pixelated", opacity: fadeIn(frame, 0, 0.3 * fps)}}
      />
    </AbsoluteFill>
  );
};

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: BG}}>
      <Backdrop />
      {/* Positioned wrapper: the Backdrop is absolutely positioned, so bare text would paint underneath it. */}
      <AbsoluteFill style={{justifyContent: "center", alignItems: "center", fontFamily: PIXEL}}>
      <div style={{color: AMBER, fontSize: 140, opacity: fadeIn(frame, 0, 0.4 * fps)}}>SCALING LAWS</div>
      <div style={{color: TEXT, fontSize: 40, marginTop: 56, opacity: fadeIn(frame, 0.6 * fps, 0.4 * fps)}}>
        Play in your browser or on Android.
      </div>
      <div style={{color: CYAN, fontSize: 32, marginTop: 48, opacity: fadeIn(frame, 1.2 * fps, 0.4 * fps)}}>
        github.com/AieatAssam/scaling-laws
      </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const PromoVideo: React.FC = () => {
  const {fps} = useVideoConfig();
  const s = (k: keyof typeof SCENES) => ({from: SCENES[k][0] * fps, durationInFrames: (SCENES[k][1] - SCENES[k][0]) * fps});
  return (
    <AbsoluteFill style={{background: BG}}>
      <Audio
        src={staticFile("music.ogg")}
        volume={(f) => interpolate(f, [0, 20, PROMO_FRAMES - 60, PROMO_FRAMES], [0, 0.9, 0.9, 0], {extrapolateLeft: "clamp", extrapolateRight: "clamp"})}
      />
      <Sequence {...s("title")}>
        <AbsoluteFill>
          <Backdrop />
          <Title />
        </AbsoluteFill>
      </Sequence>
      <Sequence {...s("lab")}>
        <PortraitScene
          clip="lab_fill"
          captions={[
            {text: "Start in a garage.", from: 0, to: 2.4},
            {text: "Buy compute.", from: 2.5, to: 5},
          ]}
        />
      </Sequence>
      <Sequence {...s("training")}>
        <PortraitScene clip="training" captions={[{text: "Train models.", from: 0, to: 5}]} />
      </Sequence>
      <Sequence {...s("research")}>
        <PortraitScene
          clip="research"
          captions={[
            {text: "Publish.", from: 0, to: 2.4},
            {text: "Or don't.", from: 2.5, to: 5},
          ]}
        />
      </Sequence>
      <Sequence {...s("funding")}>
        <PortraitScene
          clip="funding"
          captions={[
            {text: "Raise a round.", from: 0, to: 2.4},
            {text: "Start again,", from: 2.5, to: 3.8, top: 300},
            {text: "stronger.", from: 3.9, to: 5, top: 300},
          ]}
        />
      </Sequence>
      <Sequence {...s("hud")}>
        <LandscapeScene />
      </Sequence>
      <Sequence {...s("end")}>
        <EndCard />
      </Sequence>
    </AbsoluteFill>
  );
};
