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
  const size = oraCanvasSize(image.width, image.height);
  const canvas = document.createElement('canvas');
  canvas.width = size.width;
  canvas.height = size.height;
  const context = canvas.getContext('2d', {willReadFrequently: true});
  if (!context) throw new Error('OCR canvas is unavailable.');

  // Always flatten alpha first. Strava templates can use transparent overlays
  // that otherwise turn into unreadable dark text when OCR decodes the image.
  context.fillStyle = mode.background;
  context.fillRect(0, 0, size.width, size.height);
  context.drawImage(image.source, 0, 0, size.width, size.height);

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
  if (/\b(?:distance|pace|time)\b/i.test(text)) score += 1;
  return score;
}

async function recognizeOraVariants(worker, image) {
  const variants = [
    {name: 'normalized-white', background: '#ffffff', filter: 'normal', contrast: 1, threshold: null, invert: false},
    {name: 'grayscale-contrast', background: '#ffffff', filter: 'grayscale', contrast: 2.2, threshold: null, invert: false},
    {name: 'threshold', background: '#ffffff', filter: 'grayscale', contrast: 2.4, threshold: 158, invert: false},
    {name: 'invert-threshold', background: '#000000', filter: 'grayscale', contrast: 2.2, threshold: 116, invert: true},
    {name: 'normalized-black', background: '#000000', filter: 'normal', contrast: 1, threshold: null, invert: false},
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

self.oraRecognizeActivityImage = async function(bytes, mimeType) {
  const Tesseract = await loadOraTesseract();
  const blob = new Blob([bytes], {type: mimeType || 'image/jpeg'});
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
