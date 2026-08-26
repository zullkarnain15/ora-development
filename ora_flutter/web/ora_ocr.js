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

function oraCanvasSize(width, height) {
  const longestSide = Math.max(width, height);
  const scale = Math.min(2, ORA_OCR_MAX_SIDE / longestSide);
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

function drawOraVariant(image, mode) {
  const cropTop = Math.max(0, Math.min(0.8, mode.cropTop || 0));
  const sourceY = Math.round(image.height * cropTop);
  const sourceHeight = Math.max(1, image.height - sourceY);
  const size = oraCanvasSize(image.width, sourceHeight);
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
    0,
    sourceY,
    image.width,
    sourceHeight,
    0,
    0,
    size.width,
    size.height,
  );

  if (mode.filter === 'normal') return canvas.toDataURL('image/png');
  const pixels = context.getImageData(0, 0, size.width, size.height);
  const data = pixels.data;
  for (let index = 0; index < data.length; index += 4) {
    const gray = data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
    let value = Math.max(0, Math.min(255, (gray - 128) * mode.contrast + 128));
    if (mode.threshold !== null) value = value >= mode.threshold ? 255 : 0;
    if (mode.invert) value = 255 - value;
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
    data[index + 3] = 255;
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

async function recognizeOraVariants(worker, image) {
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
    return (await recognizeOraVariants(worker, image)).trim();
  } finally {
    image.dispose();
    if (worker) await worker.terminate();
    bytes = null;
  }
};
