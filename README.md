# DLSSNR-Cost-Scaler

A standalone proxy DLL for NVIDIA DLSS-NR (DirectX 12) that adds resolution scaling and cost control. It runs the neural reconstruction model at a reduced resolution while keeping native 1:1 geometry, fine textures, text, and edges intact using a high-frequency matched residual composite shader.

Designed primarily to work alongside RenoDX addons, this proxy decouples DLSS-NR's GPU performance cost from the display resolution without introducing blur.

Tested specifically with clshortfuse's DLSS addon (`renodx-dlss.addon64`), but architected to work with any game, engine, or injector that calls `nvngx_dlssnr.dll` over DirectX 12.

---

## Features

- Standalone drop-in proxy for `nvngx_dlssnr.dll`.
- Downsamples the frame using an area-weighted box filter before evaluating the neural model.
- High-frequency matched residual resolve pass: composites the neural delta back onto the untouched native frame.
- HDR luminance bounding prevents highlight clipping and shadow instability.
- Integrated AMD RCAS (Robust Contrast Adaptive Sharpening) pass.
- In-game hot-reloading: changes made to `nvngx_dlssnr.ini` take effect within one second without restarting.
- In-game hotkeys for live toggling, mode switching, and scale adjustments.
- Handles SDR (B8G8R8A8 / R8G8B8A8), HDR10 PQ (R10G10B10A2), scRGB (R16G16B16A16_FLOAT), and 3-channel HDR (R11G11B10_FLOAT).
- Dynamic subrect tracking preserves viewport offsets for games using Dynamic Resolution Scaling (DRS).

---

## Requirements

- Windows 10/11 (64-bit)
- NVIDIA RTX GPU (RTX 20, 30, 40, or 50 series)
- A game or addon utilizing NVIDIA DLSS-NR (`nvngx_dlssnr.dll`) over DirectX 12

---

## Installation

1. Navigate to your game folder where `nvngx_dlssnr.dll` is located.
2. Rename the original `nvngx_dlssnr.dll` to:
   ```text
   nvngx_dlssnr_real.dll
   ```
3. Copy the proxy `nvngx_dlssnr.dll` and `nvngx_dlssnr.ini` from the release into that same folder.
4. Launch the game.

---

## Configuration (`nvngx_dlssnr.ini`)

The configuration file is read at startup and automatically hot-reloaded every second when modified:

```ini
[DLSSNR_Proxy]
; Master toggle for the proxy
; 1 = Proxy enabled (applies ResolutionScale)
; 0 = Proxy disabled (100% native passthrough to real DLSS-NR)
EnableProxy = 1

; Internal model resolution scale (0.25 to 1.00)
; 1.00 = 100% Native
; 0.85 = 85% Resolution (~28% faster neural pass)
; 0.80 = 80% Resolution (~35% faster)
; 0.75 = 75% Resolution (~40% faster, recommended sweet spot)
; 0.67 = 67% Resolution (DLSS Quality ratio)
; 0.50 = 50% Resolution (DLSS Performance ratio)
ResolutionScale = 0.75

; Resolve algorithm
; 1 = Matched Residual (retains native 1:1 detail + neural lighting delta)
; 0 = Classic Bilinear (stretched upscale, for comparison/debugging)
EnlargementMode = 1

; Strength of the neural detail transfer (0.0 to 2.0, default 1.0)
TransferStrength = 1.00

; Contrast-adaptive edge sharpening (0.0 to 1.0, default 0.0)
Sharpness = 0.20

; Enable in-game silent hotkeys
EnableHotkeys = 1
```

---

## In-Game Hotkeys

When `EnableHotkeys = 1`, the following keyboard shortcuts are active:

- `Ctrl + Alt + Space` — Toggle proxy ON / OFF (switches between scaled proxy and native passthrough).
- `Ctrl + Alt + End` — Toggle EnlargementMode between Matched Residual (`1`) and Bilinear (`0`).
- `Ctrl + Alt + PageUp` — Increase resolution scale by +5%.
- `Ctrl + Alt + PageDown` — Decrease resolution scale by -5%.

---

## Building from Source

Prerequisites:
- Visual Studio 2022 or Build Tools with the Desktop C++ workload.
- Windows 10/11 SDK with `fxc.exe` (DirectX Shader Compiler).

To build:
1. Open the project folder.
2. Run `build.bat` from an x64 Developer Command Prompt or standard prompt.
3. The compiled `nvngx_dlssnr.dll` will be generated in the root folder.

---

## Credits

- [Dagherbou / OptiScaler_DLSSNR](https://github.com/Dagherbou/OptiScaler_DLSSNR) — For pioneering DLSS-NR integration, the matched residual resolve concept, and feature lifecycle handling.
- [OptiScaler](https://github.com/optiscaler/OptiScaler) — For the parent upscaler framework.
- [clshortfuse / RenoDX](https://github.com/clshortfuse/renodx) — For the RenoDX framework and DLSS ReShade addon.
- [AMD](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK) — For the Robust Contrast Adaptive Sharpening (RCAS) algorithm.

---

## License

This project is licensed under the [MIT License](LICENSE).
