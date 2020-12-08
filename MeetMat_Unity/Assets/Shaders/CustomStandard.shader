Shader "Lookdev/Standard"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Albedo", 2D) = "white" {}
        [NoScaleOffset] _MetallicMap ("Metallic", 2D) = "white" {}
        [NoScaleOffset] _RoughnessMap ("Roughness", 2D) = "white" {}
        [NoScaleOffset] _BumpMap ("Normal", 2D) = "bump" {}
        [NoScaleOffset] _OcclusionMap ("Occlusion", 2D) = "white" {}
        [NoScaleOffset] _EmissionMap ("Emission", 2D) = "black" {}
        _SpecularLevel ("Specular", Range(0.0, 1.0)) = 0.5
        _BumpScale ("Bump Scale", Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma target 3.0
            #pragma multi_compile_fwdbase

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"
            #include "HLSLSupport.cginc"
            #include "CustomStandardBRDF.cginc"

            sampler2D _MainTex;
            sampler2D _MetallicMap;
            sampler2D _RoughnessMap;
            sampler2D _BumpMap;
            sampler2D _OcclusionMap;
            sampler2D _EmissionMap;
            half _SpecularLevel;
            half _BumpScale;

            half3 _LightColor0;

            struct a2v
            {
                float4 vertex : POSITION;
                float2 texcoord : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 TtoW0 : TEXCOORD1;
                float4 TtoW1 : TEXCOORD2;
                float4 TtoW2 : TEXCOORD3;
                SHADOW_COORDS(4)
            };

            v2f vert (a2v v)
            {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f, o);

                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.texcoord;

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                half3 worldNormal = UnityObjectToWorldNormal(v.normal);
                half3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                half3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;
                o.TtoW0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
                o.TtoW1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
                o.TtoW2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);

                //We need this for shadow receving
                TRANSFER_SHADOW(o);

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                // ------------------------------------------------------------------
                // Prepare all the inputs
                half3 albedo = tex2D(_MainTex, i.uv).rgb;
                half specular = _SpecularLevel;
                half metallic = tex2D(_MetallicMap, i.uv).r;
                half roughness = tex2D(_RoughnessMap, i.uv).r;
                half occlusion = tex2D(_OcclusionMap, i.uv).r;
                half3 emisstion = tex2D(_EmissionMap, i.uv).rgb;

                half3 diffColor = lerp(albedo, 0.0, metallic);
                half3 specColor = ComputeF0(specular, albedo, metallic);
                
                half3 normalTangent = UnpackNormal(tex2D(_BumpMap, i.uv));
                normalTangent.xy *= _BumpScale;
                normalTangent.z = sqrt(1.0 - saturate(dot(normalTangent.xy, normalTangent.xy)));
                half3 normalWorld = normalize(half3(dot(i.TtoW0.xyz, normalTangent), dot(i.TtoW1.xyz, normalTangent), dot(i.TtoW2.xyz, normalTangent)));
                float3 worldPos = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);

                half3 viewDir = normalize(UnityWorldSpaceViewDir(worldPos));
                half3 reflDir = reflect(-viewDir, normalWorld);
                UNITY_LIGHT_ATTENUATION(atten, i, worldPos);

                // ------------------------------------------------------------------
                // Compute Direct lighting
                half3 lightColor = _LightColor0.rgb;
                half3 lightDir = normalize(UnityWorldSpaceLightDir(worldPos));
                half3 halfDir = normalize(lightDir + viewDir);
                half nv = saturate(dot(normalWorld, viewDir));
                half nl = saturate(dot(normalWorld, lightDir));
                half nh = saturate(dot(normalWorld, halfDir));
                half lv = saturate(dot(lightDir, viewDir));
                half lh = saturate(dot(lightDir, halfDir));

                // Diffuse term
                half3 diffuseTerm = DisneyDiffuseTerm(nv, nl, lh, roughness, diffColor);

                // Specular term
                half V = SmithJointGGXVisibilityTerm(nl, nv, roughness);
                half D = GGXTerm(nh, roughness * roughness);
                half3 F = FresnelTerm(specColor, lh);
                half3 specularTerm = F * V * D;

                half3 directLighting = UNITY_PI * (diffuseTerm + specularTerm) * lightColor * nl * atten;

                // ------------------------------------------------------------------
                // Compute indirect lighting
                half3 indirectDiffuse = max(0.0, ShadeSH9(half4(normalWorld, 1.0))) * diffColor * occlusion;

                half specOcclusion = GetSpecularOcclusion(metallic, roughness, occlusion);
                half envMip = ComputeEnvMapMipFromRoughness(roughness);
                half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflDir, envMip);
                half3 envMap = DecodeHDR(rgbm, unity_SpecCube0_HDR);
                half3 indirectSpecular = envMap * specOcclusion * EnvBRDF(specColor, roughness, nv);

                half3 indirectLighting = indirectDiffuse + indirectSpecular;

                // ------------------------------------------------------------------
                // Combine all togather
                half3 col = emisstion + directLighting + indirectLighting;

                return half4(col, 1);
            }
            ENDCG
        }
    }
}
