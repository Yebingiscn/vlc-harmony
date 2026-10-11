// Code-only feature switch; does not force a particular display refresh rate.
export const ENABLE_VIDEO_VARIABLE_REFRESH: boolean = true;

/** Disable immediately for interaction, enable only after the scene settles. */
export class VideoRefreshPolicy {
  private eligible: boolean = false;
  private applied: boolean = false;
  private blockedUntil: number = 0;
  private timer: number = -1;
  private apply: (allowed: boolean) => void;

  constructor(apply: (allowed: boolean) => void) {
    this.apply = apply;
  }

  update(eligible: boolean): void {
    this.eligible = ENABLE_VIDEO_VARIABLE_REFRESH && eligible;
    if (!this.eligible) {
      this.clearTimer();
      this.setAllowed(false);
    } else if (!this.applied && this.timer === -1) {
      const delay: number = Math.max(800, this.blockedUntil - Date.now());
      this.timer = setTimeout(() => {
        this.timer = -1;
        if (this.eligible) {
          this.setAllowed(true);
        }
      }, delay);
    }
  }

  blockFor(millis: number): void {
    this.blockedUntil = Math.max(this.blockedUntil, Date.now() + millis);
    this.clearTimer();
    this.setAllowed(false);
    this.update(this.eligible);
  }

  dispose(): void {
    this.update(false);
    this.apply(false);
  }

  private setAllowed(allowed: boolean): void {
    if (this.applied !== allowed) {
      this.applied = allowed;
      this.apply(allowed);
    }
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}
