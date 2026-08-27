'use strict';

const ORA_TESSERACT_URL =
  'https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/tesseract.min.js';
const ORA_OCR_MAX_SIDE = 2400;
let oraTesseractLoader = null;

function loadOraTesseract() {
  if (self.Tesseract) return Promise.resolve(self.Tesseract);
  if (oraTesseractLoader) return oraTesseractLoader;
  oraTesseractLoader = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = ORA_TESSERACT_URL;
    script.crossOrigin = 'anonymous';
    script.onload = () => resolve(self.Tesseract);
    script.onerror = () => reject(new Error('OCR engine could not be loaded.'));
    document.head.appendChild(script);
  });
  return oraTesseractLoader;
}

async function decodeOraImage(blob) {
  if (typeof createImageBitmap === 'function') {
    try {
      const bitmap = await createImageBitmap(blob);
      return {
        source: bitmap,
        width: bitmap.width,
        height: bitmap.height,
        dispose: () => bitmap.close(),
      };
    } catch (_) {
      // Safari can expose createImageBitmap yet reject a shared image format.
    }
  }
  const objectUrl = URL.createObjectURL(blob);
  const image = new Image();
  try {
    await new Promise((resolve, reject) => {
      image.onload = resolve;
      image.onerror = () => reject(new Error('Shared image could not be decoded.'));
      image.src = objectUrl;
    });
    return {
      source: image,
      width: image.naturalWidth,
      height: image.naturalHeight,
      dispose: () => URL.revokeObjectURL(objectUrl),
    };
  } catch (error) {
    URL.revokeObjectURL(objectUrl);
    throw error;
  }
}

function oraCanvasSize(width, height, requestedScale = 2) {
  const longestSide = Math.max(width, height);
  const scale = Math.min(requestedScale, ORA_OCR_MAX_SIDE / longestSide);
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

function oraCropRect(image, mode) {
  if (mode.crop) {
    const x = Math.max(0, Math.min(image.width - 1, Math.round(image.width * mode.crop.x)));
    const y = Math.max(0, Math.min(image.height - 1, Math.round(image.height * mode.crop.y)));
    const width = Math.max(1, Math.min(image.width - x, Math.round(image.width * mode.crop.width)));
    const height = Math.max(1, Math.min(image.height - y, Math.round(image.height * mode.crop.height)));
    return {x, y, width, height};
  }
  const cropTop = Math.max(0, Math.min(0.8, mode.cropTop || 0));
  const y = Math.round(image.height * cropTop);
  return {x: 0, y, width: image.width, height: Math.max(1, image.height - y)};
}

function drawOraVariant(image, mode) {
  const crop = oraCropRect(image, mode);
  const size = oraCanvasSize(crop.width, crop.height, mode.scale || 2);
  const canvas = document.createElement('canvas');
  canvas.width = size.width;
  canvas.height = size.height;
  const context = canvas.getContext('2d', {willReadFrequently: true});
  if (!context) throw new Error('OCR canvas is unavailable.');

  // Always flatten alpha first. Strava templates can use transparent overlays
  // that otherwise turn into unreadable dark text when OCR decodes the image.
  context.fillStyle = mode.background;
  context.fillRect(0, 0, size.width, size.height);
  context.drawImage(
    image.source,
    crop.x,
    crop.y,
    crop.width,
    crop.height,
    0,
    0,
    size.width,
    size.height,
  );

  if (mode.filter === 'normal') return canvas.toDataURL('image/png');
  const pixels = context.getImageData(0, 0, size.width, size.height);
  const data = pixels.data;
  const luminance = new Float32Array(size.width * size.height);
  for (let index = 0; index < data.length; index += 4) {
    luminance[index / 4] = data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
  }
  for (let y = 0; y < size.height; y += 1) {
    for (let x = 0; x < size.width; x += 1) {
      const pixelIndex = y * size.width + x;
      let gray = luminance[pixelIndex];
      if (mode.sharpen && x > 0 && y > 0 && x + 1 < size.width && y + 1 < size.height) {
        const neighbors = luminance[pixelIndex - 1] + luminance[pixelIndex + 1] +
          luminance[pixelIndex - size.width] + luminance[pixelIndex + size.width];
        gray += (gray - neighbors / 4) * mode.sharpen;
      }
      let value = Math.max(0, Math.min(255, (gray - 128) * mode.contrast + 128));
      if (mode.threshold !== null) value = value >= mode.threshold ? 255 : 0;
      if (mode.invert) value = 255 - value;
      const index = pixelIndex * 4;
      data[index] = value;
      data[index + 1] = value;
      data[index + 2] = value;
      data[index + 3] = 255;
    }
  }
  context.putImageData(pixels, 0, 0);
  return canvas.toDataURL('image/png');
}

function scoreOraActivityText(value) {
  const text = String(value || '');
  let score = 0;
  if (/\b\d+(?:[.,]\d+)?\s*(?:k\s*m|km|kilomet(?:er|re)s?)\b/i.test(text)) score += 5;
  if (/\b\d+\s*m\s*\d+\s*s\b/i.test(text) ||
      /\b\d+\s*(?:h|hours?)\s*\d+\s*(?:m|minutes?)\b/i.test(text) ||
      /\b\d{1,2}:[0-5]\d(?::[0-5]\d)?\b/.test(text)) score += 5;
  if (/\b\d{1,2}:[0-5]\d\s*(?:\/|per\s*)\s*k\s*m\b/i.test(text)) score += 3;
  if (/\b(?:distance|pace|time|moving\s*time|total\s*time|duration)\b/i.test(text)) score += 1;

  const distance = text.match(/\b(\d+(?:[.,]\d+)?)\s*(?:k\s*m|km)\b/i);
  const pace = text.match(/\b(\d{1,2}):([0-5]\d)\s*(?:\/|per\s*)\s*k\s*m\b/i);
  const duration = oraDurationSeconds(text);
  if (distance && pace && duration !== null) {
    const kilometers = Number(distance[1].replace(',', '.'));
    const paceSeconds = Number(pace[1]) * 60 + Number(pace[2]);
    const expected = kilometers * paceSeconds;
    const difference = Math.abs(duration - expected);
    const closeTolerance = Math.max(30, expected * 0.02);
    const looseTolerance = Math.max(90, expected * 0.06);
    if (difference <= closeTolerance) score += 8;
    else if (difference <= looseTolerance) score += 3;
    else score -= 5;
  }
  return score;
}

function oraDurationSeconds(text) {
  text = String(text || '').replace(
    /(\d)\s*[lI]\s*(?=s\b)/g,
    (_, digit) => `${digit}1`,
  );
  const hoursMinutesSeconds = text.match(
    /\b(\d+)\s*(?:h|hours?)\s*(\d+)\s*(?:m|minutes?)\s*(\d+)\s*(?:s|seconds?)\b/i,
  );
  if (hoursMinutesSeconds) {
    return Number(hoursMinutesSeconds[1]) * 3600 +
      Number(hoursMinutesSeconds[2]) * 60 + Number(hoursMinutesSeconds[3]);
  }
  const minutesSeconds = text.match(
    /\b(\d+)\s*(?:m|minutes?)\s*(\d+)\s*(?:s|seconds?)\b/i,
  );
  if (minutesSeconds) {
    return Number(minutesSeconds[1]) * 60 + Number(minutesSeconds[2]);
  }
  const clockValues = [...text.matchAll(/\b(\d{1,2}):([0-5]\d)(?::([0-5]\d))?\b/g)];
  for (const clock of clockValues) {
    const suffix = text.slice(clock.index + clock[0].length, clock.index + clock[0].length + 12);
    if (/^\s*(?:\/|per\s*)\s*k\s*m\b/i.test(suffix)) continue;
    return clock[3]
      ? Number(clock[1]) * 3600 + Number(clock[2]) * 60 + Number(clock[3])
      : Number(clock[1]) * 60 + Number(clock[2]);
  }
  return null;
}

function oraTextFromResult(result) {
  return result && result.data && result.data.text ? String(result.data.text) : '';
}

function isOraStravaCard(text) {
  const value = String(text || '');
  return /\bstrava\b/i.test(value) ||
    (/\bdistance\b/i.test(value) && /\bpace\b/i.test(value) && /\btime\b/i.test(value));
}

function oraWordsFromResult(result) {
  const data = result && result.data;
  if (!data) return [];
  if (Array.isArray(data.words)) return data.words;
  const words = [];
  for (const block of Array.isArray(data.blocks) ? data.blocks : []) {
    for (const paragraph of Array.isArray(block.paragraphs) ? block.paragraphs : []) {
      for (const line of Array.isArray(paragraph.lines) ? paragraph.lines : []) {
        words.push(...(Array.isArray(line.words) ? line.words : []));
      }
    }
  }
  return words;
}

function oraMetricColumnCrop(result, image, label, leftPadding, width) {
  const labelWord = oraWordsFromResult(result).find(
    (word) => String(word.text || '').replace(/[^a-z]/gi, '').toLowerCase() === label,
  );
  const box = labelWord && labelWord.bbox;
  if (!box || !Number.isFinite(box.x0) || !Number.isFinite(box.y0)) return null;
  const labelX = box.x0;
  const labelY = box.y0;
  const x = Math.max(0, Math.min(image.width - 1, labelX - image.width * leftPadding));
  const y = Math.max(0, Math.min(image.height - 1, labelY - image.height * 0.04));
  return {
    x: x / image.width,
    y: y / image.height,
    width: Math.min(image.width - x, image.width * width) / image.width,
    height: Math.min(image.height - y, image.height * 0.25) / image.height,
  };
}

function oraTimeColumnCrop(result, image) {
  return oraMetricColumnCrop(result, image, 'time', 0.12, 0.45);
}

function oraDistanceColumnCrop(result, image) {
  return oraMetricColumnCrop(result, image, 'distance', 0.04, 0.36);
}

async function recognizeOraGenericVariants(worker, image) {
  const variants = [
    {name: 'normalized-white', background: '#ffffff', filter: 'normal', contrast: 1, threshold: null, invert: false, cropTop: 0},
    {name: 'grayscale-contrast', background: '#ffffff', filter: 'grayscale', contrast: 2.2, threshold: null, invert: false, cropTop: 0},
    {name: 'threshold', background: '#ffffff', filter: 'grayscale', contrast: 2.4, threshold: 158, invert: false, cropTop: 0},
    {name: 'invert-threshold', background: '#000000', filter: 'grayscale', contrast: 2.2, threshold: 116, invert: true, cropTop: 0},
    {name: 'normalized-black', background: '#000000', filter: 'normal', contrast: 1, threshold: null, invert: false, cropTop: 0},
    // Huawei photo templates place their useful statistics in the lower area.
    {name: 'lower-stats-contrast', background: '#ffffff', filter: 'grayscale', contrast: 2.3, threshold: null, invert: false, cropTop: 0.5},
    {name: 'lower-stats-threshold', background: '#ffffff', filter: 'grayscale', contrast: 2.4, threshold: 154, invert: false, cropTop: 0.5},
  ];
  let best = '';
  let bestScore = -1;
  for (const variant of variants) {
    const dataUrl = drawOraVariant(image, variant);
    const result = await worker.recognize(dataUrl);
    const text = result && result.data && result.data.text
      ? String(result.data.text)
      : '';
    const score = scoreOraActivityText(text);
    if (score > bestScore || (score === bestScore && text.length > best.length)) {
      best = text;
      bestScore = score;
    }
  }
  return best;
}

function scoreOraMetricCrop(text, metric) {
  if (metric === 'distance') {
    if (/\b\d+[.,]\d+\s*k\s*m\b/i.test(text)) return 12;
    if (/\b\d+\s*k\s*m\b/i.test(text)) return 5;
    return 0;
  }
  if (oraDurationSeconds(text) === null) return 0;
  return /\b\d+\s*m\s*[\dIl]+\s*s\b/i.test(text) ? 12 : 8;
}

async function recognizeOraMetricCrop(worker, image, crop, metric) {
  if (!crop) return '';
  const variants = [
    {name: `${metric}-contrast`, background: '#000000', filter: 'grayscale', contrast: 2.35, threshold: null, invert: false, crop, scale: 3, sharpen: 1.15},
    {name: `${metric}-threshold-145`, background: '#000000', filter: 'grayscale', contrast: 2.6, threshold: 145, invert: false, crop, scale: 3, sharpen: 1.2},
  ];
  let best = '';
  let bestScore = -1;
  for (const variant of variants) {
    const result = await worker.recognize(drawOraVariant(image, variant));
    const text = oraTextFromResult(result).trim();
    const score = scoreOraMetricCrop(text, metric);
    if (score > bestScore || (score === bestScore && text.length > best.length)) {
      best = text;
      bestScore = score;
    }
  }
  return best;
}

async function recognizeOraStravaVariants(worker, image, originalResult) {
  const variants = [
    // The original PNG is recognized directly before these canvas passes.
    {name: 'strava-grayscale-upscale-2x', background: '#000000', filter: 'grayscale', contrast: 2.25, threshold: null, invert: false, cropTop: 0, scale: 2, sharpen: 1.05},
    {name: 'strava-grayscale-upscale-3x', background: '#000000', filter: 'grayscale', contrast: 2.35, threshold: null, invert: false, cropTop: 0, scale: 3, sharpen: 1.15},
    {name: 'strava-white-text-threshold', background: '#000000', filter: 'grayscale', contrast: 2.6, threshold: 168, invert: false, cropTop: 0, scale: 3, sharpen: 1.2},
    {name: 'strava-metrics-center-bottom', background: '#000000', filter: 'grayscale', contrast: 2.45, threshold: 158, invert: false, crop: {x: 0.12, y: 0.48, width: 0.76, height: 0.34}, scale: 3, sharpen: 1.1},
  ];
  let best = oraTextFromResult(originalResult);
  let bestScore = scoreOraActivityText(best);
  for (const variant of variants) {
    const result = await worker.recognize(drawOraVariant(image, variant));
    const text = oraTextFromResult(result);
    const score = scoreOraActivityText(text);
    if (score > bestScore || (score === bestScore && text.length > best.length)) {
      best = text;
      bestScore = score;
    }
  }

  const distanceText = await recognizeOraMetricCrop(
    worker, image, oraDistanceColumnCrop(originalResult, image), 'distance',
  );
  if (distanceText) best = `${best}\nDistance\n${distanceText}`;
  const timeText = await recognizeOraMetricCrop(
    worker, image, oraTimeColumnCrop(originalResult, image), 'time',
  );
  if (timeText) best = `${best}\nTime\n${timeText}`;
  return best;
}

function oraActualImageMimeType(bytes, declaredMimeType) {
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d &&
      bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
      bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12) {
    const ascii = (start, length) => String.fromCharCode(...bytes.slice(start, start + length));
    if (ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'WEBP') return 'image/webp';
    if (ascii(4, 4) === 'ftyp') {
      const brand = ascii(8, 4).toLowerCase();
      if (brand === 'avif' || brand === 'avis') return 'image/avif';
      if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(brand)) {
        return 'image/heic';
      }
    }
  }
  const declared = String(declaredMimeType || '').split(';')[0].trim().toLowerCase();
  return declared.startsWith('image/') ? declared : 'image/jpeg';
}

self.oraRecognizeActivityImage = async function(bytes, mimeType) {
  const Tesseract = await loadOraTesseract();
  const normalizedMimeType = oraActualImageMimeType(bytes, mimeType);
  const blob = new Blob([bytes], {type: normalizedMimeType});
  const image = await decodeOraImage(blob);
  let worker = null;
  try {
    worker = await Tesseract.createWorker('eng');
    // Keep a PNG as PNG for the first pass. This preserves white text and
    // transparent Strava overlays before any canvas preprocessing happens.
    let originalResult = null;
    try {
      originalResult = await worker.recognize(
        blob,
        {},
        {text: true, blocks: true},
      );
    } catch (_) {
      // Formats that the browser can draw but Tesseract cannot read directly
      // retain the existing generic canvas pipeline.
      return (await recognizeOraGenericVariants(worker, image)).trim();
    }
    const text = isOraStravaCard(oraTextFromResult(originalResult))
      ? await recognizeOraStravaVariants(worker, image, originalResult)
      : await recognizeOraGenericVariants(worker, image);
    return text.trim();
  } finally {
    image.dispose();
    if (worker) await worker.terminate();
    bytes = null;
  }
};
