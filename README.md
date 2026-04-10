<img width="1273" height="715" alt="image" src="https://github.com/user-attachments/assets/4e1abddd-993e-4c35-9f69-fac1c90cb137" />

# PSX Enhanced URP Shader

I got tired of all the old an semi-fucntional PSX shaderkits and render pipelines so I made one that as of now works with Unity 6.4.1's URP.
This is A PSX/PS1-style vertex-lit shader for Unity 6 URP. Bakes all PSX 
post-process effects (dithering, quantization, pixelation, vertex 
snapping, affine texture warping) directly in-shader.

## Requirements
- Unity 6+
- Universal Render Pipeline

## Installation
Drag the `PSXShaderKit` folder into your project's `Assets/` directory.

## Features
- Vertex snapping
- Affine texture warping
- Ordered Bayer dithering + color quantization
- Proximity dither fade
- Alpha cutout support
- Per-pixel or per-vertex point/spot lights
- Triangle subdivision for better Gouraud shading
- PSX fog, film grain, noise overlay
- Cubemap environment reflections
- Compatible with PSXShaderManager.cs global settings

## Setup
1. Add `PSXShaderManager.cs` to any GameObject in your scene
2. Add `PSXPostProcessEffect.cs` to your camera
3. Assign the `PSX/Enhanced Vertex Lit (URP)` shader to your materials
4. Play around with the settings
