import { test, expect } from "bun:test";

test("Calcul mathématique de base", () => {
  expect(1 + 1).toBe(2);
});

test("Structure JSON de base", () => {
  const obj = { app: "greenlogistics", active: true };
  expect(obj.app).toBe("greenlogistics");
  expect(obj.active).toBe(true);
});
