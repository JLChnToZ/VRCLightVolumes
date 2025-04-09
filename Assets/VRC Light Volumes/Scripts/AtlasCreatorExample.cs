using UnityEngine;
using UnityEditor;
using UnityEngine.Rendering;
using System.Collections.Generic;
using System.IO;

public class AtlasCreatorExample : MonoBehaviour {

    public BakeryVolume[] BakeryVolumes;
    public float[] BakeryVolumesWeights;

    public int stochasticIterations = 5000;

    [SerializeField] private Texture3D generatedAtlas;
    [SerializeField] private Vector3[] boundsMin;
    [SerializeField] private Vector3[] boundsMax;
    [SerializeField] private Texture3DAtlasGenerator.Atlas3D Atlas;
    [SerializeField] private Vector3[] boundsWMin;
    [SerializeField] private Vector3[] boundsWMax;

    [ContextMenu("Generate 3D Atlas")]
    private void GenerateAtlas() {

        Texture3D[] Textures = new Texture3D[BakeryVolumes.Length * 3];

        for (int i = 0; i < BakeryVolumes.Length; i ++) {
            if(BakeryVolumes[i].bakedTexture0 == null || BakeryVolumes[i].bakedTexture1 == null || BakeryVolumes[i].bakedTexture2 == null) {
                Debug.LogError("One of the bakery volumes is not baked!");
                return;
            }
            Textures[i * 3]     = BakeryVolumes[i].bakedTexture0;
            Textures[i * 3 + 1] = BakeryVolumes[i].bakedTexture1;
            Textures[i * 3 + 2] = BakeryVolumes[i].bakedTexture2;
        }

        Atlas = Texture3DAtlasGenerator.CreateAtlasStochastic(Textures, stochasticIterations);
        generatedAtlas = Atlas.Texture;

        boundsMin = Atlas.BoundsUvwMin;
        boundsMax = Atlas.BoundsUvwMax;

        boundsWMin = new Vector3[BakeryVolumes.Length];
        boundsWMax = new Vector3[BakeryVolumes.Length];

        for (int i = 0; i < BakeryVolumes.Length; i++) {
            boundsWMin[i] = BakeryVolumes[i].bounds.min;
            boundsWMax[i] = BakeryVolumes[i].bounds.max;
        }

        SaveTexture3DAsAsset(generatedAtlas, "Atlas3D.asset", true);


    }

    [ContextMenu("SetSaderVars")]
    private void SetVars() {
        SetShaderVariables(BakeryVolumes);
    }

    private void Update() {
        if (Atlas.Texture != null && BakeryVolumes != null && BakeryVolumes.Length != 0)
        SetShaderVariables(BakeryVolumes);
    }

    private void SetShaderVariables(BakeryVolume[] volumes) {

        Shader.SetKeyword(GlobalKeyword.Create("LightVolumesEnabled"), true);

        float[] LightVolumeWeight = new float[256];
        Vector4[] LightVolumeWorldMin = new Vector4[256];
        Vector4[] LightVolumeWorldMax = new Vector4[256];
        Vector4[] LightVolumeUvwMin = new Vector4[768];
        Vector4[] LightVolumeUvwMax = new Vector4[768];

        for (int i = 0; i < volumes.Length; i++) {

            // Weight
            LightVolumeWeight[i] = BakeryVolumesWeights.Length > 0 ? BakeryVolumesWeights[Mathf.Clamp(i, 0, BakeryVolumesWeights.Length)] : 0;
            
            // World bounds
            LightVolumeWorldMin[i] = boundsWMin[i];
            LightVolumeWorldMax[i] = boundsWMax[i];

            // UVW bounds
            LightVolumeUvwMin[i * 3] = boundsMin[i * 3];
            LightVolumeUvwMax[i * 3] = boundsMax[i * 3];
            LightVolumeUvwMin[i * 3 + 1] = boundsMin[i * 3 + 1];
            LightVolumeUvwMax[i * 3 + 1] = boundsMax[i * 3 + 1];
            LightVolumeUvwMin[i * 3 + 2] = boundsMin[i * 3 + 2];
            LightVolumeUvwMax[i * 3 + 2] = boundsMax[i * 3 + 2];

        }

        Shader.SetGlobalFloat("_UdonLightVolumeCount", volumes.Length);
        Shader.SetGlobalTexture("_UdonLightVolume", generatedAtlas);

        Shader.SetGlobalFloatArray("_UdonLightVolumeWeight", LightVolumeWeight);
        Shader.SetGlobalVectorArray("_UdonLightVolumeWorldMin", LightVolumeWorldMin);
        Shader.SetGlobalVectorArray("_UdonLightVolumeWorldMax", LightVolumeWorldMax);

        Shader.SetGlobalVectorArray("_UdonLightVolumeUvwMin", LightVolumeUvwMin);
        Shader.SetGlobalVectorArray("_UdonLightVolumeUvwMax", LightVolumeUvwMax);

    }

    public static bool SaveTexture3DAsAsset(Texture3D textureToSave, string assetPath, bool overwriteExisting = false) {
        if (textureToSave == null) {
            Debug.LogError("������ ���������� Texture3D: ���������� �������� ����� null.");
            return false;
        }

        if (string.IsNullOrEmpty(assetPath)) {
            Debug.LogError("������ ���������� Texture3D: ���� ��� ���������� �� ����� ���� ������.");
            return false;
        }

        // 1. ������������ ���� � �������� �������� "Assets/"
        string normalizedPath = assetPath.Replace("\\", "/");
        if (!normalizedPath.StartsWith("Assets/", System.StringComparison.OrdinalIgnoreCase)) {
            // ���� ���� �� ���������� � Assets/, �������� �������� ���.
            // �������, ��� ������������ ������ ���� ������ Assets.
            if (normalizedPath.StartsWith("/")) // ������� ������� ����, ���� �� ����
            {
                normalizedPath = normalizedPath.Substring(1);
            }
            normalizedPath = "Assets/" + normalizedPath;
            Debug.LogWarning($"���� '{assetPath}' �� ��������� � 'Assets/'. ������������ ���� '{normalizedPath}'.");
        }


        // 2. �������� � ���������� ���������� .asset
        string extension = Path.GetExtension(normalizedPath);
        if (string.IsNullOrEmpty(extension)) {
            // ���������� �����������, ��������� .asset
            normalizedPath += ".asset";
            Debug.Log($"��������� ���������� '.asset'. �������� ����: '{normalizedPath}'.");
        } else if (!extension.Equals(".asset", System.StringComparison.OrdinalIgnoreCase)) {
            // ������� ������ ����������, ��� ����� ���� �������
            Debug.LogWarning($"���� '{assetPath}' ����� ���������� '{extension}', � �� '.asset'. ���������� Texture3D ������ ����������� � .asset ����.");
            // ��� �� �����, ��������� ��������� � ��������� �����������, ���� ������������ ��� �����.
        }


        // 3. �������� ����������, ���� ��� �� ����������
        try {
            string directoryPath = Path.GetDirectoryName(normalizedPath);
            if (!string.IsNullOrEmpty(directoryPath) && !Directory.Exists(directoryPath)) {
                Directory.CreateDirectory(directoryPath);
                Debug.Log($"������� ����������: '{directoryPath}'");
                // ����� �������� ���� ������ ������� ����� �������� ����������,
                // ����� Unity �� "������" ����� ��������� ������ ������ ���.
                AssetDatabase.Refresh();
            }
        } catch (System.Exception e) {
            Debug.LogError($"������ ��� �������� ���������� ��� '{normalizedPath}': {e.Message}");
            return false;
        }

        // 4. ��������� ������������� ����� / ��������� ����������� ����
        string finalPath = normalizedPath;
        if (!overwriteExisting && File.Exists(finalPath)) // ���������� File.Exists ��� ��������, �.�. AssetDatabase ����� �� ����� ����������
        {
            finalPath = AssetDatabase.GenerateUniqueAssetPath(normalizedPath);
            Debug.Log($"���� '{normalizedPath}' ��� ����������. ������������ ���������� ����: '{finalPath}'.");
        } else if (overwriteExisting && File.Exists(finalPath)) {
            Debug.LogWarning($"���������� ������������� �����: '{finalPath}'.");
        }


        // 5. �������� ������
        try {
            // ������� ����� � ���� ������ Unity
            AssetDatabase.CreateAsset(textureToSave, finalPath);

            // �����������, �� �������������: �������� ����� ��� "�������", ����� ��������� ����� �����������
            EditorUtility.SetDirty(textureToSave);

            // ��������� ��������� � ���� ������ �������
            AssetDatabase.SaveAssets();

            // �����������: �������� ���� �������, ����� �������� ����� ����
            AssetDatabase.Refresh();

            // �����������: �������� ��������� ����� � ���� �������
            // EditorGUIUtility.PingObject(textureToSave);

            Debug.Log($"Texture3D ������� ��������� ��� ����� �� ����: '{finalPath}'");
            return true;
        } catch (System.Exception e) {
            Debug.LogError($"������ ��� �������� ��� ���������� ������ Texture3D �� ���� '{finalPath}': {e.Message}");
            return false;
        }
    }

}