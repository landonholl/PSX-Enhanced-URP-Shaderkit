Shader "PSX/NoiseOverlay"
{
    Properties
    {
        _MainTex        ("Texture",                     2D)         = "white" {}

        [Header(Film Grain)]
        _GrainStrength  ("Grain Strength",              Range(0,1)) = 0.08
        _GrainSize      ("Grain Size (px)",             Range(1,8)) = 1

        [Header(Dithered Noise)]
        _DitherStrength ("Dither Strength",             Range(0,1)) = 0.04
        _ColorBits      ("Color Bits (5=PSX)",          Range(1,8)) = 5
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Overlay" }
        ZWrite Off
        ZTest Always
        Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv     : TEXCOORD0;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float  _GrainStrength;
                float  _GrainSize;
                float  _DitherStrength;
                float  _ColorBits;
            CBUFFER_END

            // Time injected by script via material property
            float _NoiseTime;

            // ── Pseudo-random hash (high quality, no visible pattern) ──
            float hash(float2 p)
            {
                p = frac(p * float2(443.897f, 441.423f));
                p += dot(p, p.yx + 19.19f);
                return frac((p.x + p.y) * p.x);
            }

            // ── Bayer 4x4 dither matrix ──
            float bayer(int2 px)
            {
                static const float b[16] =
                {
                    0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
                   12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
                    3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
                   15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
                };
                return b[(px.x % 4) + (px.y % 4) * 4];
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                int2 px = (int2)(i.vertex.xy / max(1.0f, _GrainSize));

                // ── Film grain — pure random noise per pixel per frame ──
                float grain = hash(float2(px) + _NoiseTime * 7.391f);
                grain = (grain - 0.5f) * 2.0f; // remap to [-1, 1]
                col.rgb += grain * _GrainStrength;

                // ── Dithered noise — Bayer pattern quantization ──
                float levels   = round(pow(2.0f, _ColorBits)) - 1.0f;
                float threshold = bayer(px);
                float4 scaled   = saturate(col) * levels;
                float4 lo       = floor(scaled);
                float4 frac_v   = scaled - lo;
                col.rgb = clamp(lo.rgb + step(threshold, frac_v.rgb), 0.0f, levels) / levels;

                col.a = 1.0f;
                return col;
            }
            ENDHLSL
        }
    }
}
