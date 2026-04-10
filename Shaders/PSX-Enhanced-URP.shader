// PSX Enhanced Vertex Lit — URP
// Replaces the Built-in "PSX/Vertex Lit" for Universal Render Pipeline.
// Bakes all PSX post-process effects (dithering, quantization, pixelation) in-shader
// because URP does not support OnRenderImage / camera image effects.
// Compatible with PSXShaderManager.cs (respects all its global floats & keywords).

Shader "PSX/Enhanced Vertex Lit (URP)"
{
    Properties
    {
        [Header(Surface)]
        _MainTex        ("Albedo Texture",                  2D)         = "white" {}
        _Color          ("Tint Color",                      Color)      = (1,1,1,1)

        [Header(Emission)]
        _EmissiveTex    ("Emission Texture",                2D)         = "black" {}
        _EmissionColor  ("Emission (RGB) Strength (A)",     Color)      = (0,0,0,0)

        [Header(Cubemap Reflection)]
        _Cubemap        ("Reflection Cubemap",              Cube)       = "" {}
        _ReflectionMap  ("Reflection Mask",                 2D)         = "white" {}
        _CubemapColor   ("Reflection (RGB) Strength (A)",   Color)      = (0,0,0,0)

        [Header(Specular)]
        _PSXSpecColor   ("Specular Color",                  Color)      = (0.1,0.1,0.1,1)
        _PSXShininess   ("Shininess",                       Range(1,128))   = 16

        [Header(PSX Visual Style)]
        _ObjectDithering    ("Per-Object Dithering",        Range(0,1)) = 1
        _ColorBits          ("Color Bits Per Channel (5=PSX 15-bit)", Range(1,8)) = 5
        _DitherStrength     ("Dither Strength",             Range(0,1)) = 1
        _DitherScale        ("Dither Cell Size (px) — match your render resolution downscale", Range(1,8)) = 1
        _FlatShading        ("Flat Shading",                Range(0,1)) = 0

        [Header(Lighting)]
        [Toggle(_PER_PIXEL_LIGHTS)] _PerPixelAdditionalLights ("Per-Pixel Point/Spot Lights", Float) = 1
        _LightQuantization ("Light Quantization Steps (0=smooth)", Float) = 0
        [Toggle(_SUBDIVIDE)] _Subdivide ("Subdivide Triangles (Improves vertex lighting on large faces)", Float) = 0

        [Header(Vertex Snapping)]
        [Toggle] _VertexSnapping        ("Enable Vertex Snapping",              Float)      = 1
        _VertexSnapResolution           ("Resolution Override (0 = use global)", Float)     = 0

        [Header(Interaction)]
        [Toggle] _IsLit ("Lit (uncheck = highlighted when looked at)", Float) = 1
        _HighlightColor ("Highlight Color (RGB) Strength (A)", Color) = (1,1,1,0.15)

        [Header(Proximity Fade)]
        [Toggle(_PROXIMITY_FADE)] _ProximityFade ("Enable Proximity Dither Fade", Float) = 0
        _ProximityFadeStart ("Fade Start Distance", Float) = 0.8
        _ProximityFadeEnd   ("Fade End Distance (fully clipped)", Float) = 0.3

        [Header(Alpha Cutout)]
        [Toggle(_ALPHA_TEST)] _AlphaTest ("Enable Alpha Cutout", Float) = 0
        _Cutoff ("Cutoff Threshold", Range(0,1)) = 0.5

        [Header(Transparency)]
        [Toggle(_TRANSPARENT)] _Transparent ("Enable Transparency", Float) = 0
        _Alpha ("Alpha", Range(0,1)) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 0
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1

        [Header(Geometry)]
        _CustomDepthOffset  ("Custom Depth Offset",         Float)      = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull Mode",     Float) = 2
    }

    SubShader
    {
        Tags
        {
            "RenderType"        = "TransparentCutout"
            "RenderPipeline"    = "UniversalPipeline"
            "Queue"             = "Geometry"
        }
        Blend [_SrcBlend] [_DstBlend]
        ZWrite [_ZWrite]
        Cull [_Cull]

        // ─────────────────────────────────────────────────────────────────────
        // Main forward pass
        // NOTE: Geometry shaders disable SRP Batcher. This is a known URP
        // limitation — PSX vertex snapping requires geometry shaders.
        // ─────────────────────────────────────────────────────────────────────
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex      vert
            #pragma geometry    geom
            #pragma fragment    frag

            // Fog
            #pragma multi_compile_fog

            // PSXShaderManager keywords (set globally by PSXShaderManager.cs)
            #pragma multi_compile __ PSX_ENABLE_CUSTOM_VERTEX_LIGHTING
            #pragma multi_compile __ PSX_FLAT_SHADING_MODE_CENTER
            #pragma multi_compile PSX_TRIANGLE_SORT_OFF \
                                  PSX_TRIANGLE_SORT_CENTER_Z \
                                  PSX_TRIANGLE_SORT_CLOSEST_Z \
                                  PSX_TRIANGLE_SORT_CENTER_VIEWDIST \
                                  PSX_TRIANGLE_SORT_CLOSEST_VIEWDIST

            // URP lighting keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _FORWARD_PLUS

            // Per-material: per-pixel point/spot lights vs pure per-vertex
            #pragma shader_feature_local _PER_PIXEL_LIGHTS
            // Per-material: subdivide each triangle once (4x faces) for better vertex lighting
            #pragma shader_feature_local _SUBDIVIDE
            // Per-material: alpha blending
            #pragma shader_feature_local _TRANSPARENT
            // Per-material: alpha cutout / clip
            #pragma shader_feature_local _ALPHA_TEST
            // Per-material: proximity dither fade when close to camera
            #pragma shader_feature_local _PROXIMITY_FADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ── Material constant buffer (required for SRP Batcher on non-geom passes) ──
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _EmissiveTex_ST;
                half4  _Color;
                half4  _EmissionColor;
                half4  _CubemapColor;
                half4  _PSXSpecColor;
                float  _PSXShininess;
                half   _ObjectDithering;
                float  _ColorBits;
                half   _DitherStrength;
                float  _DitherScale;
                half   _FlatShading;
                float  _CustomDepthOffset;
                float  _VertexSnapping;
                float  _VertexSnapResolution;
                float  _LightQuantization;
                float  _IsLit;
                half4  _HighlightColor;
                float  _ProximityFadeStart;
                float  _ProximityFadeEnd;
                float  _Alpha;
                float  _Cutoff;
                float  _SrcBlend;
                float  _DstBlend;
                float  _ZWrite;
            CBUFFER_END

            // Textures
            TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
            TEXTURE2D(_EmissiveTex);    SAMPLER(sampler_EmissiveTex);
            TEXTURE2D(_ReflectionMap);  SAMPLER(sampler_ReflectionMap);
            TEXTURECUBE(_Cubemap);      SAMPLER(sampler_Cubemap);

            // ── PSXShaderManager globals (set via Shader.SetGlobalFloat) ──────
            float _PSX_GridSize;
            float _PSX_LightingNormalFactor;
            float _PSX_TextureWarpingFactor;
            float _PSX_TextureWarpingMode;
            float _PSX_VertexWobbleMode;
            float _PSX_LightFalloffPercent;
            float _PSX_DepthDebug;
            float _PSX_GrainStrength;
            float _PSX_GrainSize;
            float _PSX_NoiseStrength;
            float _PSX_NoiseTime;
            // Set by PSXPostProcessEffect — PerObject_Accurate mode enables this
            float _PSX_ObjectDithering;

            // PSX fog (set by PSXShaderManager)
            float _PSX_FogEnabled;
            float _PSX_FogStart;
            float _PSX_FogEnd;
            float4 _PSX_FogColor;
            float _PSX_FogSteps;

            // ─────────────────────────────────────────────────────────────────
            // Structs
            // ─────────────────────────────────────────────────────────────────
            struct appdata
            {
                float4 vertex   : POSITION;
                float3 normal   : NORMAL;
                float2 uv       : TEXCOORD0;
            };

            // Vertex → Geometry
            struct v2g
            {
                float4 viewPos      : TEXCOORD0;    // View-space position (for snapping)
                float3 worldPos     : TEXCOORD1;    // World-space position (for lighting)
                float3 worldNormal  : TEXCOORD2;    // World-space normal
                float2 uv           : TEXCOORD3;
                float3 reflDir      : TEXCOORD4;    // World-space reflection dir for cubemap
            };

            // Geometry → Fragment
            struct g2f
            {
                float4 vertex       : SV_POSITION;
                float4 affineUV     : TEXCOORD0;    // Affine (perspective-incorrect) albedo UV
                float4 affineUV2    : TEXCOORD1;    // Affine emission UV
                half4  lightColor   : TEXCOORD2;    // Per-vertex directional + ambient light
                float  fogFactor    : TEXCOORD3;
                float3 reflDir      : TEXCOORD4;
                float  customDepth  : TEXCOORD5;
                float3 worldPos     : TEXCOORD6;    // For per-pixel additional lights
                float3 worldNormal  : TEXCOORD7;    // For per-pixel additional lights
            };

            // Fragment output — SV_Depth only needed for triangle sorting
            struct fragOut
            {
                half4 color : SV_Target;
                #ifndef PSX_TRIANGLE_SORT_OFF
                float depth : SV_Depth;
                #endif
            };

            // ─────────────────────────────────────────────────────────────────
            // PSX Utility Functions
            // ─────────────────────────────────────────────────────────────────

            // Snap a clip-space position to the PSX resolution grid.
            // Snapping is performed in NDC space (AFTER the perspective divide)
            // so that vertices shared between adjacent triangles always round to
            // the same screen-space grid point.  This matches the PS1 GTE
            // hardware and is the only approach that prevents edge/vertex cracks.
            //
            // View-space or homogeneous-clip-space snapping both fail because the
            // effective grid density changes with depth, so the same world vertex
            // can round to different screen pixels depending on which triangle
            // invokes the geometry shader — producing hairline seams.
            float4 PSX_SnapClip(float4 clipPos, float gridSize)
            {
                if (gridSize < 0.00001f)
                    return clipPos;
                float2 ndc = clipPos.xy / clipPos.w;
                ndc = floor(ndc * gridSize + 0.5f) / gridSize;
                clipPos.xy = ndc * clipPos.w;
                return clipPos;
            }

            // Perspective-incorrect (affine) UV mapping — causes the characteristic
            // texture swimming of PS1 games.
            float4 PSX_AffineUV(float4 viewVertex, float2 uv)
            {
                float affineFactor = (_PSX_TextureWarpingMode < 0.5f)
                    ? length(viewVertex.xyz)
                    : max(mul(UNITY_MATRIX_P, viewVertex).w, 0.1f);
                affineFactor = lerp(1.0f, affineFactor, _PSX_TextureWarpingFactor);
                return float4(uv * affineFactor, affineFactor, 0.0f);
            }

            // Bayer 4x4 ordered dither offset — values 0..7, average = 3.5 (perfectly unbiased).
            // Previous Built-in kit used -4..+3 (average -0.5 = systematic darkening). Fixed here.
            int PSX_BayerOffset(int2 px)
            {
                static const int bayer[16] =
                {
                    0, 4, 1, 5,
                    6, 2, 7, 3,
                    1, 5, 0, 4,
                    7, 3, 6, 2
                };
                return bayer[(px.x % 4) + (px.y % 4) * 4];
            }

            // Quantize color to n-bit per channel with Bayer ordered dithering.
            // At bits=5 this matches PSX 15-bit color (5R 5G 5B).
            // DitherStrength=0 → simple rounding (no pattern). =1 → full ordered dither.
            half4 PSX_Quantize(half4 color, int2 pixelPos, float bits, float strength)
            {
                float levels   = round(pow(2.0f, bits));    // 32 for 5-bit
                float maxLevel = levels - 1.0f;             // 31

                // Scale to [0, maxLevel]
                float4 scaled  = saturate(color) * maxLevel;
                float4 lo      = floor(scaled);
                float4 frac_v  = scaled - lo;               // sub-level position [0, 1)

                // Unbiased threshold: (offset + 0.5) / 8 → range (0.0625, 0.9375), mean = 0.5
                float threshold = (PSX_BayerOffset(pixelPos) + 0.5f) / 8.0f;

                // At strength=0 use 0.5 (pure rounding). At strength=1 use Bayer threshold.
                float t = lerp(0.5f, threshold, strength);

                float4 dithered = clamp(lo + step(t, frac_v), 0.0f, maxLevel);
                return half4(dithered / maxLevel);
            }

            // Quantize a light contribution to a fixed number of steps.
            // Simulates the limited arithmetic precision of the PS1 GTE,
            // producing visible banding/stepping on lit surfaces.
            // steps=0 → smooth (passthrough).
            half3 PSX_QuantizeLight(half3 light, float steps)
            {
                if (steps < 1.0f) return light;
                return floor(light * steps + 0.5f) / steps;
            }

            // ─────────────────────────────────────────────────────────────────
            // Per-Vertex PSX Lighting — ambient + main directional only.
            // Evaluated in the geometry shader so large polygons get Gouraud
            // shading across the directional light without needing subdivision.
            // ─────────────────────────────────────────────────────────────────
            half3 PSX_ShadeVertex(float3 worldPos, float3 worldNormal)
            {
                half3 col = half3(unity_AmbientSky.rgb);

                Light mainLight = GetMainLight();
                float NdotL = max(0.0f, dot(worldNormal, mainLight.direction));
                float diff = lerp(mainLight.distanceAttenuation,
                                  NdotL * mainLight.distanceAttenuation,
                                  _PSX_LightingNormalFactor);
                col += mainLight.color * diff;

                // When per-pixel lights are off, evaluate point/spot lights here
                // per-vertex (authentic PSX Gouraud — requires dense geometry to look good).
                #ifndef _PER_PIXEL_LIGHTS
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0; i < min(lightCount, 4u); i++)
                {
                    Light light = GetAdditionalLight(i, worldPos);
                    float NdotL = max(0.0f, dot(worldNormal, light.direction));

                    #ifdef PSX_ENABLE_CUSTOM_VERTEX_LIGHTING
                    float atten = saturate(light.distanceAttenuation * (1.0f / max(1.0f - _PSX_LightFalloffPercent, 0.001f)));
                    #else
                    float atten = light.distanceAttenuation;
                    #endif

                    if (_LightQuantization >= 1.0f)
                        atten = floor(atten * _LightQuantization + 0.5f) / _LightQuantization;

                    float diff = lerp(atten, NdotL * atten, _PSX_LightingNormalFactor);
                    col += light.color * diff;
                }
                #endif

                return PSX_QuantizeLight(col, _LightQuantization);
            }

            // ─────────────────────────────────────────────────────────────────
            // Per-Pixel Additional Lights — point/spot lights evaluated in the
            // fragment shader so they correctly illuminate large low-poly surfaces
            // without requiring geometry subdivision.
            // ─────────────────────────────────────────────────────────────────
            half3 PSX_ShadeAdditionalLights(float3 worldPos, float3 worldNormal)
            {
                half3 col = 0;

                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0; i < min(lightCount, 4u); i++)
                {
                    Light light = GetAdditionalLight(i, worldPos);
                    float NdotL = max(0.0f, dot(worldNormal, light.direction));

                    #ifdef PSX_ENABLE_CUSTOM_VERTEX_LIGHTING
                    float atten = saturate(light.distanceAttenuation * (1.0f / max(1.0f - _PSX_LightFalloffPercent, 0.001f)));
                    #else
                    float atten = light.distanceAttenuation;
                    #endif

                    // Quantize the scalar attenuation (not per-channel RGB) so banding
                    // rings preserve the light's color instead of creating rainbow fringing.
                    if (_LightQuantization >= 1.0f)
                        atten = floor(atten * _LightQuantization + 0.5f) / _LightQuantization;

                    float diff = lerp(atten, NdotL * atten, _PSX_LightingNormalFactor);
                    col += light.color * diff;
                }
                return col;
            }

            // ─────────────────────────────────────────────────────────────────
            // Triangle Sorting Depth Helpers
            // (mimics PSX painter's algorithm — no hardware Z-buffer)
            // ─────────────────────────────────────────────────────────────────
            float PSX_DepthCenterZ(float4 v0, float4 v1, float4 v2)
            {
                float4 c = (v0 + v1 + v2) * 0.3333f;
                c.xyz += normalize(c.xyz) * _CustomDepthOffset;
                c.z    = min(c.z, -0.0001f);
                float4 clip = mul(UNITY_MATRIX_P, c);
                return saturate(clip.z / clip.w);
            }

            float PSX_DepthClosestZ(float4 v0, float4 v1, float4 v2)
            {
                v0 = mul(UNITY_MATRIX_P, v0);
                v1 = mul(UNITY_MATRIX_P, v1);
                v2 = mul(UNITY_MATRIX_P, v2);
                float d = 1.0f;
                d = lerp(d, min(d, v0.z / v0.w), step(0.0f, v0.w));
                d = lerp(d, min(d, v1.z / v1.w), step(0.0f, v1.w));
                d = lerp(d, min(d, v2.z / v2.w), step(0.0f, v2.w));
                return saturate(d);
            }

            float PSX_DepthCenterViewDist(float4 v0, float4 v1, float4 v2)
            {
                float3 c = ((v0 + v1 + v2) * 0.3333f).xyz;
                c += normalize(c) * _CustomDepthOffset;
                c.z = min(c.z, -0.0001f);
                return saturate(1.0f - length(c) * _ProjectionParams.w);
            }

            // ─────────────────────────────────────────────────────────────────
            // Vertex Shader
            // ─────────────────────────────────────────────────────────────────
            v2g vert(appdata v)
            {
                v2g o;
                o.worldPos    = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.viewPos     = mul(UNITY_MATRIX_V, float4(o.worldPos, 1.0));
                o.worldNormal = TransformObjectToWorldNormal(v.normal);
                o.uv          = v.uv;

                // viewPos is kept unsnapped — snapping is done in NDC space in the geometry
                // shader so the grid aligns with actual screen pixels (matching PS1 GTE behaviour).
                // NDC snapping is uniform at all depths; view-space snapping was depth-dependent
                // and produced larger screen-space gaps at distance.

                // Reflection direction for optional cubemap env mapping
                float3 viewDir = normalize(o.worldPos - _WorldSpaceCameraPos);
                o.reflDir = reflect(viewDir, o.worldNormal);

                return o;
            }

            // ─────────────────────────────────────────────────────────────────
            // Geometry Shader Helpers
            // ─────────────────────────────────────────────────────────────────

            // Interpolate two v2g structs at the midpoint (used for subdivision).
            v2g PSX_MidV2G(v2g a, v2g b)
            {
                v2g o;
                o.viewPos     = (a.viewPos    + b.viewPos)    * 0.5f;
                o.worldPos    = (a.worldPos   + b.worldPos)   * 0.5f;
                o.worldNormal = normalize(a.worldNormal + b.worldNormal);
                o.uv          = (a.uv         + b.uv)         * 0.5f;
                float3 vd     = normalize(o.worldPos - _WorldSpaceCameraPos);
                o.reflDir     = reflect(vd, o.worldNormal);
                return o;
            }

            // Convert a v2g to a fully processed g2f (lighting, affine UVs, fog).
            // viewPos is already snapped in the vertex shader — no further snapping needed.
            g2f PSX_ProcessVert(v2g v, float triDepth)
            {
                g2f o;
                o.lightColor  = half4(PSX_ShadeVertex(v.worldPos, v.worldNormal), 1.0f);
                o.affineUV    = PSX_AffineUV(v.viewPos, TRANSFORM_TEX(v.uv, _MainTex));
                o.affineUV2   = PSX_AffineUV(v.viewPos, TRANSFORM_TEX(v.uv, _EmissiveTex));
                o.reflDir     = v.reflDir;
                o.customDepth = triDepth;
                o.worldPos    = v.worldPos;
                o.worldNormal = v.worldNormal;
                float4 clip   = mul(UNITY_MATRIX_P, v.viewPos);
                o.vertex      = PSX_SnapClip(clip,
                                    (_VertexSnapping < 0.5f) ? 0.0f :
                                    ((_VertexSnapResolution > 0.0001f) ? _VertexSnapResolution : _PSX_GridSize));
                o.fogFactor   = ComputeFogFactor(clip.z);
                return o;
            }

            // ─────────────────────────────────────────────────────────────────
            // Geometry Shader
            // Handles: vertex snapping, affine UV, per-vertex lighting, flat shading,
            //          triangle depth sorting, fog, optional 1-level subdivision.
            // ─────────────────────────────────────────────────────────────────
            #ifdef _SUBDIVIDE
            [maxvertexcount(12)]
            #else
            [maxvertexcount(3)]
            #endif
            void geom(triangle v2g IN[3], inout TriangleStream<g2f> stream)
            {
                // ── Triangle sort depth ──────────────────────────────────────
                float triDepth = 0.0f;
                #ifndef PSX_TRIANGLE_SORT_OFF
                    #if defined(PSX_TRIANGLE_SORT_CENTER_Z)
                        triDepth = PSX_DepthCenterZ(IN[0].viewPos, IN[1].viewPos, IN[2].viewPos);
                    #elif defined(PSX_TRIANGLE_SORT_CLOSEST_Z)
                        triDepth = PSX_DepthClosestZ(IN[0].viewPos, IN[1].viewPos, IN[2].viewPos);
                    #elif defined(PSX_TRIANGLE_SORT_CENTER_VIEWDIST) || defined(PSX_TRIANGLE_SORT_CLOSEST_VIEWDIST)
                        triDepth = PSX_DepthCenterViewDist(IN[0].viewPos, IN[1].viewPos, IN[2].viewPos);
                    #else
                        triDepth = PSX_DepthCenterZ(IN[0].viewPos, IN[1].viewPos, IN[2].viewPos);
                    #endif
                #endif

                #ifdef _SUBDIVIDE
                // ── 1-level subdivision: triangle → 4 sub-triangles ──────────
                // Computes a midpoint vertex on each edge, giving the vertex
                // lighting more sample points across large flat surfaces.
                // Flat shading is skipped in this mode (incompatible goal).
                v2g m01 = PSX_MidV2G(IN[0], IN[1]);
                v2g m12 = PSX_MidV2G(IN[1], IN[2]);
                v2g m20 = PSX_MidV2G(IN[2], IN[0]);

                // Corner 0: IN[0], m01, m20
                stream.Append(PSX_ProcessVert(IN[0], triDepth));
                stream.Append(PSX_ProcessVert(m01,   triDepth));
                stream.Append(PSX_ProcessVert(m20,   triDepth));
                stream.RestartStrip();

                // Corner 1: m01, IN[1], m12
                stream.Append(PSX_ProcessVert(m01,   triDepth));
                stream.Append(PSX_ProcessVert(IN[1], triDepth));
                stream.Append(PSX_ProcessVert(m12,   triDepth));
                stream.RestartStrip();

                // Corner 2: m20, m12, IN[2]
                stream.Append(PSX_ProcessVert(m20,   triDepth));
                stream.Append(PSX_ProcessVert(m12,   triDepth));
                stream.Append(PSX_ProcessVert(IN[2], triDepth));
                stream.RestartStrip();

                // Center: m01, m12, m20
                stream.Append(PSX_ProcessVert(m01, triDepth));
                stream.Append(PSX_ProcessVert(m12, triDepth));
                stream.Append(PSX_ProcessVert(m20, triDepth));
                stream.RestartStrip();

                #else
                // ── Standard path (no subdivision) ───────────────────────────
                g2f o[3];
                for (int i = 0; i < 3; i++)
                {
                    o[i].lightColor  = half4(PSX_ShadeVertex(IN[i].worldPos, IN[i].worldNormal), 1.0f);
                    o[i].affineUV    = PSX_AffineUV(IN[i].viewPos, TRANSFORM_TEX(IN[i].uv, _MainTex));
                    o[i].affineUV2   = PSX_AffineUV(IN[i].viewPos, TRANSFORM_TEX(IN[i].uv, _EmissiveTex));
                    o[i].reflDir     = IN[i].reflDir;
                    o[i].customDepth = triDepth;
                    o[i].worldPos    = IN[i].worldPos;
                    o[i].worldNormal = IN[i].worldNormal;
                }

                // ── Flat shading: override per-vertex light with triangle light ──
                #ifdef PSX_FLAT_SHADING_MODE_CENTER
                {
                    float3 wCenter = (IN[0].worldPos + IN[1].worldPos + IN[2].worldPos) * 0.3333f;
                    float3 wNormal = normalize(cross(
                        IN[1].worldPos - IN[0].worldPos,
                        IN[0].worldPos - IN[2].worldPos
                    ));
                    half3 faceLight = PSX_ShadeVertex(wCenter, wNormal);
                    o[0].lightColor = o[1].lightColor = o[2].lightColor = half4(faceLight, 1.0f);
                }
                #else
                if (_FlatShading > 0.5f)
                {
                    half3 avg = (o[0].lightColor.rgb + o[1].lightColor.rgb + o[2].lightColor.rgb) * 0.3333f;
                    o[0].lightColor = o[1].lightColor = o[2].lightColor = half4(avg, 1.0f);
                }
                #endif

                float snapGrid = (_VertexSnapping < 0.5f) ? 0.0f :
                                 ((_VertexSnapResolution > 0.0001f) ? _VertexSnapResolution : _PSX_GridSize);
                for (int i = 0; i < 3; i++)
                {
                    float4 clip    = mul(UNITY_MATRIX_P, IN[i].viewPos);
                    o[i].vertex    = PSX_SnapClip(clip, snapGrid);
                    o[i].fogFactor = ComputeFogFactor(clip.z);
                    stream.Append(o[i]);
                }
                stream.RestartStrip();
                #endif
            }

            // ─────────────────────────────────────────────────────────────────
            // Fragment Shader
            // Handles: affine texture sampling, lighting multiply, emission,
            //          cubemap reflection, color quantization + dithering, fog.
            // ─────────────────────────────────────────────────────────────────
            #ifndef PSX_TRIANGLE_SORT_OFF
            fragOut frag(g2f i)
            #else
            half4 frag(g2f i) : SV_Target
            #endif
            {
                fragOut o;

                // SV_POSITION in pixel shader gives screen-space pixel coords in .xy
                // Divide by _DitherScale so each Bayer cell covers N screen pixels,
                // matching the visual size you'd get at a lower render resolution.
                // e.g. at 820x640 with _DitherScale=4, dither behaves as if at 205x160.
                int2 pixelPos = (int2)(i.vertex.xy / max(1.0f, _DitherScale));

                // ── Affine (perspective-incorrect) texture sample ─────────────
                float2 affineST  = i.affineUV.xy  / i.affineUV.z;
                float2 affineST2 = i.affineUV2.xy / i.affineUV2.z;

                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, affineST) * _Color;

                // ── Alpha cutout ──────────────────────────────────────────────
                #ifdef _ALPHA_TEST
                clip(col.a - _Cutoff);
                #endif

                // ── Lighting ─────────────────────────────────────────────────
                half3 totalLight = i.lightColor.rgb;
                #ifdef _PER_PIXEL_LIGHTS
                totalLight += PSX_ShadeAdditionalLights(i.worldPos, i.worldNormal);
                #endif
                col.rgb *= totalLight;

                // ── Interaction highlight ─────────────────────────────────────
                // _IsLit = 0 when LookSpecularHighlighter is looking at this object.
                // Additively overlays _HighlightColor on top of normal shading —
                // works regardless of texture, emission, or lighting state.
                if (_IsLit < 0.5f)
                    col.rgb += _HighlightColor.rgb * _HighlightColor.a;

                // ── Emission ─────────────────────────────────────────────────
                half4 emissive = SAMPLE_TEXTURE2D(_EmissiveTex, sampler_EmissiveTex, affineST2);
                col.rgb += emissive.rgb * _EmissionColor.rgb * _EmissionColor.a;

                // ── Cubemap env reflection (PS1-style environment mapping) ────
                half reflMask = SAMPLE_TEXTURE2D(_ReflectionMap, sampler_ReflectionMap, affineST).r;
                col.rgb += SAMPLE_TEXTURECUBE(_Cubemap, sampler_Cubemap, i.reflDir).rgb
                         * _CubemapColor.rgb * _CubemapColor.a * reflMask;

                // ── PSX color quantization + ordered dithering ────────────────
                // _PSX_ObjectDithering is set by PSXPostProcessEffect (PerObject_Accurate mode = 1).
                // _ObjectDithering is the per-material on/off toggle.
                // Both must be > 0.5 to dither, matching original PSX shader kit behaviour.
                if (_PSX_ObjectDithering * _ObjectDithering > 0.5f)
                    col = PSX_Quantize(col, pixelPos, _ColorBits, _DitherStrength);

                // ── Proximity dither fade ─────────────────────────────────────
                // When the fragment is closer than _ProximityFadeStart, use the
                // Bayer pattern to progressively clip pixels — giving a retro
                // dithered dissolve instead of a hard near-clip pop.
                #ifdef _PROXIMITY_FADE
                {
                    float camDist = length(i.worldPos - _WorldSpaceCameraPos);
                    float fadeRange = max(_ProximityFadeStart - _ProximityFadeEnd, 0.0001f);
                    float fadeT = 1.0f - saturate((camDist - _ProximityFadeEnd) / fadeRange);
                    // fadeT: 0 = fully visible, 1 = fully clipped
                    if (fadeT > 0.0f)
                    {
                        // 4x4 Bayer threshold in [0,1]. Pixel is clipped when fadeT exceeds threshold.
                        float threshold = (PSX_BayerOffset(pixelPos) + 0.5f) / 16.0f;
                        clip(threshold - fadeT);
                    }
                }
                #endif

                // ── Fog ───────────────────────────────────────────────────────
                // PSX fog: short linear ramp from _PSX_FogStart to _PSX_FogEnd,
                // fades into a solid color (like PS1 draw distance cutoff).
                // Falls back to Unity scene fog when PSX fog is disabled.
                if (_PSX_FogEnabled > 0.5f)
                {
                    float dist = length(i.worldPos - _WorldSpaceCameraPos);
                    float fogT = saturate((dist - _PSX_FogStart) / max(_PSX_FogEnd - _PSX_FogStart, 0.001f));
                    if (_PSX_FogSteps >= 1.0f)
                        fogT = floor(fogT * _PSX_FogSteps + 0.5f) / _PSX_FogSteps;
                    col.rgb = lerp(col.rgb, _PSX_FogColor.rgb, fogT);
                }
                else
                {
                    col.rgb = MixFog(col.rgb, i.fogFactor);
                }

                // ── Film grain + dithered noise (from PSXShaderManager) ──────
                if (_PSX_GrainStrength > 0.0001f || _PSX_NoiseStrength > 0.0001f)
                {
                    int2 grainPx = (int2)(i.vertex.xy / max(1.0f, _PSX_GrainSize));

                    // Film grain — random per pixel per frame
                    float2 grainSeed = float2(grainPx) + _PSX_NoiseTime * 7.391f;
                    float2 p = frac(grainSeed * float2(443.897f, 441.423f));
                    p += dot(p, p.yx + 19.19f);
                    float grain = frac((p.x + p.y) * p.x);
                    grain = (grain - 0.5f) * 2.0f; // remap [-1, 1]
                    col.rgb += grain * _PSX_GrainStrength;

                    // Dithered noise — extra Bayer quantization pass
                    if (_PSX_NoiseStrength > 0.0001f)
                    {
                        float noiseBits  = lerp(8.0f, 3.0f, _PSX_NoiseStrength);
                        float noiseLevels = round(pow(2.0f, noiseBits)) - 1.0f;
                        float noiseThresh = (PSX_BayerOffset(grainPx) + 0.5f) / 8.0f;
                        float4 ns = saturate(col) * noiseLevels;
                        float4 nlo = floor(ns);
                        col.rgb = clamp(nlo.rgb + step(noiseThresh, (ns - nlo).rgb), 0.0f, noiseLevels) / noiseLevels;
                    }
                }

                // ── Depth debug visualization (from PSXShaderManager) ─────────
                #if UNITY_COLORSPACE_GAMMA
                col.rgb = lerp(col.rgb, pow(i.customDepth, 1.0f / 2.2f).xxx, _PSX_DepthDebug);
                #else
                col.rgb = lerp(col.rgb, i.customDepth.xxx, _PSX_DepthDebug);
                #endif

                #ifdef _TRANSPARENT
                col.a *= _Alpha;
                #endif

                o.color = col;

                #ifndef PSX_TRIANGLE_SORT_OFF
                o.depth = i.customDepth;
                return o;
                #else
                return o.color;
                #endif
            }

            ENDHLSL
        }

        // ─────────────────────────────────────────────────────────────────────
        // Shadow Caster Pass (required for URP to cast shadows)
        // ─────────────────────────────────────────────────────────────────────
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex   ShadowVert
            #pragma fragment ShadowFrag

            #pragma shader_feature_local _ALPHA_TEST

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _EmissiveTex_ST;
                half4  _Color;
                half4  _EmissionColor;
                half4  _CubemapColor;
                half4  _PSXSpecColor;
                float  _PSXShininess;
                half   _ObjectDithering;
                float  _ColorBits;
                half   _DitherStrength;
                float  _DitherScale;
                half   _FlatShading;
                float  _CustomDepthOffset;
                float  _VertexSnapping;
                float  _VertexSnapResolution;
                float  _LightQuantization;
                float  _IsLit;
                half4  _HighlightColor;
                float  _Alpha;
                float  _Cutoff;
                float  _SrcBlend;
                float  _DstBlend;
                float  _ZWrite;
            CBUFFER_END

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            float3 _LightDirection;

            struct shadow_v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv     : TEXCOORD0;
            };

            shadow_v2f ShadowVert(float4 vertex : POSITION, float3 normal : NORMAL, float2 uv : TEXCOORD0)
            {
                shadow_v2f o;
                float3 worldPos    = TransformObjectToWorld(vertex.xyz);
                float3 worldNormal = TransformObjectToWorldNormal(normal);
                worldPos = ApplyShadowBias(worldPos, worldNormal, _LightDirection);
                float4 clip = TransformWorldToHClip(worldPos);
                #if UNITY_REVERSED_Z
                clip.z = min(clip.z, UNITY_NEAR_CLIP_VALUE * clip.w);
                #else
                clip.z = max(clip.z, UNITY_NEAR_CLIP_VALUE * clip.w);
                #endif
                o.vertex = clip;
                o.uv     = TRANSFORM_TEX(uv, _MainTex);
                return o;
            }

            half4 ShadowFrag(shadow_v2f i) : SV_Target
            {
                #ifdef _ALPHA_TEST
                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a * _Color.a;
                clip(alpha - _Cutoff);
                #endif
                return 0;
            }
            ENDHLSL
        }

        // ─────────────────────────────────────────────────────────────────────
        // Depth Only Pass (needed for depth prepass, SSAO, DoF in URP)
        // IMPORTANT: Must use the same two-stage MV→P matrix path + snapping as
        // ForwardLit. A single TransformObjectToHClip produces clip positions that
        // differ by ~1 ULP from the split mul(P, mul(MV, v)) path, causing depth
        // test failures at edges and vertex seams in the main forward pass.
        // ─────────────────────────────────────────────────────────────────────
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex   DepthVert
            #pragma geometry DepthGeom
            #pragma fragment DepthFrag

            #pragma multi_compile PSX_TRIANGLE_SORT_OFF \
                                  PSX_TRIANGLE_SORT_CENTER_Z \
                                  PSX_TRIANGLE_SORT_CLOSEST_Z \
                                  PSX_TRIANGLE_SORT_CENTER_VIEWDIST \
                                  PSX_TRIANGLE_SORT_CLOSEST_VIEWDIST

            #pragma shader_feature_local _ALPHA_TEST

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _EmissiveTex_ST;
                half4  _Color;
                half4  _EmissionColor;
                half4  _CubemapColor;
                half4  _PSXSpecColor;
                float  _PSXShininess;
                half   _ObjectDithering;
                float  _ColorBits;
                half   _DitherStrength;
                float  _DitherScale;
                half   _FlatShading;
                float  _CustomDepthOffset;
                float  _VertexSnapping;
                float  _VertexSnapResolution;
                float  _LightQuantization;
                float  _IsLit;
                half4  _HighlightColor;
                float  _Alpha;
                float  _Cutoff;
                float  _SrcBlend;
                float  _DstBlend;
                float  _ZWrite;
            CBUFFER_END

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            float _PSX_GridSize;
            float _PSX_VertexWobbleMode;

            struct depth_v2g { float4 viewPos : TEXCOORD0; float2 uv : TEXCOORD1; };
            struct depth_g2f { float4 vertex  : SV_POSITION; float2 uv : TEXCOORD0; };

            depth_v2g DepthVert(float4 vertex : POSITION, float2 uv : TEXCOORD0)
            {
                depth_v2g o;
                float3 worldPos = TransformObjectToWorld(vertex.xyz);
                o.viewPos = mul(UNITY_MATRIX_V, float4(worldPos, 1.0));
                o.uv = TRANSFORM_TEX(uv, _MainTex);
                // Snapping is done in NDC space in DepthGeom to match ForwardLit exactly.
                return o;
            }

            [maxvertexcount(3)]
            void DepthGeom(triangle depth_v2g IN[3], inout TriangleStream<depth_g2f> stream)
            {
                float snapGrid = (_VertexSnapping < 0.5f) ? 0.0f :
                                 ((_VertexSnapResolution > 0.0001f) ? _VertexSnapResolution : _PSX_GridSize);
                for (int i = 0; i < 3; i++)
                {
                    depth_g2f o;
                    float4 clipPos = mul(UNITY_MATRIX_P, IN[i].viewPos);
                    if (snapGrid >= 0.00001f)
                    {
                        float2 ndc = clipPos.xy / clipPos.w;
                        ndc = floor(ndc * snapGrid + 0.5f) / snapGrid;
                        clipPos.xy = ndc * clipPos.w;
                    }
                    o.vertex = clipPos;
                    o.uv     = IN[i].uv;
                    stream.Append(o);
                }
                stream.RestartStrip();
            }

            half DepthFrag(depth_g2f i) : SV_Target
            {
                #ifdef _ALPHA_TEST
                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a * _Color.a;
                clip(alpha - _Cutoff);
                #endif
                return 0;
            }
            ENDHLSL
        }
    }

    Fallback "PSX/Vertex Lit"
}
