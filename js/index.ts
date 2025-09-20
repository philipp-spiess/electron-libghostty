import native from "./native-loader.js";

export interface GhosttyFrame {
  x: number;
  y: number;
  width: number;
  height: number;
  scale?: number;
}

export type GhosttyEvent =
  | { type: "set-title"; surfaceId: number; title: string }
  | { type: "bell"; surfaceId: number }
  | { type: "surface-exit"; surfaceId: number; processAlive: boolean; exitCode: number }
  | { type: "clipboard-read"; surfaceId: number; requestId: number; clipboard: string }
  | { type: "clipboard-write"; surfaceId: number; text: string; clipboard: string; confirm: boolean };

interface GhosttyBindings {
  ensureInitialized(): boolean;
  createSurface(handle: Buffer, frame: GhosttyFrame, scale?: number): number;
  resizeSurface(id: number, frame: GhosttyFrame, scale?: number): boolean;
  destroySurface(id: number): boolean;
  setFocus(id: number, focus: boolean): boolean;
  setOccluded(id: number, occluded: boolean): boolean;
  sendKey(id: number, event: GhosttyKeyEvent): boolean;
  sendText(id: number, text: string): boolean;
  setEventHandler(handler: (event: GhosttyEvent) => void): void;
}

export interface GhosttyKeyEvent {
  action: number;
  mods: number;
  consumedMods: number;
  keycode: number;
  text?: string;
  codepoint?: number;
  composing?: boolean;
}

class GhosttyHost {
  private readonly bindings?: GhosttyBindings;

  constructor() {
    if (process.platform === "darwin") {
      this.bindings = native as GhosttyBindings;
      this.bindings.ensureInitialized();
    }
  }

  create(handle: Buffer, frame: GhosttyFrame, scale?: number): number {
    if (!Buffer.isBuffer(handle)) {
      throw new Error("[ghostty.create] handle must be a Buffer");
    }
    if (!this.bindings) return -1;
    return this.bindings.createSurface(handle, frame, scale);
  }

  resize(
    id: number,
    arg1: Buffer | GhosttyFrame,
    arg2?: GhosttyFrame | number,
    arg3?: number,
  ): boolean {
    if (!this.bindings) return false;

    let frame: GhosttyFrame;
    let scale: number | undefined;

    if (Buffer.isBuffer(arg1)) {
      frame = arg2 as GhosttyFrame;
      scale = typeof arg3 === "number" ? arg3 : undefined;
    } else {
      frame = arg1 as GhosttyFrame;
      scale = typeof arg2 === "number" ? arg2 : undefined;
    }

    return this.bindings.resizeSurface(id, frame, scale);
  }

  destroy(id: number): boolean {
    if (!this.bindings) return false;
    return this.bindings.destroySurface(id);
  }

  setFocus(id: number, focus: boolean): boolean {
    if (!this.bindings) return false;
    return this.bindings.setFocus(id, focus);
  }

  setOccluded(id: number, occluded: boolean): boolean {
    if (!this.bindings) return false;
    return this.bindings.setOccluded(id, occluded);
  }

  sendKey(id: number, event: GhosttyKeyEvent): boolean {
    if (!this.bindings) return false;
    return this.bindings.sendKey(id, event);
  }

  sendText(id: number, text: string): boolean {
    if (!this.bindings) return false;
    return this.bindings.sendText(id, text);
  }

  onEvent(handler: (event: GhosttyEvent) => void): void {
    if (!this.bindings) return;
    this.bindings.setEventHandler(handler);
  }

  // Legacy alias methods ----------------------------------------------------

  createOverlay(handle: Buffer, frame: GhosttyFrame): number {
    return this.create(handle, frame);
  }

  updateOverlay(id: number, frame: GhosttyFrame): void {
    this.resize(id, frame);
  }

  removeOverlay(id: number): void {
    this.destroy(id);
  }
}

const ghosttyHost: GhosttyHost = new GhosttyHost();

export default ghosttyHost;
