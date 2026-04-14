const express = require("express");
const multer = require("multer");
const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const { execFile } = require("child_process");
const { promisify } = require("util");

const execFileAsync = promisify(execFile);

const app = express();
const PORT = process.env.PORT || 3000;

const ROOT_DIR = path.resolve(__dirname, "..");
const FRONTEND_DIR = path.join(ROOT_DIR, "frontend");
const BIN_DIR = path.join(ROOT_DIR, "bin");
const RUNTIME_INPUT_DIR = path.join(ROOT_DIR, "runtime", "input");
const RUNTIME_OUTPUT_DIR = path.join(ROOT_DIR, "runtime", "output");

const CPU_EXECUTABLE =
    process.platform === "win32"
        ? path.join(BIN_DIR, "cpu_blur.exe")
        : path.join(BIN_DIR, "cpu_blur");
const GPU_EXECUTABLE =
    process.platform === "win32"
        ? path.join(BIN_DIR, "gpu_blur.exe")
        : path.join(BIN_DIR, "gpu_blur");

const VALID_MODES = new Set(["cpu", "gpu_basic", "gpu_tiled"]);

const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
        fileSize: 20 * 1024 * 1024
    }
});

function isWhitespace(byte) {
    return byte === 0x20 || byte === 0x09 || byte === 0x0a || byte === 0x0d || byte === 0x0c;
}

function readPgmBuffer(buffer) {
    let index = 0;

    function skipWhitespaceAndComments() {
        while (index < buffer.length) {
            const byte = buffer[index];

            if (isWhitespace(byte)) {
                index += 1;
                continue;
            }

            if (byte === 0x23) {
                while (index < buffer.length && buffer[index] !== 0x0a) {
                    index += 1;
                }
                continue;
            }

            break;
        }
    }

    function readToken() {
        skipWhitespaceAndComments();

        if (index >= buffer.length) {
            throw new Error("Invalid PGM header.");
        }

        const start = index;

        while (index < buffer.length) {
            const byte = buffer[index];
            if (isWhitespace(byte) || byte === 0x23) {
                break;
            }
            index += 1;
        }

        return buffer.toString("ascii", start, index);
    }

    const magic = readToken();
    if (magic !== "P5") {
        throw new Error("Only binary PGM (P5) images are supported.");
    }

    const width = parseInt(readToken(), 10);
    const height = parseInt(readToken(), 10);
    const maxValue = parseInt(readToken(), 10);

    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
        throw new Error("Invalid image dimensions.");
    }

    if (maxValue !== 255) {
        throw new Error("PGM max value must be 255.");
    }

    // For P5 data, consume only the separator after max value.
    // Do not skip arbitrary whitespace-like bytes because pixel values are binary.
    if (index >= buffer.length || !isWhitespace(buffer[index])) {
        throw new Error("Invalid PGM header/data separator.");
    }

    if (buffer[index] === 0x0d && index + 1 < buffer.length && buffer[index + 1] === 0x0a) {
        index += 2;
    } else {
        index += 1;
    }

    const pixelCount = width * height;
    const end = index + pixelCount;

    if (end > buffer.length) {
        throw new Error("PGM pixel data is incomplete.");
    }

    const pixels = buffer.subarray(index, end);
    return { width, height, pixels };
}

function computeMae(a, b) {
    if (a.length !== b.length) {
        throw new Error("Image sizes differ; cannot compute MAE.");
    }

    let sum = 0;
    for (let i = 0; i < a.length; i += 1) {
        sum += Math.abs(a[i] - b[i]);
    }

    return sum / a.length;
}

function parseTimeMs(outputText) {
    const match = outputText.match(/TIME_MS=([0-9]+(?:\.[0-9]+)?)/);
    if (!match) {
        throw new Error(`Unable to parse TIME_MS from output:\n${outputText}`);
    }
    return Number.parseFloat(match[1]);
}

async function ensureRuntimeDirectories() {
    await fsp.mkdir(RUNTIME_INPUT_DIR, { recursive: true });
    await fsp.mkdir(RUNTIME_OUTPUT_DIR, { recursive: true });
}

async function runExecutable(executablePath, args) {
    if (!fs.existsSync(executablePath)) {
        throw new Error(
            `Executable not found: ${executablePath}. Build binaries before running backend.`
        );
    }

    const result = await execFileAsync(executablePath, args, {
        timeout: 120000,
        windowsHide: true,
        maxBuffer: 2 * 1024 * 1024
    });

    const mergedOutput = `${result.stdout || ""}\n${result.stderr || ""}`;
    return {
        stdout: result.stdout || "",
        stderr: result.stderr || "",
        timeMs: parseTimeMs(mergedOutput)
    };
}

async function runBlurMode(mode, inputPath, outputPath, includeVerifyFlag = false) {
    if (mode === "cpu") {
        return runExecutable(CPU_EXECUTABLE, [inputPath, outputPath]);
    }

    const args = [mode, inputPath, outputPath];
    if (includeVerifyFlag) {
        args.push("--verify");
    }

    return runExecutable(GPU_EXECUTABLE, args);
}

async function removeFiles(paths) {
    await Promise.all(
        paths.map(async (filePath) => {
            try {
                await fsp.unlink(filePath);
            } catch (err) {
                if (err && err.code !== "ENOENT") {
                    throw err;
                }
            }
        })
    );
}

function makeRequestId() {
    return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

app.use(express.static(FRONTEND_DIR));

app.get("/", (req, res) => {
    res.sendFile(path.join(FRONTEND_DIR, "index.html"));
});

app.get("/api/health", (req, res) => {
    res.json({ ok: true, message: "Gaussian blur backend is running." });
});

app.post("/api/blur", upload.single("image"), async (req, res) => {
    const filesToCleanup = [];

    try {
        if (!req.file) {
            return res.status(400).json({ error: "Image upload is required." });
        }

        const mode = req.body.mode;
        if (!VALID_MODES.has(mode)) {
            return res.status(400).json({ error: "Invalid mode. Use cpu, gpu_basic, or gpu_tiled." });
        }

        const requestId = makeRequestId();
        const inputPath = path.join(RUNTIME_INPUT_DIR, `${requestId}_input.pgm`);
        const outputPath = path.join(RUNTIME_OUTPUT_DIR, `${requestId}_${mode}.pgm`);

        filesToCleanup.push(inputPath, outputPath);

        await fsp.writeFile(inputPath, req.file.buffer);

        let cpuTimeMs = 0;
        let selectedRun;

        if (mode === "cpu") {
            selectedRun = await runBlurMode("cpu", inputPath, outputPath, false);
            cpuTimeMs = selectedRun.timeMs;
        } else {
            const cpuOutputPath = path.join(RUNTIME_OUTPUT_DIR, `${requestId}_cpu_ref.pgm`);
            filesToCleanup.push(cpuOutputPath);

            const cpuRun = await runBlurMode("cpu", inputPath, cpuOutputPath, false);
            cpuTimeMs = cpuRun.timeMs;
            selectedRun = await runBlurMode(mode, inputPath, outputPath, true);
        }

        const outputBuffer = await fsp.readFile(outputPath);
        const decoded = readPgmBuffer(outputBuffer);

        const speedup = mode === "cpu" ? 1.0 : cpuTimeMs / selectedRun.timeMs;

        return res.json({
            mode,
            executionMs: selectedRun.timeMs,
            cpuMs: cpuTimeMs,
            speedup,
            image: {
                width: decoded.width,
                height: decoded.height,
                pixelsBase64: Buffer.from(decoded.pixels).toString("base64")
            },
            rawOutput: selectedRun.stdout.trim()
        });
    } catch (err) {
        return res.status(500).json({
            error: err.message || "Unexpected backend error"
        });
    } finally {
        try {
            await removeFiles(filesToCleanup);
        } catch (cleanupErr) {
            console.error("Cleanup error:", cleanupErr.message || cleanupErr);
        }
    }
});

app.post("/api/benchmark", upload.single("image"), async (req, res) => {
    const filesToCleanup = [];

    try {
        if (!req.file) {
            return res.status(400).json({ error: "Image upload is required." });
        }

        const requestId = makeRequestId();
        const inputPath = path.join(RUNTIME_INPUT_DIR, `${requestId}_benchmark_input.pgm`);

        const cpuOutputPath = path.join(RUNTIME_OUTPUT_DIR, `${requestId}_cpu.pgm`);
        const basicOutputPath = path.join(RUNTIME_OUTPUT_DIR, `${requestId}_gpu_basic.pgm`);
        const tiledOutputPath = path.join(RUNTIME_OUTPUT_DIR, `${requestId}_gpu_tiled.pgm`);

        filesToCleanup.push(inputPath, cpuOutputPath, basicOutputPath, tiledOutputPath);

        await fsp.writeFile(inputPath, req.file.buffer);

        const cpuRun = await runBlurMode("cpu", inputPath, cpuOutputPath, false);
        const basicRun = await runBlurMode("gpu_basic", inputPath, basicOutputPath, true);
        const tiledRun = await runBlurMode("gpu_tiled", inputPath, tiledOutputPath, true);

        const cpuImage = readPgmBuffer(await fsp.readFile(cpuOutputPath));
        const basicImage = readPgmBuffer(await fsp.readFile(basicOutputPath));
        const tiledImage = readPgmBuffer(await fsp.readFile(tiledOutputPath));

        const maeBasicVsCpu = computeMae(cpuImage.pixels, basicImage.pixels);
        const maeTiledVsCpu = computeMae(cpuImage.pixels, tiledImage.pixels);

        return res.json({
            timesMs: {
                cpu: cpuRun.timeMs,
                gpuBasic: basicRun.timeMs,
                gpuTiled: tiledRun.timeMs
            },
            speedup: {
                basic: cpuRun.timeMs / basicRun.timeMs,
                tiled: cpuRun.timeMs / tiledRun.timeMs
            },
            quality: {
                maeBasicVsCpu,
                maeTiledVsCpu
            },
            tiledFasterThanBasic: tiledRun.timeMs < basicRun.timeMs
        });
    } catch (err) {
        return res.status(500).json({
            error: err.message || "Unexpected benchmark error"
        });
    } finally {
        try {
            await removeFiles(filesToCleanup);
        } catch (cleanupErr) {
            console.error("Cleanup error:", cleanupErr.message || cleanupErr);
        }
    }
});

async function startServer() {
    await ensureRuntimeDirectories();

    app.listen(PORT, () => {
        console.log(`Backend running at http://localhost:${PORT}`);
    });
}

startServer().catch((err) => {
    console.error("Failed to start backend:", err.message || err);
    process.exit(1);
});
