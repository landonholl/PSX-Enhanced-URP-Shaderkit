#ifndef PSX_SNAP_INCLUDED
#define PSX_SNAP_INCLUDED

// Set globally every frame by PSXShaderManager.cs via Shader.SetGlobalFloat.
float _PSX_GridSize;

// Snap a clip-space position to a uniform screen-space grid.
// Operates in NDC (after perspective divide) so grid density is
// depth-independent — matching PS1 GTE behaviour.
// gridSize 0 or near-zero = passthrough (snapping disabled).
float4 PSX_SnapClip(float4 clipPos, float gridSize)
{
    if (gridSize < 0.00001f) return clipPos;
    float2 ndc = clipPos.xy / clipPos.w;
    ndc = floor(ndc * gridSize + 0.5f) / gridSize;
    clipPos.xy = ndc * clipPos.w;
    return clipPos;
}

// Resolve the effective grid size for a given material's snap settings.
// Returns 0 (disabled) when vertexSnapping is off.
float PSX_ResolveSnapGrid(float vertexSnapping, float snapResolution)
{
    return (vertexSnapping < 0.5f) ? 0.0f
         : (snapResolution > 0.0001f) ? snapResolution
         : _PSX_GridSize;
}

#endif // PSX_SNAP_INCLUDED
