/*
 * AgentGauge · Liquid Glass tile renderer (WebGL port of the native Metal shader)
 * Mirrors Sources/AgentGaugeCore/Rendering/NativeIconRenderer.swift:
 *  - dual wave surface + inertial tilt + ripple
 *  - refraction / chromatic dispersion / caustics / crest highlight
 *  - 24 refracting bubbles
 *  - badge compositor: concentric R-corner pill (auto-dodge) and split-text (polarity cut)
 */
(function (global) {
  "use strict";

  const VERT = `
attribute vec2 aPos;
varying vec2 vTex;
void main() {
  vTex = vec2(aPos.x * 0.5 + 0.5, 0.5 - aPos.y * 0.5);
  gl_Position = vec4(aPos, 0.0, 1.0);
}`;

  const FRAG = `
precision highp float;
varying vec2 vTex;
uniform sampler2D uIcon;
uniform sampler2D uLabel;
uniform float uLevel, uWaveT, uBubbleT, uWake, uTilt, uRipple, uIsDark, uWorking, uPhase;
uniform float uHasLabel, uStyle, uBadgeOpacity;
uniform vec4 uBody;
uniform vec3 uTint;

float sdRoundedBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}
float waveH(float x, float t, float amp, float tilt, float ph, float fr) {
  float nx = (x - 0.5) * 2.0;
  return nx * tilt * 0.085 + sin(nx * 3.14159 * fr + t + ph) * amp + sin(nx * 5.6 * fr - t * 1.28 + ph * 1.7) * (amp * 0.25);
}
vec3 boostSat(vec3 c, float a) {
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  return clamp(mix(vec3(l), c, 1.0 + a), 0.0, 1.0);
}
vec3 sampleInterior(vec2 uv, vec3 fb) {
  vec4 c = texture2D(uIcon, clamp(uv, 0.02, 0.98));
  if (c.a < 0.88) return mix(fb, c.rgb, smoothstep(0.45, 0.88, c.a));
  return c.rgb;
}
vec3 sampleFrosted(vec2 uv, vec3 fb) {
  vec3 acc = vec3(0.0); float w = 0.0;
  for (int dx = -1; dx <= 1; dx++) {
    for (int dy = -1; dy <= 1; dy++) {
      float k = (dx == 0 && dy == 0) ? 2.0 : 1.0;
      acc += sampleInterior(uv + vec2(float(dx), float(dy)) * 0.028, fb) * k;
      w += k;
    }
  }
  return acc / w;
}

void main() {
  vec2 texUv = vTex;
  vec2 uv = vec2(texUv.x, 1.0 - texUv.y);
  vec4 orig = texture2D(uIcon, texUv);
  if (orig.a < 0.004) { gl_FragColor = vec4(0.0); return; }
  float pres = smoothstep(0.0, 1.0, uWake);
  if (pres <= 0.005 || orig.a < 0.38) { gl_FragColor = vec4(orig.rgb * orig.a, orig.a); return; }
  float interiorMask = smoothstep(0.42, 0.95, orig.a);

  vec3 origRGB = orig.rgb;
  vec2 bodyCenter = vec2(uBody.x + uBody.z * 0.5, uBody.y + uBody.w * 0.5);
  vec2 halfSpan = vec2(uBody.z * 0.5, uBody.w * 0.5);
  float bodyY = (uv.y - uBody.y) / max(0.2, uBody.w);
  vec2 p = uv - bodyCenter;
  float rIcon = min(uBody.z, uBody.w) * 0.225;
  float distToWall = max(0.0, -sdRoundedBox(p, halfSpan, rIcon));

  float amp = (0.008 + uWake * 0.014 + uWorking * 0.005 + uRipple * 0.026) * 1.5;
  if (uLevel <= 0.02 || uLevel >= 0.98) amp *= 0.18;
  float hFront = uLevel + waveH(uv.x, uWaveT, amp, uTilt, uPhase, 1.06);
  float hBack = uLevel + 0.028 + waveH(uv.x, -uWaveT * 0.78, amp * 0.92, -uTilt * 0.45, uPhase + 2.40, 0.88);
  float eps = 0.004;
  float slope = (waveH(uv.x + eps, uWaveT, amp, uTilt, uPhase, 1.06) - waveH(uv.x - eps, uWaveT, amp, uTilt, uPhase, 1.06)) / (2.0 * eps);
  float aa = 0.0014;
  float maskFront = smoothstep(hFront + aa, hFront - aa, bodyY);
  float maskBack = smoothstep(hBack + aa * 1.15, hBack - aa * 1.15, bodyY) * (1.0 - maskFront);

  vec3 tint = uTint;
  vec3 col = origRGB;
  if (maskBack > 0.001) {
    vec3 bc = (uIsDark > 0.5) ? (col + tint * 0.16) : (col * exp(-(vec3(1.0) - tint) * 0.44));
    float bLine = smoothstep(0.0045, 0.0, abs(bodyY - hBack));
    vec3 bRimCol = (uIsDark > 0.5) ? mix(tint, vec3(1.0), 0.78) : mix(tint * 0.42, tint * 0.75, 0.5);
    bc = mix(bc, bRimCol, bLine * 0.575);
    col = mix(col, bc, maskBack * pres);
  }
  vec3 cleanCol = col;

  if (maskFront > 0.001) {
    float depthBelow = max(0.0, hFront - bodyY);
    float normDepth = clamp(depthBelow / max(0.18, uLevel), 0.0, 1.0);
    float surfaceLens = exp(-depthBelow * 13.0);
    float wallSoft = smoothstep(0.055, 0.0, distToWall);
    vec2 refOff = vec2(-slope * 0.022 * surfaceLens * 2.2, -0.013 * surfaceLens * 2.2) - p * (0.024 * 2.2);
    refOff.x += sin(bodyY * 15.0 + uWaveT + uPhase) * 0.003 * 2.2;

    float bSpec = 0.0, bRim = 0.0, bDarkRim = 0.0;
    float bAlpha = mix(0.92, 1.0, uWorking);
    for (int i = 0; i < 24; i++) {
      float fi = float(i);
      float seed = fract(fi * 0.3183 + uPhase * 0.17);
      float bx = 0.11 + fract(fi * 0.271 + seed * 0.31) * 0.78;
      float spd = 0.055 + mod(fi, 5.0) * 0.019;
      float prog = fract(fi * 0.163 + uBubbleT * spd);
      float by = 0.03 + prog * max(0.08, uLevel - 0.045);
      float sway = sin(uWaveT * 1.05 + fi * 2.3) * (uWorking > 0.5 ? 0.015 : 0.012);
      vec2 bC = vec2(uBody.x + (bx + sway) * uBody.z, uBody.y + by * uBody.w);
      bool isHero = mod(fi, 3.0) < 0.5;
      float br = (isHero ? (0.0125 + mod(fi, 2.0) * 0.0045) : (0.0055 + mod(fi, 4.0) * 0.0022)) * 1.42;
      if (by < hFront - br * 1.2) {
        vec2 dv = uv - bC;
        float dl = length(dv);
        if (dl < br * 1.3) {
          float lf = sin(prog * 3.14159) * bAlpha;
          if (dl < br) {
            float nz = sqrt(max(0.0, 1.0 - (dl / br) * (dl / br)));
            refOff += (dv / max(br, 1e-4)) * (1.0 - nz) * 0.022 * 2.2 * lf;
          }
          float ringW = max(0.0022, br * 0.26);
          bRim = max(bRim, smoothstep(ringW, 0.0, abs(dl - br * 0.90)) * lf);
          bDarkRim = max(bDarkRim, smoothstep(ringW * 1.2, 0.0, abs(dl - br * 1.02)) * lf * 0.65);
          bSpec = max(bSpec, smoothstep(max(0.0020, br * 0.38), 0.0, length(dv - vec2(-br * 0.32, br * 0.32))) * lf);
        }
      }
    }

    float disp = (surfaceLens + wallSoft * 0.4) * 0.0032 * 0.39;
    vec2 bs = texUv + vec2(refOff.x, -refOff.y);
    vec3 refracted;
    refracted.r = sampleInterior(bs + vec2(disp, 0.0), origRGB).r;
    refracted.g = sampleInterior(bs, origRGB).g;
    refracted.b = sampleInterior(bs - vec2(disp, 0.0), origRGB).b;
    refracted = boostSat(refracted, 0.18);

    vec3 wc;
    if (uIsDark > 0.5) {
      wc = refracted * exp(-(vec3(1.0) - tint) * (0.18 * (0.3 + 0.7 * normDepth)));
      wc += tint * (0.08 + 0.24 * smoothstep(0.0, 1.0, normDepth));
    } else {
      wc = refracted * exp(-(vec3(1.0) - tint) * 0.88 * (0.28 + 0.72 * smoothstep(0.0, 1.0, normDepth)));
    }
    float c1 = sin(uv.x * 26.0 + slope * 8.0 + uWaveT * 1.6) * sin(bodyY * 20.0 - uWaveT * 1.1);
    wc += mix(tint, vec3(1.0), 0.7) * pow(max(0.0, c1), 3.0) * (1.0 - normDepth * 0.55) * (0.26 * 0.35);
    float diag = smoothstep(0.22, 0.0, abs((uv.x * 0.72 + uv.y * 0.52) - 0.56 - slope * 0.08));
    float wallGlow = smoothstep(0.032, 0.0, distToWall);
    wc += vec3(1.0) * (diag * 0.13 + wallGlow * 0.14) * 0.99;
    vec3 wcClean = wc;

    if (uIsDark > 0.5) {
      wc = mix(wc, mix(tint, vec3(1.0), 0.82), bRim * 0.78);
      wc += vec3(1.0) * bSpec * 0.95;
    } else {
      wc = mix(wc, tint * 0.28, bDarkRim * 0.55);
      wc = mix(wc, vec3(1.0), bRim * 0.72);
      wc = mix(wc, vec3(1.0), bSpec * 0.98);
    }
    float crestW = 0.0042;
    float capRim = smoothstep(crestW, 0.0, depthBelow);
    float specBand = smoothstep(crestW * 1.5, 0.0, abs(depthBelow - crestW * 1.35));
    if (uIsDark > 0.5) {
      wc += mix(tint, vec3(1.0), 0.6) * specBand * (0.32 * 0.79);
      wc = mix(wc, vec3(0.97, 0.99, 1.0), capRim * 0.80 * 0.79);
    } else {
      wc = mix(wc, vec3(1.0), specBand * (0.78 * 0.79));
      vec3 darkCap = mix(tint * 0.36, vec3(0.05, 0.18, 0.42), 0.35);
      wc = mix(wc, darkCap, capRim * 0.38);
    }
    cleanCol = mix(cleanCol, wcClean, maskFront * pres);
    col = mix(col, wc, maskFront * pres);
  }

  if (uHasLabel > 0.5 && pres > 0.01) {
    vec4 m = texture2D(uLabel, texUv);
    if (uStyle > 1.5) {
      float gA = clamp(m.g, 0.0, 1.0) * pres;
      if (gA > 0.002) {
        float bgLum = dot(cleanCol, vec3(0.299, 0.587, 0.114));
        float darkPart = smoothstep(0.56, 0.62, bgLum);
        vec3 inkDark = mix(vec3(0.04, 0.06, 0.12), tint * 0.22, 0.28);
        col = mix(col, mix(vec3(1.0), inkDark, darkPart), gA);
      }
    } else {
      float badgeA = clamp(m.r, 0.0, 1.0) * pres;
      float textA = clamp(m.g, 0.0, 1.0) * pres;
      float rimA = clamp(m.b, 0.0, 1.0) * pres;
      if (badgeA > 0.002 || rimA > 0.002 || textA > 0.002) {
        vec3 frosted = sampleFrosted(texUv, origRGB);
        if (maskFront > 0.5) frosted = mix(frosted, tint, 0.34);
        vec3 plate; vec3 glyph; vec3 rimCol; float rimAlpha;
        if (uIsDark > 0.5) {
          plate = mix(vec3(0.96, 0.98, 1.0), tint, 0.06); glyph = vec3(0.05, 0.08, 0.15);
          rimCol = vec3(0.72, 0.76, 0.84); rimAlpha = 0.55;
        } else {
          plate = mix(vec3(0.06, 0.09, 0.16), tint * 0.20, 0.25); glyph = vec3(1.0);
          rimCol = vec3(0.36, 0.42, 0.52); rimAlpha = 0.62;
        }
        col = mix(col, mix(frosted, plate, clamp(uBadgeOpacity, 0.35, 0.98)), badgeA);
        col = mix(col, rimCol, rimA * rimAlpha);
        col = mix(col, glyph, textA);
      }
    }
  }
  vec3 finalCol = mix(origRGB, col, interiorMask);
  gl_FragColor = vec4(finalCol * orig.a, orig.a);
}`;

  const FONT_STACK = '"Futura", "Futura PT", "Cabinet Grotesk", "Century Gothic", -apple-system, sans-serif';

  function hexToRgb(hex) {
    const h = hex.replace("#", "");
    return [parseInt(h.slice(0, 2), 16) / 255, parseInt(h.slice(2, 4), 16) / 255, parseInt(h.slice(4, 6), 16) / 255];
  }

  /** Analyse an icon image exactly like NativeIconRenderer.loadBaseIcon (body rect + luminance). */
  function analyseIcon(img, side) {
    const c = document.createElement("canvas");
    c.width = c.height = side;
    const x = c.getContext("2d", { willReadFrequently: true });
    x.drawImage(img, 0, 0, side, side);
    const d = x.getImageData(0, 0, side, side).data;
    let minX = side, maxX = 0, minRow = side, maxRow = 0, lum = 0, n = 0;
    const midLo = Math.floor(side * 0.38), midHi = Math.floor(side * 0.62), inset = Math.floor(side / 6);
    for (let row = 0; row < side; row++) {
      for (let col = 0; col < side; col++) {
        const i = (row * side + col) * 4, a = d[i + 3];
        if (a >= 246) {
          if (row >= midLo && row <= midHi) { if (col < minX) minX = col; if (col > maxX) maxX = col; }
          if (col >= midLo && col <= midHi) { if (row < minRow) minRow = row; if (row > maxRow) maxRow = row; }
        }
        if (a >= 200 && row >= inset && row < side - inset && col >= inset && col < side - inset && !(col & 1) && !(row & 1)) {
          const af = a / 255;
          lum += 0.299 * Math.min(1, d[i] / 255 / af) + 0.587 * Math.min(1, d[i + 1] / 255 / af) + 0.114 * Math.min(1, d[i + 2] / 255 / af);
          n++;
        }
      }
    }
    let body;
    if (maxX > minX && maxRow > minRow) {
      body = { x: minX, y: side - 1 - maxRow, w: maxX - minX + 1, h: maxRow - minRow + 1 };
    } else {
      const pad = Math.round(side * 0.0975);
      body = { x: pad, y: pad, w: side - pad * 2, h: side - pad * 2 };
    }
    return { body, isDark: (n ? lum / n : 0.5) < 0.48 };
  }

  /** Builds the RGB-channel badge mask (R = plate, G = glyph, B = rim) in canvas space, mirroring badgeMaskTexture(). */
  function buildLabel(side, body, text, style, scale, remaining) {
    const sMin = Math.min(body.w, body.h);
    const sc = Math.max(0.6, Math.min(1.85, scale));
    const rIcon = sMin * 0.225;
    const margin = Math.round(sMin * 0.048);
    const hasPct = text.endsWith("%");
    const main = hasPct ? text.slice(0, -1) : text;
    const unit = hasPct ? "%" : "";
    const isLong = !hasPct && text.length >= 4;
    const split = style === "split";
    const baseFactor = split ? 0.158 : 0.14;
    const maxRatio = split ? 0.78 : 0.77;

    const meas = document.createElement("canvas").getContext("2d");
    let mainFs = Math.max(14, Math.round(sMin * baseFactor * sc * (isLong ? 0.85 : 1)));
    let unitFs = Math.max(9, Math.round(mainFs * 0.54));
    const gap = unit ? Math.round(sMin * 0.01) : 0;
    const measure = () => {
      meas.font = `700 ${mainFs}px ${FONT_STACK}`;
      const mA = meas.measureText(main).width;
      const cap = meas.measureText("8").actualBoundingBoxAscent || mainFs * 0.72;
      meas.font = `700 ${unitFs}px ${FONT_STACK}`;
      const uA = unit ? meas.measureText(unit).width : 0;
      return { mA, uA, cap, total: mA + gap + uA };
    };
    let m = measure();
    if (m.total > sMin * maxRatio) {
      const r = (sMin * maxRatio) / m.total;
      mainFs = Math.max(13, Math.round(mainFs * r));
      unitFs = Math.max(8.5, Math.round(mainFs * 0.54));
      m = measure();
    }

    // Geometry in CoreGraphics (y-up) space
    let pill = null, textX, textBaseY;
    const bMaxY = body.y + body.h;
    if (split) {
      textX = Math.round(body.x + sMin * 0.085);
      textBaseY = Math.round(body.y + sMin * 0.115);
    } else {
      const dodgeCutoff = Math.min(54, Math.max(25, 0.232 * sc * 100 + 4));
      const pillH = Math.min(sMin - margin * 2, Math.round(Math.max(sMin * 0.232 * sc, mainFs * 1.44)));
      const pillW = Math.min(sMin - margin * 2, Math.round(Math.max(pillH * 1.18, m.total + sMin * 0.125 * Math.min(1.3, sc))));
      const rPill = Math.min(pillH * 0.48, Math.max(8, rIcon - margin));
      const top = remaining <= dodgeCutoff;
      const px = Math.round(body.x + margin);
      const py = top ? Math.round(bMaxY - margin - pillH) : Math.round(body.y + margin);
      pill = { x: px, y: py, w: pillW, h: pillH, r: rPill };
      textX = Math.round(px + (pillW - m.total) * 0.5);
      textBaseY = Math.round(py + (pillH - m.cap) * 0.5);
    }

    const layer = () => { const c = document.createElement("canvas"); c.width = c.height = side; return c; };
    const toCanvasY = (y) => side - y;
    const plateC = layer(), rimC = layer(), textC = layer();
    if (pill) {
      const top = toCanvasY(pill.y + pill.h);
      const pc = plateC.getContext("2d");
      pc.fillStyle = "#fff";
      pc.beginPath(); pc.roundRect(pill.x, top, pill.w, pill.h, pill.r); pc.fill();
      const rc = rimC.getContext("2d");
      rc.strokeStyle = "#fff"; rc.lineWidth = Math.max(3.2, side * 0.016);
      rc.beginPath(); rc.roundRect(pill.x, top, pill.w, pill.h, pill.r); rc.stroke();
    }
    const tc = textC.getContext("2d");
    tc.fillStyle = "#fff";
    tc.textBaseline = "alphabetic";
    tc.font = `700 ${mainFs}px ${FONT_STACK}`;
    tc.fillText(main, textX, toCanvasY(textBaseY));
    if (unit) {
      tc.font = `700 ${unitFs}px ${FONT_STACK}`;
      tc.fillText(unit, textX + m.mA + gap, toCanvasY(textBaseY));
    }

    const out = layer();
    const o = out.getContext("2d");
    const od = o.createImageData(side, side);
    const P = plateC.getContext("2d").getImageData(0, 0, side, side).data;
    const Rr = rimC.getContext("2d").getImageData(0, 0, side, side).data;
    const T = tc.getImageData(0, 0, side, side).data;
    for (let i = 0; i < od.data.length; i += 4) {
      od.data[i] = P[i + 3];
      od.data[i + 1] = T[i + 3];
      od.data[i + 2] = Rr[i + 3];
      od.data[i + 3] = 255;
    }
    o.putImageData(od, 0, 0);
    return out;
  }

  class LiquidRenderer {
    constructor(canvas, side) {
      this.canvas = canvas;
      this.side = side;
      canvas.width = canvas.height = side;
      const gl = canvas.getContext("webgl", { premultipliedAlpha: true, alpha: true, antialias: true, preserveDrawingBuffer: true });
      if (!gl) throw new Error("WebGL unavailable");
      this.gl = gl;
      const sh = (type, src) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, src); gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
        return s;
      };
      const prog = gl.createProgram();
      gl.attachShader(prog, sh(gl.VERTEX_SHADER, VERT));
      gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FRAG));
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
      gl.useProgram(prog);
      this.prog = prog;
      const buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
      const loc = gl.getAttribLocation(prog, "aPos");
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
      this.u = {};
      ["uIcon", "uLabel", "uLevel", "uWaveT", "uBubbleT", "uWake", "uTilt", "uRipple", "uIsDark", "uWorking", "uPhase",
        "uHasLabel", "uStyle", "uBadgeOpacity", "uBody", "uTint"].forEach((n) => (this.u[n] = gl.getUniformLocation(prog, n)));
      gl.uniform1i(this.u.uIcon, 0);
      gl.uniform1i(this.u.uLabel, 1);
      this.iconTex = new Map();
      this.labelTex = new Map();
    }

    _texFrom(source, mipmap = false) {
      const gl = this.gl;
      const t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
      const pot = (this.side & (this.side - 1)) === 0;
      if (mipmap && pot) {
        gl.generateMipmap(gl.TEXTURE_2D);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      } else {
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      }
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      return t;
    }

    /** Registers an icon (HTMLImageElement, decoded). */
    addIcon(id, img) {
      const side = this.side;
      const c = document.createElement("canvas");
      c.width = c.height = side;
      const ctx = c.getContext("2d");
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = "high";
      ctx.drawImage(img, 0, 0, side, side);
      const info = analyseIcon(img, side);
      this.iconTex.set(id, { tex: this._texFrom(c, true), ...info });
    }

    _label(id, text, style, scale, remaining) {
      const icon = this.iconTex.get(id);
      const dodgeCutoff = Math.min(54, Math.max(25, 0.232 * scale * 100 + 4));
      const dodge = style === "split" ? "F" : remaining <= dodgeCutoff ? "T" : "B";
      const key = `${id}|${text}|${style}|${scale}|${dodge}`;
      let t = this.labelTex.get(key);
      if (!t) {
        if (this.labelTex.size > 260) {
          for (const [k, v] of this.labelTex) { this.gl.deleteTexture(v); this.labelTex.delete(k); if (this.labelTex.size < 160) break; }
        }
        t = this._texFrom(buildLabel(this.side, icon.body, text, style, scale, remaining));
        this.labelTex.set(key, t);
      }
      return t;
    }

    /**
     * state: { id, level (0-100), waveT, bubbleT, wake, tilt, ripple, tint (hex), style ("split"|"pill"), scale, showLabel, working }
     */
    render(s) {
      const gl = this.gl;
      const icon = this.iconTex.get(s.id);
      if (!icon) return false;
      const side = this.side;
      gl.viewport(0, 0, side, side);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, icon.tex);
      const txt = s.label || `${Math.round(s.level)}%`;
      const showLabel = s.showLabel !== false && s.wake > 0.01;
      if (showLabel) {
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this._label(s.id, txt, s.style || "split", s.scale || 1.55, s.level));
      }
      const u = this.u;
      const b = icon.body;
      gl.uniform1f(u.uLevel, Math.max(0, Math.min(1, s.level / 100)));
      gl.uniform1f(u.uWaveT, s.waveT);
      gl.uniform1f(u.uBubbleT, s.bubbleT);
      gl.uniform1f(u.uWake, s.wake);
      gl.uniform1f(u.uTilt, Math.max(-0.55, Math.min(0.55, s.tilt)));
      gl.uniform1f(u.uRipple, Math.max(0, Math.min(0.6, s.ripple)));
      gl.uniform1f(u.uIsDark, icon.isDark ? 1 : 0);
      gl.uniform1f(u.uWorking, s.working ? 1 : 0);
      gl.uniform1f(u.uPhase, s.phase || 0);
      gl.uniform1f(u.uHasLabel, showLabel ? 1 : 0);
      gl.uniform1f(u.uStyle, (s.style || "split") === "split" ? 2 : 0);
      gl.uniform1f(u.uBadgeOpacity, 0.85);
      gl.uniform4f(u.uBody, b.x / side, b.y / side, b.w / side, b.h / side);
      const t = hexToRgb(s.tint || "#587BA3");
      gl.uniform3f(u.uTint, t[0], t[1], t[2]);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      return true;
    }
  }

  /** Physically faithful replay of OverlayManager's hover motion integrator. */
  class TileMotion {
    constructor(seed = 0) {
      this.hover = 0; this.tilt = 0; this.tiltVel = 0; this.ripple = 0.36;
      this.waveT = seed; this.bubbleT = seed * 1.3; this.target = 0;
    }
    kick(v) { this.tiltVel += v; this.ripple = Math.max(this.ripple, 0.3); }
    step(dt) {
      const speed = 0.25 + 0.8 * 2.2;
      this.waveT += dt * 1.85 * speed;
      this.bubbleT += dt * 2.4 * speed;
      const k = Math.min(1, dt * (this.target > this.hover ? 16 : 7));
      this.hover += (this.target - this.hover) * k;
      if (Math.abs(this.target - this.hover) < 0.006) this.hover = this.target;
      const accel = 26 * (0 - this.tilt) - 6.2 * this.tiltVel;
      this.tiltVel += accel * dt;
      this.tilt = Math.max(-0.55, Math.min(0.55, this.tilt + this.tiltVel * dt));
      this.ripple *= Math.pow(0.1, dt);
    }
    get tiltScaled() { return this.tilt * (0.25 + 0.67 * 1.1); }
  }

  global.AGLiquid = { LiquidRenderer, TileMotion, analyseIcon };
})(window);
