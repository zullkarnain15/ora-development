'use strict';

const ORA_TESSERACT_URL =
  'https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/tesseract.min.js';
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

self.oraRecognizeActivityImage = async function(bytes, mimeType) {
  const Tesseract = await loadOraTesseract();
  const blob = new Blob([bytes], {type: mimeType || 'image/jpeg'});
  const objectUrl = URL.createObjectURL(blob);
  let worker = null;
  try {
    worker = await Tesseract.createWorker('eng');
    const result = await worker.recognize(objectUrl);
    return result && result.data && result.data.text
      ? String(result.data.text)
      : '';
  } finally {
    URL.revokeObjectURL(objectUrl);
    if (worker) await worker.terminate();
    bytes = null;
  }
};
