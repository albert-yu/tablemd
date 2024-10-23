import { spaceMonoRegularAtlas } from "./space-mono-regular-atlas";

/**
 * Source: https://stackoverflow.com/a/21797381
 */
function base64ToByteArray(base64: string): Uint8Array {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

export const spaceMonoFontAtlas = base64ToByteArray(spaceMonoRegularAtlas);
