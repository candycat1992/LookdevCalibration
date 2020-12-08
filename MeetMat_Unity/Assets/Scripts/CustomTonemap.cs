using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

[Serializable]
[PostProcess(typeof(CustomTonemapRenderer), PostProcessEvent.AfterStack, "Lookdev/Tonemap")]
public sealed class CustomTonemap : PostProcessEffectSettings
{
    [Range(-2f, 2f)]
    public FloatParameter exposure = new FloatParameter { value = 0.0f };
    [Range(0f, 2f)]
    public FloatParameter saturation = new FloatParameter { value = 1.0f };
    [Range(0f, 2f)]
    public FloatParameter contrast = new FloatParameter { value = 1.0f };
}

public sealed class CustomTonemapRenderer : PostProcessEffectRenderer<CustomTonemap>
{
    public override void Render(PostProcessRenderContext context)
    {
        var sheet = context.propertySheets.Get(Shader.Find("Hidden/Lookdev/Tonemap"));
        sheet.properties.SetFloat("_Exposure", settings.exposure);
        sheet.properties.SetFloat("_Saturation", settings.saturation);
        sheet.properties.SetFloat("_Contrast", settings.contrast);
        context.command.BlitFullscreenTriangle(context.source, context.destination, sheet, 0);
    }
}