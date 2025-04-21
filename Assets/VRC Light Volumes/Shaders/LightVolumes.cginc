
// Are Light Volumes enabled on scene?
uniform float _UdonLightVolumeEnabled;

// All volumes count in scene
uniform float _UdonLightVolumeCount;

// How volumes edge blending
uniform float _UdonLightVolumeBlend;

// Should volumes be blended with lightprobes?
uniform float _UdonLightVolumeProbesBlend;

// Should volumes be blended with lightprobes?
uniform float _UdonLightVolumeSharpBounds;

// Main 3D Texture atlas
uniform sampler3D _UdonLightVolume;

// Rotation types: 0 - Fixed, 1 - Y Axis, 2 - Free
uniform float _UdonLightVolumeRotationType[256];

// Fixed rotation:   A - WorldMin             B - WorldMax
// Y Axis rotation:  A - BoundsCenter | SinY  B - InvBoundsSize | CosY
// Free rotation:    A - 0                    B - InvBoundsSize
uniform float4 _UdonLightVolumeDataA[256];
uniform float4 _UdonLightVolumeDataB[256];

// Used with free rotation, World to Local (-0.5, 0.5) UVW Matrix
uniform float4x4 _UdonLightVolumeInvWorldMatrix[256];

// AABB Bounds of islands on the 3D Texture atlas
uniform float4 _UdonLightVolumeUvwMin[768];
uniform float4 _UdonLightVolumeUvwMax[768];


// AABB intersection check
bool LV_PointAABB(float3 pos, float3 min, float3 max) {
	return all(pos >= min && pos <= max);
}

// Checks if local UVW point is in bounds from -0.5 to +0.5
bool LV_PointLocalAABB(float3 localUVW){
    return all(abs(localUVW) <= 0.5);
}

// Calculates Island UVW for Fixed Rotation Mode
float3 LV_IslandFromFixedVolume(int volumeID, int texID, float3 worldPos){
    // World bounds
    float3 worldMin = _UdonLightVolumeDataA[volumeID].xyz;
    float3 worldMax = _UdonLightVolumeDataB[volumeID].xyz;
    // UVW bounds
    int uvwID = volumeID * 3 + texID;
    float3 uvwMin = _UdonLightVolumeUvwMin[uvwID].xyz;
    float3 uvwMax = _UdonLightVolumeUvwMax[uvwID].xyz;
    // Ramapping world bounds to UVW bounds
    return clamp(uvwMin + (worldPos - worldMin) * (uvwMax - uvwMin) / (worldMax - worldMin), uvwMin, uvwMax);
}

// Calculates local UVW for Y Axis rotation mode
float3 LV_LocalFromYAxisVolume(int volumeID, float3 worldPos){
    // Bounds and rotation data
    float3 invBoundsSize = _UdonLightVolumeDataB[volumeID].xyz;
    float3 boundsCenter = _UdonLightVolumeDataA[volumeID].xyz;
    float sinY = _UdonLightVolumeDataA[volumeID].w;
    float cosY = _UdonLightVolumeDataB[volumeID].w;
    // Ramapping world bounds to UVW bounds
    float3 p = worldPos - boundsCenter;
    float localX = p.x * cosY - p.z * sinY;
    float localZ = p.x * sinY + p.z * cosY;
    float localY = p.y;
    return float3(localX, localY, localZ) * invBoundsSize;
}

// Calculates local UVW for Free rotation mode
float3 LV_LocalFromFreeVolume(int volumeID, float3 worldPos) {
    return mul(_UdonLightVolumeInvWorldMatrix[volumeID], float4(worldPos, 1.0)).xyz;
}

// Calculates Island UVW from local UVW
float3 LV_LocalToIsland(int volumeID, int texID, float3 localUVW){
    // UVW bounds
    int uvwID = volumeID * 3 + texID;
    float3 uvwMin = _UdonLightVolumeUvwMin[uvwID].xyz;
    float3 uvwMax = _UdonLightVolumeUvwMax[uvwID].xyz;
    // Ramapping world bounds to UVW bounds
    return clamp(lerp(uvwMin, uvwMax, localUVW + 0.5), uvwMin, uvwMax);
}

// Samples 3 SH textures and packing them into L1 channels
void LV_SampleLightVolumeTex(float3 uvw0, float3 uvw1, float3 uvw2, out float3 L0, out float3 L1r, out float3 L1g, out float3 L1b) {
    // Sampling 3D Atlas
    float4 tex0 = tex3D(_UdonLightVolume, uvw0);
    float4 tex1 = tex3D(_UdonLightVolume, uvw1);
    float4 tex2 = tex3D(_UdonLightVolume, uvw2);
    // Packing final data
    L0 = tex0.rgb;
    L1r = float3(tex1.r, tex2.r, tex0.a);
    L1g = float3(tex1.g, tex2.g, tex1.a);
    L1b = float3(tex1.b, tex2.b, tex2.a);
}

// Faster than smoothstep
float LV_FastSmooth(float x) {
	return x * x * (3.0 - 2.0 * x);
}

// Corrects exposure, shadows, mids and highlights
float3 LV_SimpleColorCorrection(float3 color, float exposure, float shadowGain, float midGain, float highlightGain) {
	color *= exposure;
	float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    float shadowMask = LV_FastSmooth(saturate((0.4 - luma) * 2.5)); // 0.4 and 0.6 are for smoother tones overlap
    float highlightMask = LV_FastSmooth(saturate((luma - 0.6) * 2.5)); // 2.5f is actually 1/0.4
	float midMask = 1.0 - shadowMask - highlightMask;
	float gain = shadowMask * shadowGain + midMask * midGain + highlightMask * highlightGain;
	return color * gain;
}

// Bounds mask
float LV_BoundsMask(float3 pos, float3 minBounds, float3 maxBounds, float edgeSmooth) {
    float3 distToMin = (pos - minBounds) / edgeSmooth;
    float3 distToMax = (maxBounds - pos) / edgeSmooth;
    float3 fade = saturate(min(distToMin, distToMax));
    return fade.x * fade.y * fade.z;
}

// Bounds mask, but for rotated in world space, using local UVW
float LV_BoundsMaskOBB(float3 localUVW, float3 edgeSmooth, float3 invBoundsScale) {
    float3 edgeSmoothLocal = edgeSmooth * invBoundsScale;
    float3 distToMin = (localUVW + 0.5) / edgeSmoothLocal;
    float3 distToMax = (0.5 - localUVW) / edgeSmoothLocal;
    float3 fade = saturate(min(distToMin, distToMax));
    return fade.x * fade.y * fade.z;
}

// Default light probes SH components
void LV_SampleLightProbe(out float3 L0, out float3 L1r, out float3 L1g, out float3 L1b) {
    L0 = float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
    L1r = unity_SHAr.xyz;
    L1g = unity_SHAg.xyz;
    L1b = unity_SHAb.xyz;
}

// Linear single SH L1 channel evaluation
float LV_EvaluateSH(float L0, float3 L1, float3 n) {
    return L0 + dot(L1, n);
}

// Calculate Light Volume Color based on all SH components provided
float3 LightVolumeEvaluate(float3 worldNormal, float3 L0, float3 L1r, float3 L1g, float3 L1b) {
    return float3(LV_EvaluateSH(L0.r, L1r, worldNormal), LV_EvaluateSH(L0.g, L1g, worldNormal), LV_EvaluateSH(L0.b, L1b, worldNormal));
}

// Calculates SH components based on world position and world normal
void LightVolumeSH(float3 worldPos, out float3 L0, out float3 L1r, out float3 L1g, out float3 L1b) {

    // Fallback to default light probes if Light Volume are not enabled
    if (!_UdonLightVolumeEnabled || _UdonLightVolumeCount == 0) {
        LV_SampleLightProbe(L0, L1r, L1g, L1b);
        return;
    }
    
    int volumeID_A = -1; // Main, dominant volume ID
    int volumeID_B = -1; // Secondary volume ID to blend main with
    
    int rotType = 0; // Last Rot Type
    int rotType_A = 0; // Main Rot Type
    int rotType_B = 0; // Secondary Rot Type
    
    float3 localUVW; // Last local UVW to use in disabled Light Probes mode
    float3 localUVW_A; // Main local UVW for Y Axis and Free roattions
    float3 localUVW_B; // Secondary local UVW
    
    // Are A and B volumes NOT found?
    bool isNoA = true;
    bool isNoB = true;
    
    // Iterating through all light volumes with simplified algorithm requiring Light Volumes to be sorted by weight in descending order
    for (int id = 0; id < _UdonLightVolumeCount; id++) {
        rotType = _UdonLightVolumeRotationType[id];
        if (rotType == 0) { // Fixed Rotation
            // Intersection test
            if (LV_PointAABB(worldPos, _UdonLightVolumeDataA[id].xyz, _UdonLightVolumeDataB[id].xyz)) {
                if (isNoA) { // First, searching for volume A
                    volumeID_A = id;
                    isNoA = false;
                } else { // Next, searching for volume B if A found
                    volumeID_B = id;
                    isNoB = false;
                    break;
                }
            }
        } else { // Not Fixed rotation
            localUVW = rotType == 1 ? LV_LocalFromYAxisVolume(id, worldPos) : LV_LocalFromFreeVolume(id, worldPos);
            //Intersection test
            if (LV_PointLocalAABB(localUVW)) {
                if (isNoA) { // First, searching for volume A
                    volumeID_A = id;
                    localUVW_A = localUVW;
                    rotType_A = rotType;
                    isNoA = false;
                } else { // Next, searching for volume B if A found
                    volumeID_B = id;
                    localUVW_B = localUVW;
                    rotType_B = rotType;
                    isNoB = false;
                    break;
                }
            }
        }
    }
    
    // Volume A SH components, UVWs and mask to blend volume sides
    float3 L0_A, L1r_A, L1g_A, L1b_A, uvw0_A, uvw1_A, uvw2_A;
    float mask;
    
    // If no volumes found, using Fallback
    if (isNoA && _UdonLightVolumeProbesBlend) {
        
        LV_SampleLightProbe(L0, L1r, L1g, L1b); // Sample Lioght Probes as Fallback
        return;
        
    } else {
        
        rotType_A = isNoA ? rotType : rotType_A;
        localUVW_A = isNoA ? localUVW : localUVW_A;
        volumeID_A = isNoA ? _UdonLightVolumeCount - 1 : volumeID_A;
        
        // Volume A UVWs depending on Rotation Type
        if (rotType_A == 0) {
            mask = LV_BoundsMask(worldPos, _UdonLightVolumeDataA[volumeID_A].xyz, _UdonLightVolumeDataB[volumeID_A].xyz, _UdonLightVolumeBlend);
            uvw0_A = LV_IslandFromFixedVolume(volumeID_A, 0, worldPos);
            uvw1_A = LV_IslandFromFixedVolume(volumeID_A, 1, worldPos);
            uvw2_A = LV_IslandFromFixedVolume(volumeID_A, 2, worldPos);
        } else {
            mask = LV_BoundsMaskOBB(localUVW_A, _UdonLightVolumeBlend, _UdonLightVolumeDataB[volumeID_A].xyz);
            uvw0_A = LV_LocalToIsland(volumeID_A, 0, localUVW_A);
            uvw1_A = LV_LocalToIsland(volumeID_A, 1, localUVW_A);
            uvw2_A = LV_LocalToIsland(volumeID_A, 2, localUVW_A);
        }
        
        // Sample Volume A
        LV_SampleLightVolumeTex(uvw0_A, uvw1_A, uvw2_A, L0_A, L1r_A, L1g_A, L1b_A);
        
    }
    
    // Returning SH A result if it's the center of mask or out of bounds
    if (mask == 1 || isNoA || (_UdonLightVolumeSharpBounds && isNoB)) {
        L0 = L0_A;
        L1r = L1r_A;
        L1g = L1g_A;
        L1b = L1b_A;
        return;
    }
    
    // Volume B SH components
    float3 L0_B, L1r_B, L1g_B, L1b_B;

    if (isNoB && _UdonLightVolumeProbesBlend) { // No Volume found and light volumes blending enabled

        // Sample Light Probes B
        LV_SampleLightProbe(L0_B, L1r_B, L1g_B, L1b_B);

    } else { // Blending Volume A and Volume B
            
        // UVW B
        float3 uvw0_B, uvw1_B, uvw2_B;
            
        // If no volume b found, use last one found to fallback
        rotType_B = isNoB ? rotType : rotType_B;
        localUVW_B = isNoB ? localUVW : localUVW_B;
        volumeID_B = isNoB ? _UdonLightVolumeCount - 1 : volumeID_B;
            
        // Volume B UVWs
        if (rotType_B == 0) {
            uvw0_B = LV_IslandFromFixedVolume(volumeID_B, 0, worldPos);
            uvw1_B = LV_IslandFromFixedVolume(volumeID_B, 1, worldPos);
            uvw2_B = LV_IslandFromFixedVolume(volumeID_B, 2, worldPos);
        } else {
            uvw0_B = LV_LocalToIsland(volumeID_B, 0, localUVW_B);
            uvw1_B = LV_LocalToIsland(volumeID_B, 1, localUVW_B);
            uvw2_B = LV_LocalToIsland(volumeID_B, 2, localUVW_B);
        }
        
        // Sample Volume B
        LV_SampleLightVolumeTex(uvw0_B, uvw1_B, uvw2_B, L0_B, L1r_B, L1g_B, L1b_B);
            
    }
        
    // Lerping SH components
    L0 =  lerp(L0_B,  L0_A,  mask);
    L1r = lerp(L1r_B, L1r_A, mask);
    L1g = lerp(L1g_B, L1g_A, mask);
    L1b = lerp(L1b_B, L1b_A, mask);
    return;

}