import { expect, test } from "bun:test";
import { RESTART_DELAYS_MS, RestartPolicy, SETTLED_AFTER_MS } from "../src/code-editor/serverRestarts";

test("a server that keeps ending early is retried with longer waits, then given up on", () => {
  const policy = new RestartPolicy();
  const waits = RESTART_DELAYS_MS.map(() => policy.delayAfterExit(200));
  expect(waits).toEqual([...RESTART_DELAYS_MS]);
  expect(policy.delayAfterExit(200)).toBeUndefined();
  expect(policy.delayAfterExit(200)).toBeUndefined();
});

test("a server that ran properly starts the waits over when it ends", () => {
  const policy = new RestartPolicy();
  policy.delayAfterExit(200);
  policy.delayAfterExit(200);
  expect(policy.delayAfterExit(SETTLED_AFTER_MS)).toBe(RESTART_DELAYS_MS[0]);
  expect(policy.delayAfterExit(200)).toBe(RESTART_DELAYS_MS[1]);
});

test("a server given up on is tried again once it has run properly", () => {
  const policy = new RestartPolicy();
  RESTART_DELAYS_MS.forEach(() => policy.delayAfterExit(0));
  expect(policy.delayAfterExit(0)).toBeUndefined();
  expect(policy.delayAfterExit(SETTLED_AFTER_MS + 1)).toBe(RESTART_DELAYS_MS[0]);
});
