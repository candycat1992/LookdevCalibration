
using System.IO;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.PostProcessing;

public class GenerateCutomLUT : MonoBehaviour
{
    public Texture2D m_InputLUT = null;
    public ComputeShader m_GenerateShader = null;
    public string outputName = "custom_lut";
    
    public void Generate()
    {
        if (!m_InputLUT || !m_GenerateShader) return;

        PostProcessVolume volume = gameObject.GetComponent<PostProcessVolume>();
        if (!volume) return;

        CustomTonemap tonemapLayer = null;
        volume.profile.TryGetSettings(out tonemapLayer);

        if (!tonemapLayer) return;

        // Get tonemapping parameters
        float exposure = tonemapLayer.exposure.value;
        float saturation = tonemapLayer.saturation.value;
        float contrast = tonemapLayer.contrast.value;

        // Create output render texture
        int width = m_InputLUT.width;
        int height = m_InputLUT.height;
        RenderTexture colorLut = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        colorLut.enableRandomWrite = true;
        colorLut.Create();

        // Use compute shader to generate lut
        int kernel = m_GenerateShader.FindKernel("CSMain");
        
        m_GenerateShader.SetFloat("_Exposure", exposure);
        m_GenerateShader.SetFloat("_Saturation", saturation);
        m_GenerateShader.SetFloat("_Contrast", contrast);
        m_GenerateShader.SetTexture(kernel, "_InputTex", m_InputLUT);
        m_GenerateShader.SetTexture(kernel, "_OutputTex", colorLut);

        m_GenerateShader.Dispatch(kernel, width / 8, height / 8, 1);

        // Save lut to exr file
        Texture2D outputTex = new Texture2D(width, height, TextureFormat.RGBAFloat, false);

        RenderTexture currentActive = RenderTexture.active;
        RenderTexture.active = colorLut;
        outputTex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        outputTex.Apply();
        RenderTexture.active = currentActive;

        // Encode texture into the EXR
        byte[] bytes = outputTex.EncodeToEXR(Texture2D.EXRFlags.CompressZIP);
        string outputPath = Application.dataPath + "/ColorLut/" + outputName + ".exr";
        File.WriteAllBytes(outputPath, bytes);
        Debug.Log("Saved color lut to " + outputPath);

        // Release resources
        colorLut.Release();
        Object.DestroyImmediate(colorLut);
        Object.DestroyImmediate(outputTex);
    }
}
