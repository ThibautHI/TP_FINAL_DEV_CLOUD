import { test, expect } from "bun:test";

test("Validation de coordonnées GPS", () => {
  const coord = { lat: 43.6107, lng: 3.8767 };
  expect(coord.lat).toBeGreaterThanOrEqual(-90);
  expect(coord.lat).toBeLessThanOrEqual(90);
  expect(coord.lng).toBeGreaterThanOrEqual(-180);
  expect(coord.lng).toBeLessThanOrEqual(180);
});
