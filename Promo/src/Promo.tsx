import React, { useEffect, useState } from "react";
import {
  AbsoluteFill,
  continueRender,
  delayRender,
  Img,
  interpolate,
  Sequence,
  staticFile,
  useVideoConfig,
} from "remotion";
import {
  C,
  clamp,
  ease,
  Eyebrow,
  fadeIO,
  FONT,
  Icon,
  MONO,
  Reveal,
  TileSeq,
  useSpringAt,
  useTime,
  Wallpaper,
} from "./kit";

const FONTSHARE_CSS =
  "https://api.fontshare.com/v2/css?f[]=cabinet-grotesk@400,500,700&display=swap";

/* =============================== Shared macOS UI Primitives =============================== */

const MenuBarWaveIcon: React.FC<{ size?: number }> = ({ size = 24 }) => (
  <svg width={size} height={size} viewBox="0 0 18 18" fill="none">
    <defs>
      <clipPath id="ag-mb-inner">
        <rect x="2.95" y="2.95" width="12.1" height="12.1" rx="2.5" />
      </clipPath>
    </defs>
    <rect x="1.8" y="1.8" width="14.4" height="14.4" rx="3.6" stroke="#ffffff" strokeWidth="1.4" />
    <g clipPath="url(#ag-mb-inner)">
      <path
        d="M2.2 8.2 C6.2 6.2, 11.2 10.2, 15.8 8.4"
        stroke="rgba(255,255,255,0.48)"
        strokeWidth="1.05"
        fill="none"
      />
      <path
        fillRule="evenodd"
        d="M2 16 L2 9.8 C6.4 11.6, 11.4 7.4, 16 9.4 L16 16 Z M5.5 12.75 a1.15 1.15 0 1 0 2.3 0 a1.15 1.15 0 1 0 -2.3 0 Z"
        fill="#ffffff"
      />
    </g>
  </svg>
);

const DesktopChrome: React.FC<{
  plaque?: string;
  gaugeActive?: boolean;
  iconX?: number;
  barOpacity?: number;
}> = ({ plaque, gaugeActive = false, iconX = 1360, barOpacity = 1 }) => (
  <>
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: 1920,
        height: 48,
        background: "linear-gradient(180deg, rgba(22,24,32,0.78), rgba(18,20,28,0.68))",
        borderBottom: "1px solid rgba(255,255,255,0.10)",
        backdropFilter: "blur(28px) saturate(160%)",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 28px",
        opacity: barOpacity,
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 24,
          fontFamily: FONT,
          fontSize: 19,
          color: "rgba(255,255,255,0.9)",
        }}
      >
        <svg width={18} height={22} viewBox="0 0 18 22" fill="currentColor">
          <path d="M14.7 11.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.8-3.5.8-.7 0-1.9-.8-3.1-.8-1.6 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.1 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7 1.4 0 1.8.7 3 .7 1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.6 1.3-2.7-.1 0-2.3-.9-2.3-3.6zM12.3 4.8c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3z" />
        </svg>
        <span style={{ fontWeight: 700, color: "#fff" }}>Finder</span>
        <span style={{ opacity: 0.78 }}>File</span>
        <span style={{ opacity: 0.78 }}>Edit</span>
        <span style={{ opacity: 0.78 }}>View</span>
        <span style={{ opacity: 0.78 }}>Go</span>
        <span style={{ opacity: 0.78 }}>Window</span>
      </div>

      <div style={{ position: "absolute", left: 0, top: 0, height: 48, width: 1920 }}>
        <svg
          width={22}
          height={22}
          viewBox="0 0 24 24"
          fill="none"
          stroke="rgba(255,255,255,0.88)"
          strokeWidth="1.9"
          style={{ position: "absolute", left: iconX - 66, top: 13 }}
        >
          <path d="M11 5L6 9H2v6h4l5 4V5z" fill="rgba(255,255,255,0.88)" />
          <path d="M15.5 8.5a5 5 0 010 7M18.8 5.8a9 9 0 010 12.4" strokeLinecap="round" />
        </svg>
        <div
          style={{
            position: "absolute",
            left: iconX - 24,
            top: 6,
            width: 48,
            height: 36,
            borderRadius: 10,
            background: gaugeActive ? "rgba(255,255,255,0.22)" : "transparent",
            border: gaugeActive ? "1px solid rgba(255,255,255,0.26)" : "1px solid transparent",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <MenuBarWaveIcon size={25} />
        </div>
        <svg
          width={22}
          height={22}
          viewBox="0 0 24 24"
          fill="none"
          stroke="rgba(255,255,255,0.88)"
          strokeWidth="2"
          strokeLinecap="round"
          style={{ position: "absolute", left: iconX + 52, top: 13 }}
        >
          <path d="M5 12.5a10 10 0 0114 0M8.5 16a5.5 5.5 0 017 0" />
          <circle cx="12" cy="19.5" r="1.4" fill="rgba(255,255,255,0.88)" stroke="none" />
        </svg>
        <svg
          width={28}
          height={22}
          viewBox="0 0 28 20"
          fill="none"
          style={{ position: "absolute", left: iconX + 104, top: 13 }}
        >
          <rect x="1.5" y="4" width="21" height="12" rx="3" stroke="rgba(255,255,255,0.84)" strokeWidth="1.6" />
          <rect x="3.8" y="6.3" width="16.4" height="7.4" rx="1.5" fill="rgba(255,255,255,0.9)" />
          <path d="M24 8v4" stroke="rgba(255,255,255,0.75)" strokeWidth="2" strokeLinecap="round" />
        </svg>
        <svg
          width={22}
          height={22}
          viewBox="0 0 24 24"
          fill="none"
          style={{ position: "absolute", left: iconX + 160, top: 13 }}
        >
          <rect x="3" y="4" width="18" height="6.5" rx="3.25" stroke="rgba(255,255,255,0.84)" strokeWidth="1.6" />
          <circle cx="16.2" cy="7.25" r="2.1" fill="#fff" />
          <rect x="3" y="13.5" width="18" height="6.5" rx="3.25" stroke="rgba(255,255,255,0.84)" strokeWidth="1.6" />
          <circle cx="7.8" cy="16.75" r="2.1" fill="#fff" />
        </svg>
        <div
          style={{
            position: "absolute",
            left: iconX + 210,
            top: 11,
            fontFamily: FONT,
            fontSize: 19,
            fontWeight: 500,
            color: "rgba(255,255,255,0.94)",
          }}
        >
          Sat 18:30
        </div>
      </div>
    </div>

    {plaque && (
      <div
        style={{
          position: "absolute",
          left: 26,
          top: 68,
          display: "inline-flex",
          alignItems: "center",
          gap: 10,
          height: 36,
          padding: "0 14px",
          borderRadius: 999,
          background: "rgba(20,22,28,0.62)",
          border: "1px solid rgba(255,255,255,0.16)",
          backdropFilter: "blur(18px)",
          fontFamily: FONT,
          fontSize: 15.5,
          fontWeight: 500,
          color: "rgba(255,255,255,0.86)",
          opacity: barOpacity,
        }}
      >
        <span style={{ width: 7, height: 7, borderRadius: 99, background: "rgba(255,255,255,0.75)" }} />
        {plaque}
      </div>
    )}
  </>
);

/* =============================== Scene 1 · Hook =============================== */

const HOOK_APPS = ["claude", "codex", "cursor", "gemini", "antigravity", "grokbot", "windsurf", "trae", "kiro", "workbuddy"];
const ASKED: { name: string; icon: string; at: number }[] = [
  { name: "Claude", icon: "claude", at: 0.3 },
  { name: "Codex", icon: "codex", at: 0.95 },
  { name: "Cursor", icon: "cursor", at: 1.6 },
  { name: "Gemini", icon: "gemini", at: 2.25 },
];

const Hook: React.FC = () => {
  const { t, dur } = useTime();
  const activeIdx = ASKED.reduce((acc, a, i) => (t >= a.at ? i : acc), -1);
  const phase1 = Math.min(interpolate(t, [0.15, 0.5], [0, 1], clamp), interpolate(t, [2.95, 3.2], [1, 0], clamp));
  const blur1 = interpolate(t, [2.95, 3.2], [0, 14], clamp);

  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.25, 0.3) }}>
      <Wallpaper painting="judith" dim={0.54} />
      {HOOK_APPS.map((name, i) => {
        const ang = (i / HOOK_APPS.length) * Math.PI * 2 + 0.35;
        const drift = t * 0.06;
        const x = 960 + Math.cos(ang + drift) * 760 - 48;
        const y = 540 + Math.sin(ang + drift) * 360 - 48;
        const askedIdx = ASKED.findIndex((a) => a.icon === name);
        const lit = askedIdx >= 0 && askedIdx === activeIdx && t < 3.0;
        const base = interpolate(t, [0.05 + i * 0.05, 0.6 + i * 0.05], [0, 0.34], clamp);
        return (
          <div
            key={name}
            style={{
              position: "absolute",
              left: x,
              top: y,
              opacity: lit ? 1 : base,
              transform: `scale(${lit ? 1.2 : 1})`,
              filter: lit ? "drop-shadow(0 0 32px rgba(141,184,255,0.58))" : "saturate(0.75)",
            }}
          >
            <Icon name={name} size={98} />
          </div>
        );
      })}

      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity: phase1, filter: `blur(${blur1}px)` }}>
        <div style={{ position: "relative", width: 1920, height: 108, marginBottom: 14 }}>
          {ASKED.map((a, i) => {
            const p = interpolate(t, [a.at, a.at + 0.22], [0, 1], { ...clamp, easing: ease });
            const out = i < ASKED.length - 1 ? interpolate(t, [ASKED[i + 1].at, ASKED[i + 1].at + 0.22], [0, 1], { ...clamp, easing: ease }) : 0;
            return (
              <div
                key={a.icon}
                style={{
                  position: "absolute",
                  inset: 0,
                  display: "flex",
                  justifyContent: "center",
                  alignItems: "center",
                  gap: 22,
                  opacity: p * (1 - out),
                  transform: `translateY(${(1 - p) * 46 - out * 46}px)`,
                  filter: `blur(${(1 - p) * 6 + out * 6}px)`,
                }}
              >
                <Icon name={a.icon} size={86} />
                <span style={{ fontFamily: FONT, fontSize: 82, fontWeight: 700, color: C.text, letterSpacing: -2 }}>{a.name}</span>
              </div>
            );
          })}
        </div>
        <Reveal text="还剩多少额度？" delay={0.35} size={92} weight={700} align="center" letterSpacing={-1} />
      </AbsoluteFill>

      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <Reveal text="别再一个个点开查看了。" delay={3.05} size={84} weight={700} align="center" stagger={0.035} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/* =============================== Scene 2 · Brand =============================== */

const Ripples: React.FC<{ cx: number; cy: number; start: number; count?: number }> = ({ cx, cy, start, count = 3 }) => {
  const { t } = useTime();
  return (
    <>
      {Array.from({ length: count }).map((_, i) => {
        const p = interpolate(t, [start + i * 0.28, start + i * 0.28 + 1.8], [0, 1], { ...clamp, easing: ease });
        const r = 120 + p * 560;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: cx - r,
              top: cy - r,
              width: r * 2,
              height: r * 2,
              borderRadius: "50%",
              border: `${2 - p}px solid rgba(141,184,255,${(1 - p) * 0.45})`,
              boxShadow: `0 0 40px rgba(127,227,210,${(1 - p) * 0.12}) inset`,
            }}
          />
        );
      })}
    </>
  );
};

const Brand: React.FC = () => {
  const { t, dur } = useTime();
  const pop = useSpringAt(0.0, 14, 0.9, 110);
  const scale = interpolate(pop, [0, 1], [0.55, 1]);
  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.2, 0.35) }}>
      <Wallpaper painting="monet" dim={0.44} />
      <Ripples cx={960} cy={365} start={0.05} />
      <div style={{ position: "absolute", left: 960 - 118, top: 365 - 118, transform: `scale(${scale})`, opacity: pop }}>
        <Icon name="agentgauge" size={236} style={{ filter: "drop-shadow(0 30px 60px rgba(20,30,60,0.52))" }} />
      </div>
      <div style={{ position: "absolute", top: 522, width: "100%", display: "flex", justifyContent: "center" }}>
        <Eyebrow text="v1.2.0 · macOS 26 Tahoe · 30+ 主流模型与套餐" delay={0.28} />
      </div>
      <div style={{ position: "absolute", top: 586, width: "100%", display: "flex", justifyContent: "center" }}>
        <Reveal text="AgentGauge" delay={0.45} size={116} weight={700} align="center" letterSpacing={-4} stagger={0.032} />
      </div>
      <div style={{ position: "absolute", top: 738, width: "100%", display: "flex", justifyContent: "center" }}>
        <Reveal text="AI 额度，清澈如水 · 把仪表装进你的 Dock" delay={1.15} size={46} weight={600} align="center" gradient stagger={0.03} />
      </div>
    </AbsoluteFill>
  );
};

/* =============================== Scene 3 · HD Liquid Showcase (1024px Metal) =============================== */

type HeroItem = {
  id: string;
  dir: string;
  name: string;
  headline: string;
  sub: string;
  badge: string;
  pct: string;
  glow: string;
  dot: string;
  from: number;
  to: number;
};

const HD_HEROES: HeroItem[] = [
  {
    id: "codex",
    dir: "hd_codex",
    name: "ChatGPT / Codex",
    headline: "截图顶栏时间 · 余量一眼即知",
    sub: "上方实时显示重置倒计时，下方翡翠光学水波与气泡清澈跃动",
    badge: "Pro Lite 5x · 37% 剩余",
    pct: "37%",
    glow: "rgba(76, 178, 150, 0.34)",
    dot: "#66D4B8",
    from: 0.0,
    to: 2.1,
  },
  {
    id: "grokbot",
    dir: "hd_grokbot",
    name: "Grok Bot",
    headline: "博朗圆弧指针 · 精密机械美学",
    sub: "经典德系半圆刻度与橙红指针，随暖陶液态水波同频呼吸",
    badge: "Premium · 69% 剩余",
    pct: "69%",
    glow: "rgba(222, 146, 108, 0.34)",
    dot: "#E2A17E",
    from: 2.1,
    to: 4.2,
  },
  {
    id: "cursor",
    dir: "hd_cursor",
    name: "Cursor",
    headline: "双轨微仪表 · 主周限额同屏",
    sub: "主窗口与周限额双轨并列，1024px 原生 Metal 纤毫毕现",
    badge: "Ultra 20x · 68% 剩余",
    pct: "68%",
    glow: "rgba(156, 144, 232, 0.34)",
    dot: "#A499EC",
    from: 4.2,
    to: 6.3,
  },
];

const HD_LINEUP = [
  { id: "codex", dir: "hd_codex", name: "ChatGPT", styleName: "截图顶栏时间", glow: "rgba(76, 178, 150, 0.34)", dot: "#66D4B8" },
  { id: "claude", dir: "hd_claude", name: "Claude", styleName: "像素 LED 点阵", glow: "rgba(218, 128, 92, 0.34)", dot: "#E89A78" },
  { id: "grokbot", dir: "hd_grokbot", name: "Grok Bot", styleName: "博朗圆弧指针", glow: "rgba(222, 146, 108, 0.34)", dot: "#E2A17E" },
  { id: "cursor", dir: "hd_cursor", name: "Cursor", styleName: "双轨微仪表", glow: "rgba(156, 144, 232, 0.34)", dot: "#A499EC" },
  { id: "antigravity", dir: "hd_antigravity", name: "Antigravity", styleName: "同心 R 角胶囊", glow: "rgba(105, 168, 255, 0.36)", dot: "#7EB6FF" },
];

const HDShowcase: React.FC = () => {
  const { t, dur } = useTime();
  const trioStart = 6.25;
  const soloMaster = interpolate(t, [trioStart - 0.12, trioStart + 0.18], [1, 0], clamp);
  const trioMaster = interpolate(t, [trioStart, trioStart + 0.35], [0, 1], { ...clamp, easing: ease });
  const HERO_SIZE = 650;

  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.25, 0.3) }}>
      <Wallpaper painting="judith" dim={0.54} />

      <AbsoluteFill style={{ opacity: soloMaster }}>
        {HD_HEROES.map((h, idx) => {
          const inP =
            idx === 0
              ? interpolate(t, [0.0, 0.38], [0, 1], { ...clamp, easing: ease })
              : interpolate(t, [h.from - 0.08, h.from + 0.28], [0, 1], { ...clamp, easing: ease });
          const outP =
            idx < HD_HEROES.length - 1
              ? interpolate(t, [h.to - 0.18, h.to + 0.08], [1, 0], { ...clamp, easing: ease })
              : 1;
          const vis = Math.max(0, Math.min(inP, outP));
          if (vis <= 0.002) return null;
          const slideY = (1 - inP) * 34 - (1 - outP) * 28;
          const sc = interpolate(inP, [0, 1], [0.91, 1]) * interpolate(outP, [0, 1], [0.95, 1]);
          const driftY = Math.sin((t - h.from) * 1.9 + idx) * 6;

          return (
            <React.Fragment key={h.id}>
              <div
                style={{
                  position: "absolute",
                  left: 110,
                  top: 90,
                  width: 900,
                  height: 900,
                  background: `radial-gradient(circle at 50% 48%, ${h.glow}, rgba(0,0,0,0) 60%)`,
                  opacity: vis,
                }}
              />
              <div
                style={{
                  position: "absolute",
                  left: 230,
                  top: 210 + driftY,
                  width: HERO_SIZE,
                  height: HERO_SIZE,
                  opacity: vis,
                  transform: `translateY(${slideY}px) scale(${sc})`,
                }}
              >
                <TileSeq
                  dir={h.dir}
                  frames={240}
                  start={0}
                  size={HERO_SIZE}
                  style={{ filter: "drop-shadow(0 44px 80px rgba(0,0,0,0.62))" }}
                />
                <div
                  style={{
                    position: "absolute",
                    top: HERO_SIZE - 42,
                    left: 0,
                    transform: "scaleY(-1)",
                    opacity: 0.08,
                    WebkitMaskImage: "linear-gradient(to top, rgba(0,0,0,1), rgba(0,0,0,0) 34%)",
                    maskImage: "linear-gradient(to top, rgba(0,0,0,1), rgba(0,0,0,0) 34%)",
                  }}
                >
                  <TileSeq dir={h.dir} frames={240} start={0} size={HERO_SIZE} />
                </div>
              </div>

              <div
                style={{
                  position: "absolute",
                  left: 980,
                  top: 280,
                  width: 800,
                  opacity: vis,
                  transform: `translateX(${(1 - inP) * 44 - (1 - outP) * 26}px)`,
                }}
              >
                <div style={{ display: "flex", alignItems: "center", gap: 14, marginBottom: 24 }}>
                  <div
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: 10,
                      padding: "8px 20px",
                      borderRadius: 999,
                      background: "rgba(255,255,255,0.08)",
                      border: "1px solid rgba(255,255,255,0.16)",
                      fontFamily: FONT,
                      fontSize: 20,
                      fontWeight: 600,
                      color: C.text,
                    }}
                  >
                    <span style={{ width: 9, height: 9, borderRadius: 99, background: h.dot, boxShadow: `0 0 12px ${h.dot}` }} />
                    {h.badge}
                  </div>
                </div>

                <div style={{ fontFamily: FONT, fontSize: 96, fontWeight: 700, color: C.text, letterSpacing: -3, lineHeight: 1.02 }}>
                  {h.name}
                </div>
                <div
                  style={{
                    fontFamily: FONT,
                    fontSize: 44,
                    fontWeight: 700,
                    marginTop: 22,
                    letterSpacing: -0.8,
                    backgroundImage: `linear-gradient(100deg, ${C.water1}, ${C.water2})`,
                    WebkitBackgroundClip: "text",
                    backgroundClip: "text",
                    WebkitTextFillColor: "transparent",
                  }}
                >
                  {h.headline}
                </div>
                <div style={{ fontFamily: FONT, fontSize: 28, fontWeight: 500, color: C.dim, marginTop: 20, lineHeight: 1.55, maxWidth: 700 }}>
                  {h.sub}
                </div>
              </div>
            </React.Fragment>
          );
        })}

        <div style={{ position: "absolute", left: 980, top: 214 }}>
          <Eyebrow text="v1.2.0 Native Metal · 统一光学水波" delay={0.05} />
        </div>
        <div style={{ position: "absolute", left: 980, top: 750, display: "flex", alignItems: "center", gap: 14 }}>
          {HD_HEROES.map((h) => {
            const active = t >= h.from && t < h.to;
            return (
              <div
                key={h.id}
                style={{
                  width: active ? 46 : 12,
                  height: 12,
                  borderRadius: 99,
                  background: active ? h.dot : "rgba(255,255,255,0.22)",
                  boxShadow: active ? `0 0 16px ${h.dot}` : "none",
                }}
              />
            );
          })}
        </div>
      </AbsoluteFill>

      {trioMaster > 0.002 && (
        <AbsoluteFill style={{ opacity: trioMaster }}>
          <div style={{ position: "absolute", top: 112, width: "100%", display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
            <Eyebrow text="11 Curated Liquid Styles · 多样混搭" delay={trioStart + 0.05} />
            <div
              style={{
                fontFamily: FONT,
                fontSize: 62,
                fontWeight: 700,
                color: C.text,
                letterSpacing: -1.4,
                transform: `translateY(${(1 - trioMaster) * 24}px)`,
              }}
            >
              多款指示样式自由混搭 · 每一枚都是流动仪表盘
            </div>
          </div>

          <div
            style={{
              position: "absolute",
              left: 0,
              top: 326,
              width: 1920,
              display: "flex",
              justifyContent: "center",
              alignItems: "flex-start",
              gap: 38,
            }}
          >
            {HD_LINEUP.map((h, i) => {
              const p = interpolate(t, [trioStart + i * 0.055, trioStart + 0.38 + i * 0.055], [0, 1], { ...clamp, easing: ease });
              return (
                <div
                  key={h.id}
                  style={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    opacity: p,
                    transform: `translateY(${(1 - p) * 44}px) scale(${interpolate(p, [0, 1], [0.88, 1])})`,
                  }}
                >
                  <div style={{ position: "relative" }}>
                    <div
                      style={{
                        position: "absolute",
                        inset: -44,
                        background: `radial-gradient(circle, ${h.glow}, rgba(0,0,0,0) 64%)`,
                      }}
                    />
                    <TileSeq
                      dir={h.dir}
                      frames={240}
                      start={0}
                      size={308}
                      style={{ position: "relative", filter: "drop-shadow(0 28px 50px rgba(0,0,0,0.58))" }}
                    />
                  </div>
                  <div style={{ fontFamily: FONT, fontSize: 30, fontWeight: 700, color: C.text, marginTop: 20, letterSpacing: -0.4 }}>
                    {h.name}
                  </div>
                  <div style={{ fontFamily: FONT, fontSize: 21, fontWeight: 600, color: h.dot, marginTop: 6 }}>
                    {h.styleName}
                  </div>
                </div>
              );
            })}
          </div>
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};

/* =============================== Scene 4 · Dock Demo (with macOS Magnification & Masterpiece Desktop) =============================== */

const DOCK = ["finder", "safari", "antigravity", "codex", "cursor", "grokbot", "claude", "workbuddy", "settings"];
const ICON_SZ = 104;
const GAP = 22;
const DOCK_PAD = 16;
const DOCK_W = DOCK.length * ICON_SZ + (DOCK.length - 1) * GAP + DOCK_PAD * 2;
const DOCK_X = (1920 - DOCK_W) / 2;
const DOCK_TOP = 1080 - 26 - (ICON_SZ + DOCK_PAD * 2);
const iconCX = (i: number) => DOCK_X + DOCK_PAD + ICON_SZ / 2 + i * (ICON_SZ + GAP);
const ICON_TOP = DOCK_TOP + DOCK_PAD;

type Hover = { i: number; id: string; label: string; from: number; to: number; tipW: number; tipH: number };
const HOVERS: Hover[] = [
  { i: 2, id: "antigravity", label: "Antigravity", from: 0.85, to: 3.5, tipW: 794, tipH: 564 },
  { i: 3, id: "codex", label: "ChatGPT", from: 3.65, to: 6.2, tipW: 834, tipH: 330 },
  { i: 5, id: "grokbot", label: "Grok Bot", from: 6.45, to: 8.55, tipW: 644, tipH: 330 },
];
const PT = 1.56;

const seg = (t: number, keys: [number, number][]) => {
  for (let k = 0; k < keys.length - 1; k++) {
    if (t <= keys[k + 1][0]) {
      return interpolate(t, [keys[k][0], keys[k + 1][0]], [keys[k][1], keys[k + 1][1]], { ...clamp, easing: ease });
    }
  }
  return keys[keys.length - 1][1];
};

const Pointer: React.FC<{ x: number; y: number; opacity: number; scale?: number }> = ({ x, y, opacity, scale = 1 }) => (
  <svg
    width={46}
    height={62}
    viewBox="0 0 23 31"
    style={{
      position: "absolute",
      left: x - 6,
      top: y - 4,
      opacity,
      transform: `scale(${scale})`,
      transformOrigin: "6px 4px",
      filter: "drop-shadow(0 4px 6px rgba(0,0,0,0.45))",
    }}
  >
    <path d="M2 1 L2 24 L7.6 18.6 L11.4 27.4 L15 25.8 L11.3 17.2 L18.8 17.2 Z" fill="#111" stroke="#fff" strokeWidth={1.6} strokeLinejoin="round" />
  </svg>
);

const DockDemo: React.FC = () => {
  const { t, dur } = useTime();

  const cx = seg(t, [
    [0.0, 1560],
    [0.85, iconCX(2) + 8],
    [3.5, iconCX(2) + 8],
    [3.68, iconCX(3) + 10],
    [6.2, iconCX(3) + 10],
    [6.48, iconCX(5) + 8],
    [8.55, iconCX(5) + 8],
    [9.0, 1500],
  ]);
  const cy = seg(t, [
    [0.0, 1130],
    [0.85, ICON_TOP + 54],
    [8.55, ICON_TOP + 56],
    [9.0, 1140],
  ]);

  const dockHoverStrength = Math.min(interpolate(t, [0.65, 0.9], [0, 1], clamp), interpolate(t, [8.55, 8.85], [1, 0], clamp));
  const active = HOVERS.find((h) => t >= h.from && t < h.to + 0.15);
  const tipVisible = Math.min(interpolate(t, [0.85, 1.05], [0, 1], clamp), interpolate(t, [8.55, 8.75], [1, 0], clamp));
  const tipPop = useSpringAt(0.85, 15, 0.8, 170);

  const tipX = seg(t, [
    [0, iconCX(2)],
    [3.5, iconCX(2)],
    [3.72, iconCX(3)],
    [6.2, iconCX(3)],
    [6.52, iconCX(5)],
    [9, iconCX(5)],
  ]);
  const tipCardBottom = ICON_TOP - 64 * PT;

  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.3, 0.3) }}>
      <Wallpaper painting="yosemite" dim={0.18} zoom={1.06} />
      <DesktopChrome plaque="Albert Bierstadt · Yosemite Valley, 1866" />

      <div style={{ position: "absolute", left: 0, top: 108, width: "100%", display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
        <Eyebrow text="Hover to Reveal · 120Hz Glide" delay={0.1} />
        <Reveal text="悬停 Dock 图标，额度随鼠标丝滑跟随" delay={0.2} size={60} weight={700} align="center" stagger={0.028} />
      </div>

      {/* Dock glass bar */}
      <div
        style={{
          position: "absolute",
          left: DOCK_X,
          top: DOCK_TOP,
          width: DOCK_W,
          height: ICON_SZ + DOCK_PAD * 2,
          borderRadius: 38,
          background: "linear-gradient(180deg, rgba(255,255,255,0.18), rgba(255,255,255,0.08))",
          border: "1px solid rgba(255,255,255,0.24)",
          boxShadow: "0 30px 80px rgba(0,0,0,0.48), inset 0 1px 0 rgba(255,255,255,0.25)",
          backdropFilter: "blur(30px) saturate(160%)",
        }}
      />
      {DOCK.map((name, i) => {
        const isAI = ["antigravity", "codex", "cursor", "grokbot", "claude", "workbuddy"].includes(name);
        const h = HOVERS.find((hh) => hh.i === i);
        const isHovered = h ? t >= h.from - 0.1 && t <= h.to + 0.2 : false;
        const tileOpacity = isAI
          ? Math.min(
              interpolate(t, [0.15 + i * 0.05, 0.55 + i * 0.05], [0, isHovered ? 1 : 0.94], clamp),
              interpolate(t, [8.65, 8.95], [1, 0], clamp),
            )
          : 0;
        // Gaussian Dock magnification matching real macOS
        const dist = Math.abs(cx - iconCX(i));
        const g = Math.exp(-(dist * dist) / (2 * 92 * 92)) * dockHoverStrength;
        const magScale = 1 + 0.19 * g;
        const magLift = -18 * g;

        return (
          <div
            key={name}
            style={{
              position: "absolute",
              left: iconCX(i) - ICON_SZ / 2,
              top: ICON_TOP,
              width: ICON_SZ,
              height: ICON_SZ,
              transformOrigin: "50% 100%",
              transform: `translateY(${magLift}px) scale(${magScale})`,
            }}
          >
            <Icon name={name} size={ICON_SZ} style={{ position: "absolute", inset: 0 }} />
            {isAI && tileOpacity > 0 && (
              <div style={{ position: "absolute", inset: 0, opacity: tileOpacity }}>
                <TileSeq dir={`wake_${name}`} frames={270} start={0} size={ICON_SZ} />
              </div>
            )}
            <div style={{ position: "absolute", left: ICON_SZ / 2 - 3, top: ICON_SZ + 9, width: 6, height: 6, borderRadius: 3, background: "rgba(255,255,255,0.68)" }} />
          </div>
        );
      })}

      {/* Smoothly gliding Dock label pill */}
      <div
        style={{
          position: "absolute",
          left: tipX,
          top: ICON_TOP - 74,
          transform: "translateX(-50%)",
          padding: "8px 20px",
          borderRadius: 14,
          fontFamily: FONT,
          fontSize: 23,
          fontWeight: 500,
          color: "#fff",
          background: "rgba(32,35,44,0.78)",
          border: "1px solid rgba(255,255,255,0.18)",
          backdropFilter: "blur(20px)",
          opacity: active
            ? Math.min(interpolate(t, [active.from, active.from + 0.12], [0, 1], clamp), interpolate(t, [active.to, active.to + 0.12], [1, 0], clamp))
            : 0,
          whiteSpace: "nowrap",
        }}
      >
        {active ? active.label : "Antigravity"}
      </div>

      {/* Real Liquid Glass hover dashboards */}
      <div
        style={{
          position: "absolute",
          left: tipX,
          top: tipCardBottom,
          opacity: tipVisible,
          transform: `translate(-50%, -100%) scale(${interpolate(tipPop, [0, 1], [0.94, 1])})`,
          transformOrigin: "50% 100%",
        }}
      >
        {HOVERS.map((h, k) => {
          const next = HOVERS[k + 1];
          const inP = k === 0 ? 1 : interpolate(t, [h.from - 0.12, h.from + 0.1], [0, 1], clamp);
          const outP = next ? interpolate(t, [next.from - 0.12, next.from + 0.06], [1, 0], clamp) : 1;
          const w = (h.tipW / 2) * PT;
          const hh = (h.tipH / 2) * PT;
          return (
            <Img
              key={h.id}
              src={staticFile(`shots/tooltip_${h.id}.png`)}
              style={{
                position: "absolute",
                left: -w / 2,
                bottom: -16 * PT,
                width: w,
                height: hh,
                opacity: Math.max(0, Math.min(inP, outP)),
              }}
            />
          );
        })}
      </div>

      <Pointer x={cx} y={cy} opacity={interpolate(t, [0, 0.2], [0, 1], clamp)} />
    </AbsoluteFill>
  );
};

/* =============================== Scene 5 · Macro 2x2 Multi-Style Drain Quartet =============================== */

const FEATURES = [
  { n: "01", title: "Retina 级 Metal 实时渲染", sub: "半精度着色器管线，每帧约 1.7 ms", at: 0.6 },
  { n: "02", title: "波浪、气泡与光学折射", sub: "鼠标划过，水面随惯性轻盈摇晃", at: 1.8 },
  { n: "03", title: "多样式同步响应 · 低水位避让", sub: "顶栏计时、灵动微岛、光圈扫描与胶囊自由混搭", at: 3.2 },
  { n: "04", title: "闲置零占用，即停即醒", sub: "离开 Dock 自动休眠，回来瞬间唤醒", at: 4.4 },
];

const DRAIN_QUARTET = [
  { dir: "drain_codex", label: "截图顶栏时间" },
  { dir: "drain_claude", label: "顶部灵动微岛" },
  { dir: "drain_cursor", label: "光圈扇叶扫描" },
  { dir: "drain_antigravity", label: "同心 R 角避让" },
];

const Macro: React.FC = () => {
  const { t, dur } = useTime();
  const enter = useSpringAt(0.0, 18, 1, 90);
  const cellS = 252;
  const gap = 30;
  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.3, 0.3) }}>
      <Wallpaper painting="monet" dim={0.48} />
      <div
        style={{
          position: "absolute",
          left: 110,
          top: 130,
          width: 820,
          height: 820,
          background: "radial-gradient(circle at 50% 48%, rgba(110,160,255,0.28), rgba(0,0,0,0) 62%)",
          opacity: enter,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 224,
          top: 200,
          width: cellS * 2 + gap,
          display: "grid",
          gridTemplateColumns: `${cellS}px ${cellS}px`,
          columnGap: gap,
          rowGap: 32,
          transform: `translateY(${(1 - enter) * 56}px) scale(${interpolate(enter, [0, 1], [0.9, 1])})`,
          opacity: enter,
        }}
      >
        {DRAIN_QUARTET.map((item) => (
          <div key={item.dir} style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
            <TileSeq dir={item.dir} frames={180} size={cellS} style={{ filter: "drop-shadow(0 28px 50px rgba(0,0,0,0.52))" }} />
            <div style={{ fontFamily: FONT, fontSize: 21, fontWeight: 600, color: C.dim, marginTop: 10 }}>{item.label}</div>
          </div>
        ))}
      </div>

      <div style={{ position: "absolute", left: 960, top: 190, width: 860 }}>
        <Eyebrow text="Liquid Quota · Native Metal" delay={0.05} />
        <div style={{ height: 18 }} />
        <Reveal text="余量，像水一样看得见" delay={0.15} size={72} weight={700} stagger={0.035} letterSpacing={-1.5} />
        <div style={{ height: 46 }} />
        {FEATURES.map((f) => {
          const p = interpolate(t, [f.at, f.at + 0.55], [0, 1], { ...clamp, easing: ease });
          return (
            <div key={f.n} style={{ display: "flex", gap: 26, alignItems: "flex-start", marginBottom: 34, opacity: p, transform: `translateX(${(1 - p) * 40}px)` }}>
              <div style={{ fontFamily: MONO, fontSize: 22, color: C.water2, paddingTop: 10, width: 36 }}>{f.n}</div>
              <div>
                <div style={{ fontFamily: FONT, fontSize: 38, fontWeight: 650, color: C.text, letterSpacing: -0.4 }}>{f.title}</div>
                <div style={{ fontFamily: FONT, fontSize: 24, fontWeight: 500, color: C.dim, marginTop: 6 }}>{f.sub}</div>
              </div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

/* =============================== Scene 6 · Styles grid =============================== */

const STYLE_LABELS = ["截图顶栏时间", "动态反相字", "微晶描边字", "同心 R 角", "光圈扇叶扫描", "像素 LED 点阵", "双轨微仪表", "博朗圆弧指针", "底部 5 格晶块", "顶部灵动微岛", "顶部弧形光眉", "低水位避让"];

const Styles: React.FC = () => {
  const { t, dur, frame, fps } = useTime();
  const cell = 232;
  const gx = 46;
  const gridW = 6 * cell + 5 * gx;
  const left = (1920 - gridW) / 2;
  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.3, 0.3) }}>
      <Wallpaper painting="twilight" dim={0.5} />
      <div style={{ position: "absolute", top: 104, width: "100%", display: "flex", flexDirection: "column", alignItems: "center", gap: 16 }}>
        <Eyebrow text="Make It Yours · v1.2.0" delay={0.05} />
        <Reveal text="11 种精选指示样式 · 全系共享光学水波" delay={0.12} size={58} weight={700} align="center" stagger={0.025} letterSpacing={-1} />
      </div>
      {STYLE_LABELS.map((label, i) => {
        const col = i % 6;
        const row = Math.floor(i / 6);
        const delay = 0.25 + i * 0.11;
        const local = frame - Math.round(delay * fps);
        const p = local < 0 ? 0 : interpolate(local / fps, [0, 0.45], [0, 1], { ...clamp, easing: ease });
        return (
          <div
            key={label}
            style={{
              position: "absolute",
              left: left + col * (cell + gx),
              top: 300 + row * 340,
              width: cell,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              opacity: p,
              transform: `translateY(${(1 - p) * 40}px) scale(${interpolate(p, [0, 1], [0.86, 1])})`,
            }}
          >
            <TileSeq dir={`style_${String(i).padStart(2, "0")}`} frames={150} start={delay - 0.05} size={cell} style={{ filter: "drop-shadow(0 18px 30px rgba(0,0,0,0.45))" }} />
            <div style={{ fontFamily: FONT, fontSize: 24, fontWeight: 600, color: C.dim, marginTop: 14 }}>{label}</div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

/* =============================== Scene 7 · Dashboard detail =============================== */

type Callout = { box: [number, number, number, number]; title: string; sub: string; at: number };
const CALLOUTS: Callout[] = [
  { box: [280, 56, 406, 96], title: "订阅与余额自动识别", sub: "AI Ultra · Pro Lite 5x · Max 20x · API 余额", at: 1.0 },
  { box: [600, 52, 744, 128], title: "主额度与重置倒计时", sub: "什么时候恢复，一眼可知", at: 2.2 },
  { box: [50, 152, 744, 470], title: "多模型分项额度", sub: "每个模型独立进度，低于 30% 自动变色", at: 3.4 },
  { box: [50, 476, 236, 514], title: "积分与权益同步展示", sub: "Credits · 满额重置券 · 可用积分", at: 4.4 },
];

const Dashboard: React.FC = () => {
  const { t, dur } = useTime();
  const enter = useSpringAt(0.0, 18, 1, 100);
  const k = 1.16;
  const W = 794 * k;
  const H = 564 * k;
  const X = 150;
  const Y = 262;
  const push = interpolate(t, [0, dur], [1, 1.035], clamp);
  const activeIdx = CALLOUTS.reduce((acc, c, i) => (t >= c.at ? i : acc), -1);

  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.3, 0.3) }}>
      <Wallpaper painting="judith" dim={0.42} />
      <div style={{ position: "absolute", left: X + 30, top: 92 }}>
        <Eyebrow text="Hover Dashboard" delay={0.05} />
        <div style={{ height: 14 }} />
        <Reveal text="一张卡片，看清全部额度" delay={0.12} size={62} weight={700} stagger={0.035} letterSpacing={-1.2} />
      </div>

      <div style={{ position: "absolute", left: X, top: Y, width: W, height: H, opacity: enter, transform: `translateY(${(1 - enter) * 50}px) scale(${push})`, transformOrigin: "30% 50%" }}>
        <Img src={staticFile("shots/tooltip_antigravity.png")} style={{ width: W, height: H }} />
        {CALLOUTS.map((c, i) => {
          const p = interpolate(t, [c.at, c.at + 0.35], [0, 1], { ...clamp, easing: ease });
          const emph = i === activeIdx ? 1 : 0.0;
          const [x0, y0, x1, y1] = c.box.map((v) => v * k);
          return (
            <div
              key={c.title}
              style={{
                position: "absolute",
                left: x0 - 6,
                top: y0 - 6,
                width: x1 - x0 + 12,
                height: y1 - y0 + 12,
                borderRadius: 14,
                border: `2px solid rgba(127,227,210,${0.95 * p * (0.25 + 0.75 * emph)})`,
                boxShadow: `0 0 ${24 * emph}px rgba(127,227,210,${0.35 * p * emph})`,
                transform: `scale(${interpolate(p, [0, 1], [1.06, 1])})`,
              }}
            />
          );
        })}
      </div>

      {CALLOUTS.map((c, i) => {
        const p = interpolate(t, [c.at, c.at + 0.45], [0, 1], { ...clamp, easing: ease });
        const emph = i === activeIdx;
        const ly = 300 + i * 150;
        const boxRightX = X + c.box[2] * k + 8;
        const boxMidY = Y + ((c.box[1] + c.box[3]) / 2) * k;
        const labelX = 1210;
        return (
          <React.Fragment key={c.title}>
            <svg style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, opacity: p * (emph ? 1 : 0) }}>
              <path
                d={`M ${boxRightX} ${boxMidY} C ${boxRightX + 120} ${boxMidY}, ${labelX - 140} ${ly + 26}, ${labelX - 24} ${ly + 26}`}
                stroke="rgba(127,227,210,0.85)"
                strokeWidth={2}
                fill="none"
                strokeDasharray={600}
                strokeDashoffset={600 * (1 - p)}
              />
              <circle cx={labelX - 24} cy={ly + 26} r={5} fill={C.water2} />
            </svg>
            <div style={{ position: "absolute", left: labelX, top: ly, opacity: p * (emph ? 1 : 0.42), transform: `translateX(${(1 - p) * 30}px)` }}>
              <div style={{ fontFamily: FONT, fontSize: 40, fontWeight: 700, color: C.text, letterSpacing: -0.5 }}>{c.title}</div>
              <div style={{ fontFamily: FONT, fontSize: 24, fontWeight: 500, color: C.dim, marginTop: 8 }}>{c.sub}</div>
            </div>
          </React.Fragment>
        );
      })}
    </AbsoluteFill>
  );
};

/* =============================== Scene 8 · Seamless Vector Menu Bar Popover (Silky Spring Sidebar) =============================== */

const POP_SIDEBAR = [
  { id: "antigravity", name: "Antigravity", val: "64%", accent: "#5479B2", paused: false, work: false },
  { id: "cursor", name: "Cursor", val: "68%", accent: "#7165AD", paused: false, work: false },
  { id: "workbuddy", name: "WorkBuddy", val: "3.2k", accent: "#498596", paused: false, work: false },
  { id: "deepseek", name: "DeepSeek", val: "¥29", accent: "#536DA8", paused: false, work: false },
  { id: "grokbot", name: "Grok Bot", val: "69%", accent: "#B37452", paused: false, work: false },
  { id: "gemini", name: "Gemini", val: "暂停", accent: "#597AB2", paused: true, work: false },
  { id: "claude", name: "Claude", val: "83%", accent: "#AD6E54", paused: false, work: false },
  { id: "codex", name: "Codex", val: "82%", accent: "#3E8C79", paused: false, work: true },
];

const POP_DETAILS: Record<
  string,
  {
    title: string;
    badge: string;
    sub: string;
    hero: string;
    accent: string;
    rows: [string, number, string, boolean][];
    note: string;
  }
> = {
  antigravity: {
    title: "Antigravity",
    badge: "AI Ultra",
    sub: "hello@agentgauge.app · Google AI Ultra",
    hero: "64%",
    accent: "#6B92CC",
    rows: [
      ["Gemini 4 (当前)", 72, "1h 41m", true],
      ["Gemini · 周限额", 64, "4d 22h", true],
      ["Claude/GPT · 周限额", 100, "6d 23h", true],
      ["Orchestrator", 72, "1h 41m", false],
      ["Gemini 3.8 Flash", 86, "1h 41m", false],
      ["Claude Opus 5.5", 41, "4h 55m", false],
    ],
    note: "可用积分 500",
  },
  cursor: {
    title: "Cursor",
    badge: "Ultra · 20x",
    sub: "code@agentgauge.app",
    hero: "68%",
    accent: "#8B7FD1",
    rows: [
      ["Cursor 月度额度 (主)", 68, "5d 4h", true],
      ["Auto 模型", 88, "5d 4h", false],
      ["Claude Opus 5.5", 46, "5d 4h", false],
      ["GPT-5.5 Codex", 74, "5d 4h", false],
    ],
    note: "按量计费 $0 / $200 上限",
  },
  grokbot: {
    title: "Grok Bot",
    badge: "Premium",
    sub: "grok@agentgauge.app",
    hero: "69%",
    accent: "#CC8966",
    rows: [
      ["Grok 周额度 (主)", 69, "5d 4h", true],
      ["Auto / 主力模型", 69, "5d 4h", false],
    ],
    note: "本周已使用 31% 的套餐额度",
  },
  codex: {
    title: "Codex",
    badge: "Pro Lite · 5x",
    sub: "dev@agentgauge.app",
    hero: "82%",
    accent: "#4CA892",
    rows: [
      ["5 小时窗口 (主)", 82, "3h 12m", true],
      ["周额度", 91, "5d 20h", true],
    ],
    note: "Credits $128.90 · 满额重置券 ×2",
  },
};

function makePopoverPath(w: number, h: number, topPad: number, r: number, cx: number) {
  const cw = 28;
  return `M ${r} ${topPad} L ${cx - cw} ${topPad} C ${cx - 16} ${topPad} ${cx - 9} 2 ${cx} 2 C ${cx + 9} 2 ${cx + 16} ${topPad} ${cx + cw} ${topPad} L ${w - r} ${topPad} A ${r} ${r} 0 0 1 ${w} ${topPad + r} L ${w} ${h - r} A ${r} ${r} 0 0 1 ${w - r} ${h} L ${r} ${h} A ${r} ${r} 0 0 1 0 ${h - r} L 0 ${topPad + r} A ${r} ${r} 0 0 1 ${r} ${topPad} Z`;
}

const MENUBAR_BEATS = [
  { idx: 0, id: "antigravity", from: 0.4, title: "左侧全局应用列表", sub: "鼠标上下滑过，选中胶囊丝滑跟随切换" },
  { idx: 1, id: "cursor", from: 2.0, title: "右侧多模型实时进度", sub: "独立进度条、套餐名牌与重置倒计时即时联动" },
  { idx: 4, id: "grokbot", from: 3.5, title: "一体成型原生弹窗质感", sub: "无接缝液态玻璃轮廓，暂停与刷新一键直达" },
  { idx: 7, id: "codex", from: 4.7, title: "工作态绿点实时感知", sub: "正在活跃运行的智能体自动点亮状态指示" },
];

const MenuBar: React.FC = () => {
  const { t, dur } = useTime();
  const barIn = interpolate(t, [0.0, 0.25], [0, 1], { ...clamp, easing: ease });
  const popOpen = useSpringAt(0.38, 16, 0.85, 165);
  const popVis = interpolate(t, [0.36, 0.54], [0, 1], clamp);
  const iconX = 1360;

  const W = 840;
  const TOP_CARET = 22;
  const H = 640 + TOP_CARET;
  const cardLeft = iconX - W / 2;
  const cardTop = 48;
  const caretCX = W / 2;
  const contour = makePopoverPath(W, H, TOP_CARET, 36, caretCX);

  const clickPulse = interpolate(t, [0.34, 0.68], [0, 1], { ...clamp, easing: ease });
  const isClicking = t >= 0.32 && t <= 0.43;

  const beatIdx = MENUBAR_BEATS.reduce((acc, b, i) => (t >= b.from ? i : acc), 0);
  const activeBeat = MENUBAR_BEATS[beatIdx];
  const detail = POP_DETAILS[activeBeat.id];

  // Smooth spring-like row index for the sliding selection pill
  const selRowFloat = seg(t, [
    [0.0, 0],
    [1.85, 0],
    [2.12, 1],
    [3.35, 1],
    [3.65, 4],
    [4.55, 4],
    [4.85, 7],
    [6.0, 7],
  ]);

  const rowStride = 67;
  const rowBaseY = cardTop + TOP_CARET + 16 + 31;
  const px = seg(t, [
    [0.0, 1600],
    [0.32, iconX],
    [0.55, iconX],
    [0.92, cardLeft + 160],
    [5.6, cardLeft + 165],
    [6.0, 1640],
  ]);
  const py = seg(t, [
    [0.0, 250],
    [0.32, 24],
    [0.55, 24],
    [0.92, rowBaseY + 0 * rowStride],
    [1.85, rowBaseY + 0 * rowStride],
    [2.12, rowBaseY + 1 * rowStride],
    [3.35, rowBaseY + 1 * rowStride],
    [3.65, rowBaseY + 4 * rowStride],
    [4.55, rowBaseY + 4 * rowStride],
    [4.85, rowBaseY + 7 * rowStride],
    [5.6, rowBaseY + 7 * rowStride],
    [6.0, 560],
  ]);

  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.3, 0.3) }}>
      <Wallpaper painting="judith" dim={0.22} zoom={1.04} />
      <DesktopChrome
        plaque="Martin Johnson Heade · Point Judith, 1867"
        gaugeActive={t >= 0.34}
        iconX={iconX}
        barOpacity={barIn}
      />

      {t >= 0.34 && t < 0.7 && (
        <div
          style={{
            position: "absolute",
            left: iconX - 24 - clickPulse * 18,
            top: 6 - clickPulse * 18,
            width: 48 + clickPulse * 36,
            height: 36 + clickPulse * 36,
            borderRadius: 18,
            border: `2px solid rgba(141,184,255,${(1 - clickPulse) * 0.85})`,
          }}
        />
      )}

      {/* Left Editorial Copy */}
      <div style={{ position: "absolute", left: 104, top: 186, width: 740 }}>
        <Eyebrow text="Menu Bar Dashboard · 丝滑跟随" delay={0.12} />
        <div style={{ height: 18 }} />
        <Reveal text="顶部菜单栏，" delay={0.18} size={72} weight={700} stagger={0.035} letterSpacing={-1.6} />
        <Reveal text="全局额度一触即达。" delay={0.42} size={72} weight={700} stagger={0.035} letterSpacing={-1.6} gradient />
        <div style={{ height: 38 }} />

        {MENUBAR_BEATS.map((item, idx) => {
          const p = interpolate(t, [0.5 + idx * 0.18, 0.92 + idx * 0.18], [0, 1], { ...clamp, easing: ease });
          const emph = idx === beatIdx;
          return (
            <div
              key={item.id}
              style={{
                display: "flex",
                alignItems: "flex-start",
                gap: 18,
                marginBottom: 18,
                padding: "14px 18px",
                borderRadius: 16,
                background: emph ? "rgba(255,255,255,0.08)" : "rgba(255,255,255,0.02)",
                border: emph ? "1px solid rgba(141,184,255,0.34)" : "1px solid rgba(255,255,255,0.06)",
                opacity: p * (emph ? 1 : 0.58),
                transform: `translateX(${(1 - p) * 26}px)`,
              }}
            >
              <div
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: 99,
                  marginTop: 12,
                  background: emph ? C.water2 : "rgba(255,255,255,0.35)",
                  boxShadow: emph ? `0 0 14px ${C.water2}` : "none",
                  flexShrink: 0,
                }}
              />
              <div>
                <div style={{ fontFamily: FONT, fontSize: 28, fontWeight: 700, color: C.text, letterSpacing: -0.4 }}>{item.title}</div>
                <div style={{ fontFamily: FONT, fontSize: 20, fontWeight: 500, color: C.dim, marginTop: 4 }}>{item.sub}</div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Seamless Single-Piece Vector MenuBarPopoverView */}
      <div
        style={{
          position: "absolute",
          left: cardLeft,
          top: cardTop,
          width: W,
          height: H,
          opacity: popVis,
          transform: `scale(${interpolate(popOpen, [0, 1], [0.92, 1])}) translateY(${interpolate(popOpen, [0, 1], [-12, 0])}px)`,
          transformOrigin: "50% 0%",
          filter: "drop-shadow(0 38px 76px rgba(0,0,0,0.65))",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            paddingTop: TOP_CARET,
            background: "rgba(26,27,32,0.90)",
            backdropFilter: "blur(38px) saturate(180%)",
            clipPath: `path("${contour}")`,
            WebkitClipPath: `path("${contour}")`,
            display: "flex",
            flexDirection: "column",
            fontFamily: FONT,
            color: "#fff",
          }}
        >
          <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
            {/* Left Sidebar with Silky Sliding Selection Pill */}
            <div
              style={{
                width: 312,
                padding: 15,
                background: "rgba(255,255,255,0.022)",
                borderRight: "1.2px solid rgba(255,255,255,0.09)",
                position: "relative",
              }}
            >
              {/* Sliding selection pill */}
              <div
                style={{
                  position: "absolute",
                  left: 15,
                  right: 15,
                  top: 15 + selRowFloat * rowStride,
                  height: 61,
                  borderRadius: 16,
                  background: "rgba(255,255,255,0.095)",
                  boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.09)",
                }}
              >
                <div
                  style={{
                    position: "absolute",
                    left: 6,
                    top: "50%",
                    width: 5.5,
                    height: 28,
                    marginTop: -14,
                    borderRadius: 99,
                    background: detail.accent,
                  }}
                />
              </div>

              {POP_SIDEBAR.map((r, i) => {
                const isSel = Math.round(selRowFloat) === i;
                return (
                  <div
                    key={r.id}
                    style={{
                      position: "relative",
                      height: 61,
                      marginBottom: 6,
                      padding: "0 14px 0 20px",
                      display: "flex",
                      alignItems: "center",
                      gap: 14,
                      opacity: r.paused ? 0.45 : 1,
                    }}
                  >
                    <div style={{ position: "relative", width: 38, height: 38 }}>
                      <Icon name={r.id} size={38} />
                      {r.work && (
                        <span
                          style={{
                            position: "absolute",
                            right: -2,
                            bottom: -2,
                            width: 11,
                            height: 11,
                            borderRadius: 99,
                            background: "#30d158",
                            border: "2px solid #1b1c20",
                          }}
                        />
                      )}
                    </div>
                    <span style={{ flex: 1, fontSize: 22, fontWeight: isSel ? 700 : 500, color: isSel ? "#fff" : "rgba(255,255,255,0.8)" }}>
                      {r.name}
                    </span>
                    <span style={{ fontSize: r.paused ? 17 : 20, fontWeight: isSel ? 700 : 600, color: isSel ? "#fff" : "rgba(255,255,255,0.62)", fontVariantNumeric: "tabular-nums" }}>
                      {r.val}
                    </span>
                  </div>
                );
              })}
            </div>

            {/* Right Detail Column */}
            <div style={{ flex: 1, padding: "22px 24px", display: "flex", flexDirection: "column", gap: 18 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                <Icon name={activeBeat.id} size={52} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <span style={{ fontSize: 25, fontWeight: 700 }}>{detail.title}</span>
                    <span
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        gap: 7,
                        padding: "3px 12px",
                        borderRadius: 999,
                        background: "rgba(62,70,88,0.85)",
                        border: "1px solid rgba(255,255,255,0.2)",
                        fontSize: 17,
                        fontWeight: 600,
                      }}
                    >
                      <span style={{ width: 8, height: 8, borderRadius: 99, background: detail.accent }} />
                      {detail.badge}
                    </span>
                  </div>
                  <div style={{ fontSize: 18, color: "rgba(255,255,255,0.5)", marginTop: 3 }}>{detail.sub}</div>
                </div>
                <span style={{ fontSize: 28, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>{detail.hero}</span>
              </div>

              <div style={{ height: 1, background: "rgba(255,255,255,0.09)" }} />

              <div style={{ display: "flex", flexDirection: "column", gap: 15, flex: 1 }}>
                {detail.rows.map(([lbl, pct, cd, pri]) => (
                  <div key={lbl} style={{ display: "flex", flexDirection: "column", gap: 7 }}>
                    <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
                      <span style={{ flex: 1, fontSize: 20, fontWeight: pri ? 600 : 400, color: pri ? "#fff" : "rgba(255,255,255,0.68)" }}>
                        {lbl}
                      </span>
                      <span style={{ fontSize: 20, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>{pct}%</span>
                      <span style={{ fontSize: 17, color: "rgba(255,255,255,0.42)", minWidth: 74, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>
                        {cd}
                      </span>
                    </div>
                    <div style={{ height: pri ? 9 : 7.5, borderRadius: 99, background: "rgba(255,255,255,0.09)", overflow: "hidden" }}>
                      <div style={{ width: `${pct}%`, height: "100%", borderRadius: 99, background: detail.accent }} />
                    </div>
                  </div>
                ))}

                <div
                  style={{
                    marginTop: "auto",
                    padding: "9px 14px",
                    borderRadius: 12,
                    background: "rgba(255,255,255,0.05)",
                    fontSize: 18,
                    color: "rgba(255,255,255,0.64)",
                  }}
                >
                  ✦ {detail.note}
                </div>
              </div>
            </div>
          </div>

          {/* Bottom Bar */}
          <div
            style={{
              height: 74,
              padding: "0 20px",
              borderTop: "1.2px solid rgba(255,255,255,0.09)",
              display: "flex",
              alignItems: "center",
              gap: 14,
            }}
          >
            <div style={{ padding: "8px 18px", borderRadius: 999, background: "rgba(255,255,255,0.08)", border: "1px solid rgba(255,255,255,0.12)", display: "flex", alignItems: "center", gap: 9, fontSize: 19, fontWeight: 500 }}>
              <span style={{ width: 11, height: 11, borderRadius: 99, background: "#30d158" }} />
              运行中
            </div>
            <div style={{ padding: "8px 18px", borderRadius: 999, background: "rgba(255,255,255,0.08)", border: "1px solid rgba(255,255,255,0.12)", fontSize: 19, fontWeight: 500 }}>
              ↻ 刷新
            </div>
            <div style={{ flex: 1 }} />
            <div style={{ padding: "8px 18px", borderRadius: 999, background: "rgba(255,255,255,0.08)", border: "1px solid rgba(255,255,255,0.12)", fontSize: 19, fontWeight: 500 }}>
              设置
            </div>
          </div>
        </div>

        {/* Continuous Single-Piece Specular Rim (Zero Caret Seam!) */}
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
          <path d={contour} fill="none" stroke="rgba(255,255,255,0.18)" strokeWidth={1.8} strokeLinejoin="round" />
        </svg>
      </div>

      <Pointer x={px} y={py} opacity={interpolate(t, [0, 0.16], [0, 1], clamp)} scale={isClicking ? 0.88 : 1} />
    </AbsoluteFill>
  );
};

/* =============================== Scene 9 · Settings (v1.2.0) =============================== */

const Settings: React.FC = () => {
  const { t, dur } = useTime();
  const win = useSpringAt(0.15, 20, 1, 90);
  const sheet = useSpringAt(1.55, 20, 1, 90);
  const sw = 872 * 0.82;
  const sh = 1056 * 0.82;
  const tw = 968 * 0.74;
  const th = 1056 * 0.74;
  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.3, 0.3) }}>
      <Wallpaper painting="monet" dim={0.34} />
      <DesktopChrome plaque="Claude Monet · Water Lilies, c. 1915" />
      <div style={{ position: "absolute", left: 110, top: 360, width: 560 }}>
        <Eyebrow text="AgentGauge v1.2.0 · Native macOS" delay={0.1} />
        <div style={{ height: 16 }} />
        <Reveal text="原生设置，" delay={0.2} size={76} weight={700} stagger={0.04} letterSpacing={-1.5} />
        <Reveal text="一切随心。" delay={0.5} size={76} weight={700} stagger={0.04} letterSpacing={-1.5} gradient />
        <div style={{ height: 26 }} />
        <Reveal text="支持 30+ 主流模型与套餐 · 11 种精选样式" delay={1.0} size={26} weight={500} color={C.dim} stagger={0.012} />
        <div style={{ height: 8 }} />
        <Reveal text="订阅配额、积分与 API 余额直连 · 实时预览" delay={1.3} size={26} weight={500} color={C.dim} stagger={0.012} />
      </div>
      <Img
        src={staticFile("shots/settings_demo_0_436x528.png")}
        style={{
          position: "absolute",
          left: 690,
          top: (1080 - sh) / 2 + 16,
          width: sw,
          height: sh,
          opacity: win,
          transform: `perspective(1600px) translateY(${(1 - win) * 140}px) rotateX(${(1 - win) * 12}deg)`,
          filter: "drop-shadow(0 40px 80px rgba(0,0,0,0.6))",
        }}
      />
      <Img
        src={staticFile("shots/studio_demo_0_484x528.png")}
        style={{
          position: "absolute",
          left: 1170,
          top: 212,
          width: tw,
          height: th,
          opacity: sheet,
          transform: `translateX(${(1 - sheet) * 220}px) scale(${interpolate(sheet, [0, 1], [0.96, 1])})`,
          filter: "drop-shadow(0 50px 90px rgba(0,0,0,0.7))",
        }}
      />
    </AbsoluteFill>
  );
};

/* =============================== Scene 10 · Supported 29 Authentic Vendors =============================== */

const ALL_APPS = [
  "codex", "antigravity", "claude", "cursor", "grokbot", "windsurf", "workbuddy", "trae", "kiro", "vscode",
  "qoder", "zed", "warp", "devin", "intellij",
  "pycharm", "webstorm", "gemini", "grok", "deepseek", "kimi", "chatglm", "qwen", "doubao", "minimax",
  "perplexity", "lechat", "manus", "poe",
];

const ROW_MASK = "linear-gradient(90deg, transparent 0%, black 14%, black 86%, transparent 100%)";
const AppsRow: React.FC<{ items: string[]; y: number; dir: 1 | -1; t: number; size: number; step: number }> = ({ items, y, dir, t, size, step }) => {
  const span = items.length * step;
  const shift = (((t * 86 * dir) % span) + span) % span;
  const tripled = [...items, ...items, ...items];
  return (
    <div style={{ position: "absolute", left: 0, top: y, width: 1920, height: size + 20, WebkitMaskImage: ROW_MASK, maskImage: ROW_MASK }}>
      <div style={{ position: "absolute", left: -span + shift, display: "flex", gap: step - size }}>
        {tripled.map((n, i) => (
          <Icon key={`${n}-${i}`} name={n} size={size} style={{ filter: "drop-shadow(0 12px 22px rgba(0,0,0,0.45))" }} />
        ))}
      </div>
    </div>
  );
};

const Apps: React.FC = () => {
  const { t, dur } = useTime();
  const count = Math.round(interpolate(t, [0.2, 1.65], [0, 30], { ...clamp, easing: ease }));
  const size = 114;
  const step = size + 40;
  const rowA = ALL_APPS.slice(0, 15);
  const rowB = ALL_APPS.slice(15);
  return (
    <AbsoluteFill style={{ opacity: fadeIO(t, dur, 0.3, 0.3) }}>
      <Wallpaper painting="fuji" dim={0.62} />
      <AppsRow items={rowA} y={146} dir={1} t={t} size={size} step={step} />
      <AppsRow items={rowB} y={794} dir={-1} t={t} size={size} step={step} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <div
          style={{
            fontFamily: FONT,
            fontSize: 224,
            fontWeight: 700,
            letterSpacing: -8,
            lineHeight: 1,
            backgroundImage: `linear-gradient(100deg, ${C.water1}, ${C.water2})`,
            WebkitBackgroundClip: "text",
            backgroundClip: "text",
            WebkitTextFillColor: "transparent",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {count}+
        </div>
        <div style={{ height: 10 }} />
        <Reveal text="主流大模型与 Coding Plan · 持续接入更多" delay={0.45} size={48} weight={700} align="center" stagger={0.025} />
        <div style={{ height: 14 }} />
        <Reveal text="Claude · Codex · Cursor · Antigravity · Windsurf · Copilot · DeepSeek · Kimi · GLM · Qwen …" delay={0.9} size={25} weight={500} color={C.dim} align="center" stagger={0.008} letterSpacing={0.3} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/* =============================== Scene 11 · Outro (v1.2.0 + usage.komorebi.date) =============================== */

const Outro: React.FC = () => {
  const { t, dur } = useTime();
  const pop = useSpringAt(0.0, 15, 0.9, 110);
  const urlIn = interpolate(t, [1.55, 2.1], [0, 1], { ...clamp, easing: ease });
  const black = interpolate(t, [dur - 0.85, dur], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: interpolate(t, [0, 0.3], [0, 1], clamp) }}>
      <Wallpaper painting="yosemite" dim={0.46} />
      <Ripples cx={960} cy={328} start={0.05} count={4} />
      <div style={{ position: "absolute", left: 960 - 108, top: 328 - 108, transform: `scale(${interpolate(pop, [0, 1], [0.6, 1])})`, opacity: pop }}>
        <Icon name="agentgauge" size={216} style={{ filter: "drop-shadow(0 30px 60px rgba(20,30,60,0.52))" }} />
      </div>
      <div style={{ position: "absolute", top: 472, width: "100%", display: "flex", justifyContent: "center" }}>
        <Reveal text="AgentGauge" delay={0.35} size={108} weight={700} align="center" letterSpacing={-3.5} stagger={0.03} />
      </div>
      <div style={{ position: "absolute", top: 608, width: "100%", display: "flex", justifyContent: "center" }}>
        <Reveal text="AI 额度，清澈如水。" delay={0.95} size={54} weight={650} align="center" gradient stagger={0.05} />
      </div>

      {/* Official URL & v1.2.0 Download Pill */}
      <div
        style={{
          position: "absolute",
          top: 726,
          width: "100%",
          display: "flex",
          justifyContent: "center",
          opacity: urlIn,
          transform: `translateY(${(1 - urlIn) * 20}px)`,
        }}
      >
        <div
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 16,
            padding: "14px 32px",
            borderRadius: 999,
            background: "rgba(255,255,255,0.94)",
            color: "#141413",
            fontFamily: FONT,
            fontSize: 27,
            fontWeight: 700,
            letterSpacing: -0.4,
            boxShadow: "0 24px 60px rgba(0,0,0,0.45)",
          }}
        >
          <span>Download v1.2.0</span>
          <span style={{ width: 5, height: 5, borderRadius: 99, background: "rgba(20,20,19,0.35)" }} />
          <span style={{ fontWeight: 500, color: "#4a4945" }}>usage.komorebi.date</span>
        </div>
      </div>

      <div style={{ position: "absolute", top: 832, width: "100%", display: "flex", justifyContent: "center" }}>
        <Reveal text="macOS 26 Tahoe 原生  ·  Metal 实时渲染  ·  本地零打扰" delay={1.75} size={24} weight={500} color={C.faint} align="center" stagger={0.012} letterSpacing={0.8} />
      </div>
      <AbsoluteFill style={{ backgroundColor: "#000", opacity: black }} />
    </AbsoluteFill>
  );
};

/* =============================== Timeline (62s) =============================== */

export const SCENES: { from: number; to: number; C: React.FC }[] = [
  { from: 0, to: 4, C: Hook },
  { from: 4, to: 8, C: Brand },
  { from: 8, to: 16, C: HDShowcase },
  { from: 16, to: 25, C: DockDemo },
  { from: 25, to: 31, C: Macro },
  { from: 31, to: 36, C: Styles },
  { from: 36, to: 42, C: Dashboard },
  { from: 42, to: 48, C: MenuBar },
  { from: 48, to: 53, C: Settings },
  { from: 53, to: 57, C: Apps },
  { from: 57, to: 62, C: Outro },
];

export const TOTAL_SECONDS = 62;

export const AgentGaugePromo: React.FC = () => {
  const { fps } = useVideoConfig();
  const [fontHandle] = useState(() => delayRender("Load Cabinet Grotesk"));

  useEffect(() => {
    let done = false;
    const finish = () => {
      if (!done) {
        done = true;
        continueRender(fontHandle);
      }
    };
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = FONTSHARE_CSS;
    link.onload = () => {
      Promise.race([
        Promise.all([
          document.fonts.load('700 72px "Cabinet Grotesk"'),
          document.fonts.load('500 28px "Cabinet Grotesk"'),
        ]),
        new Promise((r) => setTimeout(r, 2000)),
      ]).finally(finish);
    };
    link.onerror = finish;
    document.head.appendChild(link);
    const timer = setTimeout(finish, 3000);
    return () => clearTimeout(timer);
  }, [fontHandle]);

  const overlap = 0.25;
  return (
    <AbsoluteFill style={{ backgroundColor: C.bg }}>
      {SCENES.map(({ from, to, C: Scene }, i) => {
        const start = i === 0 ? 0 : from - overlap;
        const end = i === SCENES.length - 1 ? to : to + overlap;
        return (
          <Sequence key={i} from={Math.round(start * fps)} durationInFrames={Math.round((end - start) * fps)} premountFor={fps}>
            <Scene />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
