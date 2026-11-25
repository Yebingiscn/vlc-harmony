import { LengthMetrics } from '@kit.ArkUI';

// Match the native bottom-sheet profile. A bottom panel stays flush with the screen edge.
const RADIUS_VP: number = 32;

export const NATIVE_BOTTOM_SHEET_RADIUS: LengthMetrics = LengthMetrics.vp(RADIUS_VP);
export const BOTTOM_SHEET_TOP_CORNERS: BorderRadiuses = {
  topLeft: RADIUS_VP,
  topRight: RADIUS_VP,
  bottomLeft: 0,
  bottomRight: 0,
};
