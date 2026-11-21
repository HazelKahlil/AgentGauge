import React from "react";
import { Composition } from "remotion";
import { AgentGaugePromo, TOTAL_SECONDS } from "./Promo";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="AgentGaugePromo"
      component={AgentGaugePromo}
      durationInFrames={TOTAL_SECONDS * 30}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};
