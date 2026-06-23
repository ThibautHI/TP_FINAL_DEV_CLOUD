import { test, expect } from "bun:test";

function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * 
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

test("Calcul de la distance de Haversine", () => {
  const dist = calculateDistance(43.6107, 3.8767, 43.6300, 3.8600);
  expect(dist).toBeGreaterThan(1);
  expect(dist).toBeLessThan(5);
});
