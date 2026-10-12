/** How long to wait before starting a language server again, by how many times in a row it ended early. */
export const RESTART_DELAYS_MS: readonly number[] = [1_000, 5_000, 15_000, 60_000];

/** A server that ran this long had started properly, so its next exit starts the delays over. */
export const SETTLED_AFTER_MS = 30_000;

/**
 * Decides when a language server that ended is started again. A server that
 * keeps ending right after it starts (it is not installed on the host, the
 * host cannot be reached) is given up on after the last delay.
 */
export class RestartPolicy {
  private earlyExits = 0;

  /** The wait before the next start, or undefined when it is time to stop trying. */
  delayAfterExit(ranForMs: number): number | undefined {
    if (ranForMs >= SETTLED_AFTER_MS) {
      this.earlyExits = 0;
    }
    const delay = RESTART_DELAYS_MS[this.earlyExits];
    if (delay !== undefined) {
      this.earlyExits += 1;
    }
    return delay;
  }
}
