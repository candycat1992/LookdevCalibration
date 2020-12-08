//- Allegorithmic Metal/Rough PBR shader
//- ====================================
//-
//- Import from libraries.
import lib-sss.glsl
import lib-pbr.glsl
import lib-emissive.glsl
import lib-pom.glsl
import lib-utils.glsl

//: param custom { "default": 50, "label": "Light Angle X", "min": -180, "max": 180 }
uniform float light_angle_x;
//: param custom { "default": -30, "label": "Light Angle Y", "min": -180, "max": 180 }
uniform float light_angle_y;
//: param custom { "default": 0, "label": "Light Angle Z", "min": -180, "max": 180 }
uniform float light_angle_z;
//: param custom { "default": 1, "label": "Light Color", "widget": "color" }
uniform vec3 light_color;
//: param custom { "default": 1, "label": "Light Intensity", "min": 0, "max": 10 }
uniform float light_intensity;

//- Channels needed for metal/rough workflow are bound here.
//: param auto channel_basecolor
uniform SamplerSparse basecolor_tex;
//: param auto channel_roughness
uniform SamplerSparse roughness_tex;
//: param auto channel_metallic
uniform SamplerSparse metallic_tex;
//: param auto channel_specularlevel
uniform SamplerSparse specularlevel_tex;

float DielectricSpecularToF0(float specular)
{
	return 0.08 * specular;
}

vec3 ComputeF0(float specular, vec3 baseColor, float metallic)
{
	return mix(vec3(DielectricSpecularToF0(specular)), baseColor, metallic);
}

vec3 DisneyDiffuseTerm(float NdotV, float NdotL, float LdotH, float perceptualRoughness, vec3 baseColor)
{
    float fd90 = 0.5 + 2 * LdotH * LdotH * perceptualRoughness;
    // Two schlick fresnel term
    float lightScatter = (1 + (fd90 - 1) * pow(1 - NdotL, 5));
    float viewScatter = (1 + (fd90 - 1) * pow(1 - NdotV, 5));
    return baseColor / M_PI * lightScatter * viewScatter;
}

float SmithJointGGXVisibilityTerm(float NdotL, float NdotV, float roughness)
{   
    // Original formulation:
    //  lambda_v    = (-1 + sqrt(a2 * (1 - NdotL2) / NdotL2 + 1)) * 0.5f;
    //  lambda_l    = (-1 + sqrt(a2 * (1 - NdotV2) / NdotV2 + 1)) * 0.5f;
    //  G           = 1 / (1 + lambda_v + lambda_l);

    // Reorder code to be more optimal
    float a          = roughness;
    float a2         = a * a;

    float lambdaV    = NdotL * sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
    float lambdaL    = NdotV * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);

    // Simplify visibility term: (2.0f * NdotL * NdotV) /  ((4.0f * NdotL * NdotV) * (lambda_v + lambda_l + 1e-5f));
    return 0.5f / (lambdaV + lambdaL + 1e-5f);
}

float GGXTerm(float NdotH, float roughness)
{
    float a2 = roughness * roughness;
    float d = (NdotH * a2 - NdotH) * NdotH + 1.0f;
    return a2 / ((d * d + 1e-7f) * M_PI);
}

vec3 FresnelTerm(vec3 c, float cosA)
{
    float t = pow(1 - cosA, 5);
    return c + (1 - c) * t;
}

float GetSpecularOcclusion(float metallic, float roughness, float occlusion)
{
	return mix(occlusion, 1.0, metallic * (1.0 - roughness) * (1.0 - roughness));
}

mat3 MakeRotation(vec3 angles)
{
  mat3 rx = mat3(
    1, 0, 0, 
    0, cos(angles.x), -sin(angles.x), 
    0, sin(angles.x), cos(angles.x));
  mat3 ry = mat3(
    cos(angles.y), 0, sin(angles.y),
    0, 1, 0,
    -sin(angles.y), 0, cos(angles.y));
  mat3 rz = mat3(
    cos(angles.z), -sin(angles.z), 0,
    sin(angles.z), cos(angles.z), 0, 
    0, 0, 1);
  // Match Unity rotations order: Z axis, X axis, and Y axis (from right to left)
  return ry * rx * rz;
}

//- Shader entry point.
void shade(V2F inputs)
{
  // Apply parallax occlusion mapping if possible
  vec3 viewTS = worldSpaceToTangentSpace(getEyeVec(inputs.position), inputs);
  applyParallaxOffset(inputs, viewTS);

  // ------------------------------------------------------------------
  // Prepare all the inputs
  vec3 albedo = getBaseColor(basecolor_tex, inputs.sparse_coord);
  float specular = getSpecularLevel(specularlevel_tex, inputs.sparse_coord);
  float metallic = getMetallic(metallic_tex, inputs.sparse_coord);
  float roughness = getRoughness(roughness_tex, inputs.sparse_coord);
  float occlusion = getAO(inputs.sparse_coord) * getShadowFactor();
  vec3 emisstion = pbrComputeEmissive(emissive_tex, inputs.sparse_coord);

  vec3 diffColor = mix(albedo, vec3(0.0), metallic);
  vec3 specColor = ComputeF0(specular, albedo, metallic);

  LocalVectors vectors = computeLocalFrame(inputs);
  vec3 viewDir = vectors.eye;
  vec3 normalDir = vectors.normal;

  // ------------------------------------------------------------------
  // Compute Direct lighting
  vec3 lightColor = light_color * light_intensity;
  vec3 lightAngles = vec3(light_angle_x * 0.0174533, (180.0 + light_angle_y) * 0.0174533, light_angle_z * 0.0174533); // Degree to radian
  vec3 lightDir = MakeRotation(lightAngles) * vec3(0, 0, 1);
  vec3 halfDir = normalize(lightDir + viewDir);
  float nv = clamp(dot(normalDir, viewDir), 0, 1);
  float nl = clamp(dot(normalDir, lightDir), 0, 1);
  float nh = clamp(dot(normalDir, halfDir), 0, 1);
  float lv = clamp(dot(lightDir, viewDir), 0, 1);
  float lh = clamp(dot(lightDir, halfDir), 0, 1);

  // Diffuse term
  vec3 diffuseTerm = DisneyDiffuseTerm(nv, nl, lh, roughness, diffColor);

  // Specular term
  float V = SmithJointGGXVisibilityTerm(nl, nv, roughness);
  float D = GGXTerm(nh, roughness * roughness);
  vec3 F = FresnelTerm(specColor, lh);
  vec3 specularTerm = F * V * D;

  vec3 directLighting = M_PI * (diffuseTerm + specularTerm) * lightColor * nl;

  // ------------------------------------------------------------------
  // Compute indirect lighting
  vec3 indirectDiffuse = envIrradiance(vectors.normal) * diffColor * occlusion;

  float specOcclusion = GetSpecularOcclusion(metallic, roughness, occlusion);
  vec3 indirectSpecular = specOcclusion * pbrComputeSpecular(vectors, specColor, roughness);

  vec3 indirectLighting = indirectDiffuse + indirectSpecular;

  // ------------------------------------------------------------------
  // Combine all togather
  vec3 col = emisstion + directLighting + indirectLighting;

  diffuseShadingOutput(col);
}
