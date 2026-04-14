const imageInput = document.getElementById("image-input");
const runButton = document.getElementById("run-btn");
const benchmarkButton = document.getElementById("benchmark-btn");
const statusEl = document.getElementById("status");

const metricModeEl = document.getElementById("metric-mode");
const metricTimeEl = document.getElementById("metric-time");
const metricSpeedupEl = document.getElementById("metric-speedup");

const benchCpuTimeEl = document.getElementById("bench-cpu-time");
const benchBasicTimeEl = document.getElementById("bench-basic-time");
const benchTiledTimeEl = document.getElementById("bench-tiled-time");
const benchBasicSpeedupEl = document.getElementById("bench-basic-speedup");
const benchTiledSpeedupEl = document.getElementById("bench-tiled-speedup");
const benchBasicMaeEl = document.getElementById("bench-basic-mae");
const benchTiledMaeEl = document.getElementById("bench-tiled-mae");
const benchmarkNoteEl = document.getElementById("benchmark-note");

const inputCanvas = document.getElementById("input-canvas");
const outputCanvas = document.getElementById("output-canvas");

let selectedFile = null;
let cachedGrayImage = null;

function setBusy(isBusy) {
    runButton.disabled = isBusy;
    benchmarkButton.disabled = isBusy;
}

function setStatus(text, isError = false) {
    statusEl.textContent = text;
    statusEl.classList.toggle("error", isError);
}

function getSelectedMode() {
    const selected = document.querySelector("input[name='mode']:checked");
    return selected ? selected.value : "cpu";
}

function modeLabel(mode) {
    if (mode === "gpu_basic") {
        return "GPU Basic";
    }
    if (mode === "gpu_tiled") {
        return "GPU Tiled";
    }
    return "CPU";
}

function drawGrayPixelsToCanvas(canvas, width, height, pixels) {
    const ctx = canvas.getContext("2d");
    const imageData = ctx.createImageData(width, height);

    for (let i = 0, j = 0; i < pixels.length; i += 1, j += 4) {
        const value = pixels[i];
        imageData.data[j] = value;
        imageData.data[j + 1] = value;
        imageData.data[j + 2] = value;
        imageData.data[j + 3] = 255;
    }

    canvas.width = width;
    canvas.height = height;
    ctx.putImageData(imageData, 0, 0);
}

function base64ToUint8Array(base64Text) {
    const binary = atob(base64Text);
    const bytes = new Uint8Array(binary.length);

    for (let i = 0; i < binary.length; i += 1) {
        bytes[i] = binary.charCodeAt(i);
    }

    return bytes;
}

async function decodeFileToGrayImage(file) {
    const bitmap = await createImageBitmap(file);
    const scratch = document.createElement("canvas");
    scratch.width = bitmap.width;
    scratch.height = bitmap.height;

    const ctx = scratch.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(bitmap, 0, 0);

    const rgba = ctx.getImageData(0, 0, bitmap.width, bitmap.height).data;
    const gray = new Uint8Array(bitmap.width * bitmap.height);

    for (let src = 0, dst = 0; src < rgba.length; src += 4, dst += 1) {
        const r = rgba[src];
        const g = rgba[src + 1];
        const b = rgba[src + 2];
        gray[dst] = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
    }

    if (typeof bitmap.close === "function") {
        bitmap.close();
    }

    return {
        width: scratch.width,
        height: scratch.height,
        pixels: gray
    };
}

function grayImageToPgmBlob(grayImage) {
    const headerText = `P5\n${grayImage.width} ${grayImage.height}\n255\n`;
    const headerBytes = new TextEncoder().encode(headerText);
    const payload = new Uint8Array(headerBytes.length + grayImage.pixels.length);

    payload.set(headerBytes, 0);
    payload.set(grayImage.pixels, headerBytes.length);

    return new Blob([payload], { type: "application/octet-stream" });
}

async function ensureGrayImage() {
    if (!selectedFile) {
        throw new Error("Select an image before running blur.");
    }

    if (!cachedGrayImage) {
        cachedGrayImage = await decodeFileToGrayImage(selectedFile);
        drawGrayPixelsToCanvas(
            inputCanvas,
            cachedGrayImage.width,
            cachedGrayImage.height,
            cachedGrayImage.pixels
        );
    }

    return cachedGrayImage;
}

function updateSelectedMetrics(result) {
    metricModeEl.textContent = modeLabel(result.mode);
    metricTimeEl.textContent = `${result.executionMs.toFixed(3)} ms`;
    metricSpeedupEl.textContent = `${result.speedup.toFixed(2)}x`;
}

function updateBenchmarkTable(benchmark) {
    benchCpuTimeEl.textContent = `${benchmark.timesMs.cpu.toFixed(3)} ms`;
    benchBasicTimeEl.textContent = `${benchmark.timesMs.gpuBasic.toFixed(3)} ms`;
    benchTiledTimeEl.textContent = `${benchmark.timesMs.gpuTiled.toFixed(3)} ms`;

    benchBasicSpeedupEl.textContent = `${benchmark.speedup.basic.toFixed(2)}x`;
    benchTiledSpeedupEl.textContent = `${benchmark.speedup.tiled.toFixed(2)}x`;

    benchBasicMaeEl.textContent = benchmark.quality.maeBasicVsCpu.toFixed(4);
    benchTiledMaeEl.textContent = benchmark.quality.maeTiledVsCpu.toFixed(4);

    benchmarkNoteEl.textContent = benchmark.tiledFasterThanBasic
        ? "Tiled kernel is faster than basic GPU for this input."
        : "Tiled kernel was not faster for this input size. Try a larger image.";
}

async function callApi(endpoint, mode = null) {
    const grayImage = await ensureGrayImage();
    const pgmBlob = grayImageToPgmBlob(grayImage);

    const formData = new FormData();
    formData.append("image", pgmBlob, "input.pgm");

    if (mode) {
        formData.append("mode", mode);
    }

    const response = await fetch(endpoint, {
        method: "POST",
        body: formData
    });

    const payload = await response.json();
    if (!response.ok) {
        throw new Error(payload.error || "Request failed.");
    }

    return payload;
}

async function runSelectedMode() {
    const mode = getSelectedMode();

    setBusy(true);
    setStatus(`Running ${modeLabel(mode)}...`);

    try {
        const payload = await callApi("/api/blur", mode);
        const outputPixels = base64ToUint8Array(payload.image.pixelsBase64);

        drawGrayPixelsToCanvas(outputCanvas, payload.image.width, payload.image.height, outputPixels);
        updateSelectedMetrics(payload);

        setStatus(`Completed ${modeLabel(mode)} in ${payload.executionMs.toFixed(3)} ms.`);
    } catch (err) {
        setStatus(err.message || "Failed to run selected mode.", true);
    } finally {
        setBusy(false);
    }
}

async function runFullBenchmark() {
    setBusy(true);
    setStatus("Running full benchmark (CPU, GPU Basic, GPU Tiled)...");

    try {
        const payload = await callApi("/api/benchmark");
        updateBenchmarkTable(payload);
        setStatus("Benchmark completed.");
    } catch (err) {
        setStatus(err.message || "Failed to run benchmark.", true);
    } finally {
        setBusy(false);
    }
}

imageInput.addEventListener("change", async (event) => {
    selectedFile = event.target.files && event.target.files.length > 0 ? event.target.files[0] : null;
    cachedGrayImage = null;

    if (!selectedFile) {
        setStatus("Upload an image to begin.");
        return;
    }

    setStatus("Preparing grayscale preview...");

    try {
        await ensureGrayImage();
        setStatus(`Ready: ${selectedFile.name}`);
    } catch (err) {
        setStatus(err.message || "Failed to load image.", true);
    }
});

runButton.addEventListener("click", () => {
    runSelectedMode();
});

benchmarkButton.addEventListener("click", () => {
    runFullBenchmark();
});
