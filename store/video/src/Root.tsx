import {Composition} from "remotion";
import {PROMO_FRAMES, PromoVideo} from "./Composition";
import "./font";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="ScalingLawsPromo"
      component={PromoVideo}
      durationInFrames={PROMO_FRAMES}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};
