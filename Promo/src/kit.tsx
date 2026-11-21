import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

export const FONT =
  '"Cabinet Grotesk", -apple-system, "SF Pro Display", "PingFang SC", "Hiragino Sans GB", "Helvetica Neue", sans-serif';
export const MONO = '"SF Mono", ui-monospace, Menlo, monospace';

export const C = {
  bg: "#090B10",
  text: "#F5F6FA",
  dim: "rgba(232,236,246,0.68)",
  faint: "rgba(232,236,246,0.44)",
  water1: "#93BCFF",
  water2: "#86E5D4",
  hair: "rgba(255,255,255,0.14)",
};

export const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

export const pad3 = (n: number) => String(n).padStart(3, "0");

export const useTime = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  return { frame, fps, t: frame / fps, dur: durationInFrames / fps };
};

export const ease = Easing.bezier(0.22, 1, 0.36, 1);

export const fadeIO = (t: number, dur: number, inS = 0.35, outS = 0.35) =>
  Math.min(
    interpolate(t, [0, inS], [0, 1], clamp),
    interpolate(t, [dur - outS, dur], [1, 0], clamp),
  );

export const useSpringAt = (delay: number, damping = 18, mass = 0.9, stiffness = 120) => {
  const { frame, fps } = useTime();
  return spring({
    frame: frame - Math.round(delay * fps),
    fps,
    config: { damping, mass, stiffness },
  });
};

export type PaintingKey = "monet" | "yosemite" | "judith" | "twilight" | "fuji";

const PAINTING_FILES: Record<PaintingKey, string> = {
  monet: "paintings/monet-water-lilies.jpg",
  yosemite: "paintings/bierstadt-yosemite.jpg",
  judith: "paintings/heade-point-judith.jpg",
  twilight: "paintings/church-twilight.jpg",
  fuji: "paintings/hokusai-red-fuji.jpg",
};

export const Wallpaper: React.FC<{ dim?: number; zoom?: number; painting?: PaintingKey }> = ({
  dim = 0.25,
  zoom = 1.045,
  painting = "judith",
}) => {
  const { t, dur } = useTime();
  const s = interpolate(t, [0, dur], [zoom, 1.0], clamp);
  return (
    <AbsoluteFill style={{ backgroundColor: C.bg, overflow: "hidden" }}>
      <Img
        src={staticFile(PAINTING_FILES[painting])}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          transform: `scale(${s})`,
          filter: "contrast(1.06) saturate(1.06)",
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(ellipse at 50% 45%, rgba(6,8,14,0.04) 36%, rgba(6,8,14,0.58) 100%)",
        }}
      />
      {dim > 0 && <AbsoluteFill style={{ backgroundColor: `rgba(6,8,14,${dim})` }} />}
    </AbsoluteFill>
  );
};

export const Reveal: React.FC<{
  text: string;
  delay: number;
  size: number;
  weight?: number;
  color?: string;
  stagger?: number;
  letterSpacing?: number;
  gradient?: boolean;
  align?: "left" | "center";
}> = ({
  text,
  delay,
  size,
  weight = 600,
  color = C.text,
  stagger = 0.04,
  letterSpacing = -0.8,
  gradient = false,
  align = "left",
}) => {
  const { t } = useTime();
  const chars = Array.from(text);
  return (
    <div
      style={{
        fontFamily: FONT,
        fontSize: size,
        fontWeight: weight,
        letterSpacing,
        lineHeight: 1.16,
        display: "flex",
        flexWrap: "wrap",
        justifyContent: align === "center" ? "center" : "flex-start",
        whiteSpace: "pre",
      }}
    >
      {chars.map((ch, i) => {
        const p = interpolate(t, [delay + i * stagger, delay + i * stagger + 0.52], [0, 1], {
          ...clamp,
          easing: ease,
        });
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              opacity: p,
              transform: `translateY(${(1 - p) * size * 0.32}px)`,
              filter: `blur(${(1 - p) * 9}px)`,
              color: gradient ? undefined : color,
              backgroundImage: gradient
                ? `linear-gradient(100deg, ${C.water1}, ${C.water2})`
                : undefined,
              WebkitBackgroundClip: gradient ? "text" : undefined,
              backgroundClip: gradient ? "text" : undefined,
              WebkitTextFillColor: gradient ? "transparent" : undefined,
            }}
          >
            {ch}
          </span>
        );
      })}
    </div>
  );
};

export const TileSeq: React.FC<{
  dir: string;
  frames: number;
  start?: number;
  size: number;
  style?: React.CSSProperties;
}> = ({ dir, frames, start = 0, size, style }) => {
  const { frame, fps } = useTime();
  const idx = Math.max(0, Math.min(frames - 1, Math.floor((frame / fps - start) * 30)));
  return (
    <Img
      src={staticFile(`seq/${dir}/f_${pad3(idx)}.png`)}
      style={{ width: size, height: size, ...style }}
    />
  );
};

export const Icon: React.FC<{ name: string; size: number; style?: React.CSSProperties }> = ({
  name,
  size,
  style,
}) => <Img src={staticFile(`icons/${name}.png`)} style={{ width: size, height: size, ...style }} />;

export const Eyebrow: React.FC<{ text: string; delay: number }> = ({ text, delay }) => {
  const { t } = useTime();
  const p = interpolate(t, [delay, delay + 0.5], [0, 1], { ...clamp, easing: ease });
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 10,
        padding: "7px 18px",
        borderRadius: 999,
        background: "rgba(255,255,255,0.075)",
        border: "1px solid rgba(255,255,255,0.16)",
        fontFamily: FONT,
        fontSize: 19,
        fontWeight: 500,
        letterSpacing: 0.4,
        color: C.water1,
        opacity: p,
        transform: `translateY(${(1 - p) * 14}px)`,
      }}
    >
      <span
        style={{
          width: 7,
          height: 7,
          borderRadius: 99,
          background: C.water2,
          boxShadow: `0 0 10px ${C.water2}`,
        }}
      />
      {text}
    </div>
  );
};
