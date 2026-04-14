$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Join-Path $root "Report_Format.docx"
$outputPath = Join-Path $root "Mini_Project_Report_Abhinav_Mohapatra.docx"

if (-not (Test-Path $templatePath)) {
    throw "Template file Report_Format.docx was not found in the project root."
}

Copy-Item -Path $templatePath -Destination $outputPath -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($outputPath, [System.IO.Compression.ZipArchiveMode]::Update)
$documentEntry = $zip.GetEntry("word/document.xml")
if ($null -eq $documentEntry) {
    $zip.Dispose()
    throw "word/document.xml not found inside the template."
}

$reader = New-Object System.IO.StreamReader($documentEntry.Open())
$documentXmlText = $reader.ReadToEnd()
$reader.Close()

[xml]$doc = $documentXmlText
$ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
$ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

$body = $doc.SelectSingleNode("//w:body", $ns)
if ($null -eq $body) {
    $zip.Dispose()
    throw "The template document body could not be located."
}

$sectPr = $body.SelectSingleNode("w:sectPr", $ns)
$existingNodes = @($body.ChildNodes)
foreach ($node in $existingNodes) {
    if ($node -ne $sectPr) {
        [void]$body.RemoveChild($node)
    }
}

function Add-Paragraph {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [bool]$Bold = $false,
        [bool]$Center = $false
    )

    $wNs = $ns.LookupNamespace("w")
    $p = $doc.CreateElement("w", "p", $wNs)

    if ($Center) {
        $pPr = $doc.CreateElement("w", "pPr", $wNs)
        $jc = $doc.CreateElement("w", "jc", $wNs)
        $val = $doc.CreateAttribute("w", "val", $wNs)
        $val.Value = "center"
        [void]$jc.Attributes.Append($val)
        [void]$pPr.AppendChild($jc)
        [void]$p.AppendChild($pPr)
    }

    if ($Text.Length -gt 0) {
        $r = $doc.CreateElement("w", "r", $wNs)

        if ($Bold) {
            $rPr = $doc.CreateElement("w", "rPr", $wNs)
            $b = $doc.CreateElement("w", "b", $wNs)
            [void]$rPr.AppendChild($b)
            [void]$r.AppendChild($rPr)
        }

        $t = $doc.CreateElement("w", "t", $wNs)
        if ($Text.StartsWith(" ") -or $Text.EndsWith(" ")) {
            $spaceAttr = $doc.CreateAttribute("xml", "space", "http://www.w3.org/XML/1998/namespace")
            $spaceAttr.Value = "preserve"
            [void]$t.Attributes.Append($spaceAttr)
        }

        $t.InnerText = $Text
        [void]$r.AppendChild($t)
        [void]$p.AppendChild($r)
    }

    if ($null -ne $sectPr) {
        [void]$body.InsertBefore($p, $sectPr)
    } else {
        [void]$body.AppendChild($p)
    }
}

$lines = @(
    @{ t = "GAUSSIAN BLUR USING CUDA WITH TILING OPTIMIZATION AND WEB INTERFACE"; b = $true; c = $true },
    @{ t = "Mini-Project Report"; b = $true; c = $true },
    @{ t = ""; b = $false; c = $false },
    @{ t = "Author: Abhinav Mohapatra"; b = $false; c = $true },
    @{ t = "Affiliation: Department of Computer Science and Engineering, Manipal Institute of Technology, Manipal, Karnataka - 576104"; b = $false; c = $true },
    @{ t = "Project Guide: <<Name of the Internal Guide>>, <<Designation of the internal guide>>"; b = $false; c = $true },
    @{ t = "Date: 14 April 2026"; b = $false; c = $true },
    @{ t = ""; b = $false; c = $false },

    @{ t = "ABSTRACT"; b = $true; c = $false },
    @{ t = "This mini-project presents the design and implementation of a Gaussian blur system across three computational paradigms: sequential CPU processing in C, parallel GPU processing in CUDA using global memory, and an optimized CUDA implementation using shared-memory tiling with halo loading. The project further integrates a web-based interface and backend service to execute selected modes and display output images with performance metrics. The implemented evaluation framework measures CPU execution time, GPU basic execution time, and GPU tiled execution time, and computes speedup values relative to CPU execution. The system demonstrates how memory hierarchy optimization in CUDA can substantially improve throughput for convolution workloads while preserving output quality relative to the CPU reference."; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 1: INTRODUCTION"; b = $true; c = $false },
    @{ t = "1.1 General Introduction to the Topic"; b = $true; c = $false },
    @{ t = "Gaussian blur is a widely used image processing operation for noise reduction and smoothing. It performs a weighted convolution in which neighboring pixels contribute to the output based on a Gaussian distribution. Since convolution is computationally intensive for large images, this operation is a suitable candidate for parallel acceleration using Graphics Processing Units (GPUs)."; b = $false; c = $false },
    @{ t = "1.2 Organization"; b = $true; c = $false },
    @{ t = "The report is organized into eight chapters covering problem definition, objectives, background concepts, methodology, implementation details, contribution summary, and references."; b = $false; c = $false },
    @{ t = "1.3 Area of Computer Science"; b = $true; c = $false },
    @{ t = "The project lies at the intersection of parallel computing, high-performance computing, and full-stack software engineering, with a focus on CUDA-based optimization for image processing pipelines."; b = $false; c = $false },
    @{ t = "1.4 Hardware and Software Requirements"; b = $true; c = $false },
    @{ t = "Hardware Requirements:"; b = $true; c = $false },
    @{ t = "- Multi-core CPU (x86_64)"; b = $false; c = $false },
    @{ t = "- NVIDIA GPU with CUDA support"; b = $false; c = $false },
    @{ t = "- Minimum 8 GB RAM"; b = $false; c = $false },
    @{ t = "Software Requirements:"; b = $true; c = $false },
    @{ t = "- Operating System: Windows or Linux"; b = $false; c = $false },
    @{ t = "- CUDA Toolkit (for nvcc and runtime libraries)"; b = $false; c = $false },
    @{ t = "- GCC/Clang compiler for CPU code"; b = $false; c = $false },
    @{ t = "- Node.js and npm for backend service"; b = $false; c = $false },
    @{ t = "- Modern web browser for frontend visualization"; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 2: PROBLEM DEFINITION"; b = $true; c = $false },
    @{ t = "Conventional CPU-based Gaussian blur becomes time-consuming for high-resolution images due to sequential execution. A basic GPU implementation improves parallelism but may still underutilize memory bandwidth because repeated neighborhood accesses are served from global memory. The problem is to design and demonstrate an optimized GPU approach that reduces memory latency and improves performance while maintaining output fidelity."; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 3: OBJECTIVES"; b = $true; c = $false },
    @{ t = "The primary objectives of this mini-project are:"; b = $false; c = $false },
    @{ t = "- To implement a CPU-based Gaussian blur in C."; b = $false; c = $false },
    @{ t = "- To implement a basic CUDA Gaussian blur kernel using global memory."; b = $false; c = $false },
    @{ t = "- To implement an optimized CUDA Gaussian blur kernel using shared-memory tiling with halo loading and synchronization."; b = $false; c = $false },
    @{ t = "- To build a web frontend and backend for mode selection, execution, and result display."; b = $false; c = $false },
    @{ t = "- To compare execution time and speedup for CPU, GPU basic, and GPU tiled implementations."; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 4: BACKGROUND"; b = $true; c = $false },
    @{ t = "A 3x3 Gaussian kernel applies weighted averaging where central pixels have higher influence. In CUDA, each thread typically maps to one output pixel. The basic kernel reads neighboring pixels directly from global memory. In contrast, tiled optimization uses shared memory to cache a block-local tile and its halo region. Since shared memory has lower access latency, repeated neighbor lookups are faster, improving effective throughput for convolution operations."; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 5: METHODOLOGY"; b = $true; c = $false },
    @{ t = "The adopted methodology consists of the following stages:"; b = $false; c = $false },
    @{ t = "1. Image acquisition and conversion to grayscale PGM format."; b = $false; c = $false },
    @{ t = "2. CPU execution path for reference output generation."; b = $false; c = $false },
    @{ t = "3. GPU basic kernel execution with direct global memory accesses."; b = $false; c = $false },
    @{ t = "4. GPU tiled kernel execution with shared tile size (BLOCK_SIZE + 2) x (BLOCK_SIZE + 2), including halo pixels."; b = $false; c = $false },
    @{ t = "5. Time measurement and speedup computation."; b = $false; c = $false },
    @{ t = "6. API-based orchestration and browser visualization of outputs and metrics."; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 6: IMPLEMENTATION DETAILS"; b = $true; c = $false },
    @{ t = "6.1 Core Native Modules"; b = $true; c = $false },
    @{ t = "The core folder contains cpu_blur.c, gpu_blur.cu, image_io.c, and image_io.h. The CPU module performs sequential 3x3 convolution with clamped boundaries. The CUDA module includes both kernels: gaussianBlurBasic and gaussianBlurTiled."; b = $false; c = $false },
    @{ t = "6.2 CUDA Basic Kernel"; b = $true; c = $false },
    @{ t = "In gaussianBlurBasic, each thread computes one output pixel and accesses all required neighboring pixels from global memory. This model is straightforward and highly parallel but can suffer from repeated global memory transactions."; b = $false; c = $false },
    @{ t = "6.3 CUDA Tiled Kernel (Shared Memory Optimization)"; b = $true; c = $false },
    @{ t = "The tiled kernel uses a 16x16 block. Shared memory is declared as tile[BLOCK_SIZE+2][BLOCK_SIZE+2] to accommodate the central block and one-pixel halo on all sides. Threads cooperatively load central and halo data into shared memory, followed by __syncthreads(). Convolution is then computed from shared memory, reducing global memory access overhead."; b = $false; c = $false },
    @{ t = "6.4 Backend and Frontend Integration"; b = $true; c = $false },
    @{ t = "The backend exposes /api/blur and /api/benchmark endpoints that accept mode selection (cpu, gpu_basic, gpu_tiled), execute corresponding binaries, and return execution metrics with output image data. The frontend provides a mode selector, image upload, canvas-based preview, execution-time display, and comparative benchmark table."; b = $false; c = $false },
    @{ t = "6.5 Performance Metrics and Validation"; b = $true; c = $false },
    @{ t = "The project computes the following metrics:"; b = $false; c = $false },
    @{ t = "Speedup (basic) = T_CPU / T_GPU_basic"; b = $false; c = $false },
    @{ t = "Speedup (tiled) = T_CPU / T_GPU_tiled"; b = $false; c = $false },
    @{ t = "Output similarity is assessed using Mean Absolute Error (MAE) against the CPU reference."; b = $false; c = $false },
    @{ t = "Benchmark recording table (to be filled from execution logs):"; b = $false; c = $false },
    @{ t = "- CPU Time (ms): __________________"; b = $false; c = $false },
    @{ t = "- GPU Basic Time (ms): ____________"; b = $false; c = $false },
    @{ t = "- GPU Tiled Time (ms): ____________"; b = $false; c = $false },
    @{ t = "- Speedup (basic): ________________"; b = $false; c = $false },
    @{ t = "- Speedup (tiled): ________________"; b = $false; c = $false },
    @{ t = "- MAE (CPU vs GPU basic): _________"; b = $false; c = $false },
    @{ t = "- MAE (CPU vs GPU tiled): _________"; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 7: CONTRIBUTION SUMMARY"; b = $true; c = $false },
    @{ t = "This project was carried out as an individual submission. All major components, including CPU implementation, CUDA kernel development, tiling optimization, backend API development, frontend interface design, integration, and validation workflow were completed by Abhinav Mohapatra."; b = $false; c = $false },
    @{ t = ""; b = $false; c = $false },

    @{ t = "CHAPTER 8: REFERENCES"; b = $true; c = $false },
    @{ t = "[1] NVIDIA Corporation, CUDA C++ Programming Guide, NVIDIA Documentation, 2025."; b = $false; c = $false },
    @{ t = "[2] R. C. Gonzalez and R. E. Woods, Digital Image Processing, 4th ed., Pearson, 2018."; b = $false; c = $false },
    @{ t = "[3] D. B. Kirk and W. W. Hwu, Programming Massively Parallel Processors, 4th ed., Morgan Kaufmann, 2022."; b = $false; c = $false },
    @{ t = "[4] J. Sanders and E. Kandrot, CUDA by Example: An Introduction to General-Purpose GPU Programming, Addison-Wesley, 2010."; b = $false; c = $false },
    @{ t = "[5] MDN Web Docs, Fetch API and Canvas API Documentation, Mozilla Developer Network, accessed April 2026."; b = $false; c = $false },
    @{ t = "[6] OpenJS Foundation, Node.js Documentation, Express.js Documentation, accessed April 2026."; b = $false; c = $false }
)

foreach ($line in $lines) {
    Add-Paragraph -Text $line.t -Bold $line.b -Center $line.c
}

$tempXmlPath = Join-Path $env:TEMP ("document_" + [Guid]::NewGuid().ToString() + ".xml")
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$settings.Indent = $true
$writer = [System.Xml.XmlWriter]::Create($tempXmlPath, $settings)
$doc.Save($writer)
$writer.Close()

$documentEntry.Delete()
[void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $zip,
    $tempXmlPath,
    "word/document.xml",
    [System.IO.Compression.CompressionLevel]::Optimal
)

$zip.Dispose()
Remove-Item -Path $tempXmlPath -Force

Write-Host "Report generated successfully: $outputPath"
