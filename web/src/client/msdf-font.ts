/**
 * The kerning map stores a spare map of character ID pairs with an associated
 * X offset that should be applied to the character spacing when the second
 * character ID is rendered after the first.
 */
export type KerningMap = Map<number, Map<number, number>>;

export type Kerning = {
  first: number;
  second: number;
  amount: number;
};

export interface MsdfChar {
  id: number;
  index: number;
  char: string;
  width: number;
  height: number;
  xoffset: number;
  yoffset: number;
  xadvance: number;
  chnl: number;
  x: number;
  y: number;
  page: number;
  charIndex: number;
}

export class MsdfFont {
  charCount: number;
  defaultChar: MsdfChar;
  constructor(
    public pipeline: GPURenderPipeline,
    public bindGroup: GPUBindGroup,
    public lineHeight: number,
    public chars: { [x: number]: MsdfChar },
    public kernings: KerningMap,
  ) {
    const charArray = Object.values(chars);
    this.charCount = charArray.length;
    this.defaultChar = charArray[0];
  }

  getChar(charCode: number): MsdfChar {
    let char = this.chars[charCode];
    if (!char) {
      char = this.defaultChar;
    }
    return char;
  }

  /**
   * Gets the distance in pixels a line should advance for a given character code. If the upcoming
   * character code is given any kerning between the two characters will be taken into account.
   */
  getXAdvance(charCode: number, nextCharCode: number = -1): number {
    const char = this.getChar(charCode);
    if (nextCharCode >= 0) {
      const kerning = this.kernings.get(charCode);
      if (kerning) {
        return char.xadvance + (kerning.get(nextCharCode) ?? 0);
      }
    }
    return char.xadvance;
  }
}
