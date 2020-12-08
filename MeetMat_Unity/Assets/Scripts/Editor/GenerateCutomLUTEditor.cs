using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

[CustomEditor(typeof(GenerateCutomLUT))]
public class GenerateCutomLUTEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();

        GenerateCutomLUT script = (GenerateCutomLUT)target;
        if (GUILayout.Button("Generate"))
        {
            script.Generate();
        }
    }
}
