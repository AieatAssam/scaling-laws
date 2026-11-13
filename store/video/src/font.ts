import {loadFont} from "@remotion/fonts";
import {staticFile} from "remotion";

// The game's pixel font (assets/fonts/PressStart2P-Regular.ttf, OFL).
// One identifier, no spaces or digits-first: it is used unquoted in CSS font-family.
export const PIXEL = "PressStart2P";

await loadFont({family: PIXEL, url: staticFile("fonts/PressStart2P-Regular.ttf")});
