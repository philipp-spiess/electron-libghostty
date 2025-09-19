import native from "./native-loader.js";

export interface OverlayFrame {
  x: number;
  y: number;
  width: number;
  height: number;
  scale?: number;
}

export interface NativeOverlayBindings {
  createOverlay(handle: Buffer, frame: OverlayFrame): number;
  updateOverlay(id: number, frame: OverlayFrame): void;
  removeOverlay(id: number): void;
}

class NativeOverlay {
  private readonly bindings?: NativeOverlayBindings;

  constructor() {
    if (process.platform === "darwin") {
      this.bindings = native as NativeOverlayBindings;
    }
  }

  create(handle: Buffer, frame: OverlayFrame): number {
    if (!Buffer.isBuffer(handle)) {
      throw new Error("[nativeOverlay.create] handle must be a Buffer");
    }
    if (!this.bindings) return -1;
    return this.bindings.createOverlay(handle, frame);
  }

  update(id: number, frame: OverlayFrame): void {
    if (!this.bindings) return;
    this.bindings.updateOverlay(id, frame);
  }

  remove(id: number): void {
    if (!this.bindings) return;
    this.bindings.removeOverlay(id);
  }
}

const nativeOverlay: NativeOverlay = new NativeOverlay();

export default nativeOverlay;
