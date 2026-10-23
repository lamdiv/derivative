export const swipeQuietMs = 160;
export type SpaceEdge = 'first' | 'last' | null;

/** Wheel events have no portable gesture phases, so lock an axis until a quiet gap. */
export class SpaceSwipeGesture {
  private last = -Infinity;
  private x = 0;
  private y = 0;
  private axis: 'pending' | 'horizontal' | 'vertical' = 'pending';
  private committed = 0;
  private reverse = 0;

  reset() {
    this.last = -Infinity; this.x = 0; this.y = 0;
    this.axis = 'pending'; this.committed = 0; this.reverse = 0;
  }

  update(dx: number, dy: number, now: number, index: number, count: number) {
    if (now - this.last > swipeQuietMs) this.reset();
    this.last = now;
    this.x += dx; this.y += dy;
    if (this.axis === 'pending') {
      if (Math.abs(this.x) >= 8 && Math.abs(this.x) > Math.abs(this.y) * 1.15) this.axis = 'horizontal';
      else if (Math.abs(this.y) >= 8 && Math.abs(this.y) > Math.abs(this.x) * 1.25) this.axis = 'vertical';
    }
    if (this.axis !== 'horizontal') return { consumed:false, x:0, edge:null as SpaceEdge, step:0 };
    // Ignore same-direction momentum. A deliberate reversal can start immediately.
    if (this.committed) {
      if (Math.sign(dx) === -this.committed) this.reverse += dx;
      else this.reverse = 0;
      if (Math.abs(this.reverse) < 24) return { consumed:true, x:0, edge:null as SpaceEdge, step:0 };
      this.x = this.reverse; this.y = 0; this.reverse = 0; this.committed = 0;
    }
    const sign = Math.sign(this.x);
    const outside = index + sign < 0 || index + sign >= count;
    const edge: SpaceEdge = outside ? sign < 0 ? 'first' : 'last' : null;
    const x = -sign * (outside ? 28 * (1 - Math.exp(-Math.abs(this.x) / 75)) : Math.min(48, Math.abs(this.x) * .7));
    if (!outside && Math.abs(this.x) >= 52) {
      this.committed = sign;
      return { consumed:true, x:0, edge:null as SpaceEdge, step:sign };
    }
    return { consumed:true, x, edge, step:0 };
  }
}
