import { test, expect } from "bun:test";

test("Interpolation de coordonnées pour simulation", () => {
  const start_lat = 43.6000;
  const dest_lat = 43.6100;
  const ratio = 0.5;
  const interpolated = start_lat + (dest_lat - start_lat) * ratio;
  expect(interpolated).toBeCloseTo(43.6050, 4);
});
