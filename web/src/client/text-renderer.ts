import {
  MsdfFont,
  type Kerning,
  type KerningMap,
  type MsdfChar,
} from "./msdf-font";
import msdfTextWGSL from "./shaders/msdf-text.wgsl";
import { MsdfText, type MsdfTextMeasurements } from "./msdf-text";
import { spaceMonoFontAtlas } from "./fonts/space-mono-regular-msdf/space-mono-regular";
import spaceMonoFontJSON from "./fonts/space-mono-regular-msdf/space-mono-regular-msdf.json";
import type { UniformsProvider } from "./uniforms-provider";
import { vec2, type Vec2 } from "wgpu-matrix";
import { SAMPLE_COUNT, DEPTH_STENCIL_TEXTURE_FORMAT } from "./constants";

export type PushTextArgs = {
  value: string;
  position: Vec2;
};

export type UpdateTextArgs = {
  index: number;
  value?: string;
  position: Vec2;
};

interface MsdfTextFormattingOptions {
  centered?: boolean;
  pixelScale?: number;
  color?: [number, number, number, number];
  position: Vec2;
}

const depthFormat = DEPTH_STENCIL_TEXTURE_FORMAT;

export class TextRenderer {
  private fontPipeline: GPURenderPipeline;

  /**
   * Call `init` to initialize
   */
  private font: MsdfFont | undefined = undefined;

  private charsBuffer: GPUBuffer;
  private sampler: GPUSampler;
  private fontBindGroupLayout: GPUBindGroupLayout;
  private textBindGroupLayout: GPUBindGroupLayout;
  private chars: { [x: number]: MsdfChar };
  private renderBundleDescriptor: GPURenderBundleEncoderDescriptor;
  private texts: MsdfText[] = [];

  constructor(
    private device: GPUDevice,
    format: GPUTextureFormat,
    private uniforms: UniformsProvider,
  ) {
    this.renderBundleDescriptor = {
      colorFormats: [format],
      depthStencilFormat: depthFormat,
      sampleCount: SAMPLE_COUNT,
    };
    const shaderModule = device.createShaderModule({
      label: "MSDF text shader",
      code: msdfTextWGSL,
    });
    const fontBindGroupLayout = device.createBindGroupLayout({
      label: "MSDF font group layout",
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.FRAGMENT,
          texture: {},
        },
        {
          binding: 1,
          visibility: GPUShaderStage.FRAGMENT,
          sampler: {},
        },
        {
          binding: 2,
          visibility: GPUShaderStage.VERTEX,
          buffer: { type: "read-only-storage" },
        },
      ],
    });
    this.fontBindGroupLayout = fontBindGroupLayout;
    const textBindGroupLayout = device.createBindGroupLayout({
      label: "MSDF text group layout",
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.VERTEX,
          buffer: {},
        },
        {
          binding: 1,
          visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
          buffer: { type: "read-only-storage" },
        },
      ],
    });
    this.textBindGroupLayout = textBindGroupLayout;

    this.fontPipeline = device.createRenderPipeline({
      label: "MSDF font pipeline",
      layout: device.createPipelineLayout({
        bindGroupLayouts: [fontBindGroupLayout, textBindGroupLayout],
      }),
      vertex: {
        module: shaderModule,
        entryPoint: "vertexMain",
      },
      fragment: {
        module: shaderModule,
        entryPoint: "fragmentMain",
        targets: [
          {
            format: format,
            blend: {
              color: {
                srcFactor: "src-alpha",
                dstFactor: "one-minus-src-alpha",
              },
              alpha: {
                srcFactor: "one",
                dstFactor: "one",
              },
            },
          },
        ],
      },
      primitive: {
        topology: "triangle-strip",
        stripIndexFormat: "uint32",
      },
      depthStencil: {
        depthWriteEnabled: false,
        depthCompare: "less",
        format: depthFormat,
      },
      multisample: {
        count: SAMPLE_COUNT,
      },
    });

    const charCount = spaceMonoFontJSON.chars.length;
    const charsBuffer = device.createBuffer({
      label: "MSDF character layout buffer",
      size: charCount * Float32Array.BYTES_PER_ELEMENT * 8,
      usage: GPUBufferUsage.STORAGE,
      mappedAtCreation: true,
    });
    const charsArray = new Float32Array(charsBuffer.getMappedRange());
    const u = 1 / spaceMonoFontJSON.common.scaleW;
    const v = 1 / spaceMonoFontJSON.common.scaleH;

    const chars: { [x: number]: MsdfChar } = {};

    let offset = 0;
    for (const [i, char] of spaceMonoFontJSON.chars.entries()) {
      // @ts-expect-error charIndex assigned in following line
      chars[char.id] = char;
      chars[char.id].charIndex = i;
      charsArray[offset] = char.x * u; // texOffset.x
      charsArray[offset + 1] = char.y * v; // texOffset.y
      charsArray[offset + 2] = char.width * u; // texExtent.x
      charsArray[offset + 3] = char.height * v; // texExtent.y
      charsArray[offset + 4] = char.width; // size.x
      charsArray[offset + 5] = char.height; // size.y
      charsArray[offset + 6] = char.xoffset; // offset.x
      charsArray[offset + 7] = -char.yoffset; // offset.y
      offset += 8;
    }
    this.chars = chars;

    charsBuffer.unmap();
    this.charsBuffer = charsBuffer;

    const sampler = device.createSampler({
      label: "MSDF text sampler",
      minFilter: "linear",
      magFilter: "linear",
      mipmapFilter: "linear",
      maxAnisotropy: 16,
    });
    this.sampler = sampler;
  }

  /**
   * Needs to be async because of `createImageBitmap`
   */
  async init() {
    const imageBitmap = await createImageBitmap(new Blob([spaceMonoFontAtlas]));
    const texture = this.device.createTexture({
      label: "MSDF font atlas texture Space Mono",
      size: [imageBitmap.width, imageBitmap.height, 1],
      format: "rgba8unorm",
      usage:
        GPUTextureUsage.TEXTURE_BINDING |
        GPUTextureUsage.COPY_DST |
        GPUTextureUsage.RENDER_ATTACHMENT,
    });
    this.device.queue.copyExternalImageToTexture(
      { source: imageBitmap },
      { texture: texture },
      [imageBitmap.width, imageBitmap.height],
    );
    const bindGroup = this.device.createBindGroup({
      label: "msdf font bind group",
      layout: this.fontBindGroupLayout,
      entries: [
        {
          binding: 0,
          // TODO: Allow multi-page fonts
          resource: texture.createView(),
        },
        {
          binding: 1,
          resource: this.sampler,
        },
        {
          binding: 2,
          resource: { buffer: this.charsBuffer },
        },
      ],
    });
    const kernings = getKerningMap();
    this.font = new MsdfFont(
      this.fontPipeline,
      bindGroup,
      spaceMonoFontJSON.common.lineHeight,
      this.chars,
      kernings,
    );
  }

  render(passEncoder: GPURenderPassEncoder): void {
    const renderBundles = this.texts.map((t) => t.getRenderBundle());
    passEncoder.executeBundles(renderBundles);
  }

  /**
   * Returns the index of the pushed element
   */
  pushText(args: PushTextArgs) {
    const { value, position } = args;
    const msdfText = this.formatText(value, { pixelScale: 1 / 256, position });
    this.texts.push(msdfText);
    return this.texts.length - 1;
  }

  updateText(args: UpdateTextArgs) {
    const { value, index, position } = args;
    if (value) {
      const msdfText = this.formatText(value, {
        pixelScale: 1 / 256,
        position,
      });
      this.texts[index] = msdfText;
    }
  }

  private formatText(
    text: string,
    options: MsdfTextFormattingOptions = {
      position: vec2.create(0, 0),
    },
  ) {
    if (!this.font) {
      throw new Error(`Need to call first ${this.init.name}`);
    }
    // TODO: use options.position
    const font = this.font;
    const textBuffer = this.device.createBuffer({
      label: "msdf text buffer",
      size: (text.length + 6) * Float32Array.BYTES_PER_ELEMENT * 4,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
      mappedAtCreation: true,
    });

    const textArray = new Float32Array(textBuffer.getMappedRange());
    let offset = 24; // Accounts for the values managed by MsdfText internally.

    let measurements: MsdfTextMeasurements;
    if (options.centered) {
      measurements = measureText(font, text);

      measureText(
        font,
        text,
        (textX: number, textY: number, line: number, char: MsdfChar) => {
          const lineOffset =
            measurements.width * -0.5 -
            (measurements.width - measurements.lineWidths[line]) * -0.5;

          textArray[offset] = textX + lineOffset;
          textArray[offset + 1] = textY + measurements.height * 0.5;
          textArray[offset + 2] = char.charIndex;
          offset += 4;
        },
      );
    } else {
      measurements = measureText(
        font,
        text,
        (textX: number, textY: number, _line: number, char: MsdfChar) => {
          textArray[offset] = textX;
          textArray[offset + 1] = textY;
          textArray[offset + 2] = char.charIndex;
          offset += 4;
        },
      );
    }

    textBuffer.unmap();

    const textBindGroup = this.device.createBindGroup({
      label: "msdf text bind group",
      layout: this.textBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: this.uniforms.getBuffer() },
        },
        {
          binding: 1,
          resource: { buffer: textBuffer },
        },
      ],
    });

    const encoder = this.device.createRenderBundleEncoder(
      this.renderBundleDescriptor,
    );
    encoder.setPipeline(font.pipeline);
    encoder.setBindGroup(0, font.bindGroup);
    encoder.setBindGroup(1, textBindGroup);
    encoder.draw(4, measurements.printedCharCount);
    const renderBundle = encoder.finish();

    const msdfText = new MsdfText(
      this.device,
      renderBundle,
      measurements,
      font,
      textBuffer,
    );
    if (options.pixelScale !== undefined) {
      msdfText.setPixelScale(options.pixelScale);
    }

    if (options.color !== undefined) {
      msdfText.setColor(...options.color);
    }

    return msdfText;
  }
}

function getKerningMap() {
  const kernings: KerningMap = new Map();

  if (spaceMonoFontJSON.kernings) {
    // Our particular font is monospaced, so we can actually remove this
    for (const kerning of spaceMonoFontJSON.kernings as Kerning[]) {
      let charKerning = kernings.get(kerning.first);
      if (!charKerning) {
        charKerning = new Map<number, number>();
        kernings.set(kerning.first, charKerning);
      }
      charKerning.set(kerning.second, kerning.amount);
    }
  }
  return kernings;
}

function measureText(
  font: MsdfFont,
  text: string,
  charCallback?: (x: number, y: number, line: number, char: MsdfChar) => void,
): MsdfTextMeasurements {
  let maxWidth = 0;
  const lineWidths: number[] = [];

  let textOffsetX = 0;
  let textOffsetY = 0;
  let line = 0;
  let printedCharCount = 0;
  let nextCharCode = text.charCodeAt(0);
  for (let i = 0; i < text.length; ++i) {
    const charCode = nextCharCode;
    nextCharCode = i < text.length - 1 ? text.charCodeAt(i + 1) : -1;

    switch (charCode) {
      case 10: // Newline
        lineWidths.push(textOffsetX);
        line++;
        maxWidth = Math.max(maxWidth, textOffsetX);
        textOffsetX = 0;
        textOffsetY -= font.lineHeight;
        break;
      case 13: // CR
        break;
      case 32: // Space
        // For spaces, advance the offset without actually adding a character.
        textOffsetX += font.getXAdvance(charCode);
        break;
      default: {
        if (charCallback) {
          charCallback(textOffsetX, textOffsetY, line, font.getChar(charCode));
        }
        textOffsetX += font.getXAdvance(charCode, nextCharCode);
        printedCharCount++;
      }
    }
  }

  lineWidths.push(textOffsetX);
  maxWidth = Math.max(maxWidth, textOffsetX);

  return {
    width: maxWidth,
    height: lineWidths.length * font.lineHeight,
    lineWidths,
    printedCharCount,
  };
}
