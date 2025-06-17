import { defineConfig } from "tsdown";

export default defineConfig({
  entry: "js/index.ts",
  format: ["cjs", "esm"],
  dts: true,
  clean: true,
  outDir: "dist",
  target: "node18",
  platform: "node",
  tsconfig: "tsconfig.build.json",
  external: ["bindings", "node-addon-api", "node-gyp-build", "electron"],
});
