// ================================================================================================
// DLSS-NR Proxy Shaders: Area-Weighted Downsample + High-Frequency Matched Residual Resolve
// ================================================================================================

// --- DOWNSAMPLE SHADER ---
cbuffer DownConstants : register(b0)
{
    uint gSrcWidth;
    uint gSrcHeight;
    uint gDstWidth;
    uint gDstHeight;
};

Texture2D<float4>   gDownSource : register(t0);
RWTexture2D<float4> gDownTarget : register(u0);

[numthreads(8, 8, 1)]
void CS_Downsample(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= gDstWidth || id.y >= gDstHeight)
        return;

    const float x0 = ((float) id.x * (float) gSrcWidth) / (float) gDstWidth;
    const float x1 = ((float) (id.x + 1) * (float) gSrcWidth) / (float) gDstWidth;
    const float y0 = ((float) id.y * (float) gSrcHeight) / (float) gDstHeight;
    const float y1 = ((float) (id.y + 1) * (float) gSrcHeight) / (float) gDstHeight;
    const float area = max((x1 - x0) * (y1 - y0), 1e-6);

    const int i0 = (int) floor(x0);
    const int i1 = (int) ceil(x1) - 1;
    const int j0 = (int) floor(y0);
    const int j1 = (int) ceil(y1) - 1;

    float4 acc = float4(0, 0, 0, 0);

    for (int j = j0; j <= j1; ++j)
    {
        const int jj = clamp(j, 0, (int) gSrcHeight - 1);
        const float aY = max(y0, (float) j);
        const float bY = min(y1, (float) j + 1.0);
        const float wy = max(bY - aY, 0.0);

        for (int i = i0; i <= i1; ++i)
        {
            const int ii = clamp(i, 0, (int) gSrcWidth - 1);
            const float aX = max(x0, (float) i);
            const float bX = min(x1, (float) i + 1.0);
            acc += gDownSource.Load(int3(ii, jj, 0)) * (max(bX - aX, 0.0) * wy);
        }
    }

    gDownTarget[id.xy] = acc / area;
}


// --- RESOLVE & RESIDUAL COMPOSITE SHADER ---
cbuffer ResolveConstants : register(b0)
{
    uint  gNativeWidth;
    uint  gNativeHeight;
    uint  gWorkWidth;
    uint  gWorkHeight;
    float gTransferStrength;
    float gSharpness;
    uint  gEnlargementMode;
    uint  gPad0;
};

Texture2D<float4>   gSmallInput    : register(t0); // Downsampled model input (g_colorSmall)
Texture2D<float4>   gSmallOutput   : register(t1); // Model output (g_outputSmall)
Texture2D<float4>   gNativeColor   : register(t2); // Pristine native frame (origColor)
RWTexture2D<float4> gResolveTarget : register(u0); // Destination (origOutput)

SamplerState gLinear : register(s0);

static const float3 kLuma = float3(0.2126, 0.7152, 0.0722);

[numthreads(8, 8, 1)]
void CS_Resolve(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= gNativeWidth || id.y >= gNativeHeight)
        return;

    float2 uv = (float2(id.xy) + 0.5) / float2(gNativeWidth, gNativeHeight);

    // Fallback mode: Classic Bilinear (for comparison/debugging)
    if (gEnlargementMode == 0)
    {
        gResolveTarget[id.xy] = gSmallOutput.SampleLevel(gLinear, uv, 0);
        return;
    }

    // 1. Pristine 1:1 Native Game Pixel (preserves all geometry, subpixel edges, textures, text)
    float4 nativeSample = gNativeColor.Load(int3(id.xy, 0));
    float3 original = nativeSample.rgb;

    // 2. Sample the downsampled input proxy and model output with bilinear interpolation
    float3 smallInput = gSmallInput.SampleLevel(gLinear, uv, 0).rgb;
    float3 smallOutput = gSmallOutput.SampleLevel(gLinear, uv, 0).rgb;

    // 3. Compute neural delta / edit
    float3 edit = smallOutput - smallInput;

    // 4. HDR-Safe Luminance Ratio & Residual Composite
    float origLuma = dot(max(original, 0.0), kLuma);
    float inLuma = dot(max(smallInput, 0.0), kLuma);
    float outLuma = dot(max(smallOutput, 0.0), kLuma);

    // Noise floor (1/512) prevents division-by-zero or noise crawling in near-black pixels
    const float kFloor = 1.0 / 512.0;
    float lumaRatio = (outLuma + kFloor) / (inLuma + kFloor);

    // Scale the neural edit by TransferStrength
    float3 scaledEdit = edit * gTransferStrength;

    // Base native frame + neural delta
    float3 result = original + scaledEdit;
    result = max(result, 0.0);

    // HDR highlight & shadow guard:
    // Ensure the resulting luminance doesn't run away or blow out highlights
    float resLuma = dot(result, kLuma);
    if (resLuma > 1e-5 && inLuma > 1e-5)
    {
        float targetLuma = origLuma * lumaRatio;
        float maxAllowedLuma = max(origLuma * 2.5, targetLuma * 1.5 + 0.1);
        if (resLuma > maxAllowedLuma)
        {
            result *= (maxAllowedLuma / resLuma);
        }
    }

    // 5. Optional RCAS (Robust Contrast Adaptive Sharpening) pass
    if (gSharpness > 0.001)
    {
        int2 coord = int2(id.xy);
        int w = (int)gNativeWidth - 1;
        int h = (int)gNativeHeight - 1;

        float3 cE = gNativeColor.Load(int3(min(coord.x + 1, w), coord.y, 0)).rgb;
        float3 cW = gNativeColor.Load(int3(max(coord.x - 1, 0), coord.y, 0)).rgb;
        float3 cS = gNativeColor.Load(int3(coord.x, min(coord.y + 1, h), 0)).rgb;
        float3 cN = gNativeColor.Load(int3(coord.x, max(coord.y - 1, 0), 0)).rgb;

        float lE = dot(cE, kLuma);
        float lW = dot(cW, kLuma);
        float lS = dot(cS, kLuma);
        float lN = dot(cN, kLuma);
        float lM = origLuma;

        float minL = min(lM, min(min(lE, lW), min(lS, lN)));
        float maxL = max(lM, max(max(lE, lW), max(lS, lN)));

        float range = maxL - minL;
        if (range > 1e-5)
        {
            float weight = saturate(gSharpness) * clamp(-0.2, 0.0, -0.15 * (1.0 - range / (maxL + 1e-4)));
            result = max(result - weight * (cE + cW + cS + cN - 4.0 * original), 0.0);
        }
    }

    gResolveTarget[id.xy] = float4(result, nativeSample.a);
}
