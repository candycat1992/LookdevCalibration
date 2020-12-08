#ifndef CUSTOM_STANDARD_BRDF_INCLUDED
#define CUSTOM_STANDARD_BRDF_INCLUDED

half DielectricSpecularToF0(half specular)
{
	return 0.08 * specular;
}

half3 ComputeF0(half specular, half3 baseColor, half metallic)
{
	return lerp(DielectricSpecularToF0(specular).xxx, baseColor, metallic);
}

half3 DisneyDiffuseTerm(half NdotV, half NdotL, half LdotH, half perceptualRoughness, half3 baseColor)
{
    half fd90 = 0.5 + 2 * LdotH * LdotH * perceptualRoughness;
    // Two schlick fresnel term
    half lightScatter = (1 + (fd90 - 1) * pow(1 - NdotL, 5));
    half viewScatter = (1 + (fd90 - 1) * pow(1 - NdotV, 5));
    return baseColor * UNITY_INV_PI * lightScatter * viewScatter;
}

half SmithJointGGXVisibilityTerm(half NdotL, half NdotV, half roughness)
{   
    // Original formulation:
    //  lambda_v    = (-1 + sqrt(a2 * (1 - NdotL2) / NdotL2 + 1)) * 0.5f;
    //  lambda_l    = (-1 + sqrt(a2 * (1 - NdotV2) / NdotV2 + 1)) * 0.5f;
    //  G           = 1 / (1 + lambda_v + lambda_l);

    // Reorder code to be more optimal
    half a          = roughness;
    half a2         = a * a;

    half lambdaV    = NdotL * sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
    half lambdaL    = NdotV * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);

    // Simplify visibility term: (2.0f * NdotL * NdotV) /  ((4.0f * NdotL * NdotV) * (lambda_v + lambda_l + 1e-5f));
    return 0.5f / (lambdaV + lambdaL + 1e-5f);
}

half GGXTerm(half NdotH, half roughness)
{
    half a2 = roughness * roughness;
    half d = (NdotH * a2 - NdotH) * NdotH + 1.0f;
    return UNITY_INV_PI * a2 / (d * d + 1e-7f);
}

half3 FresnelTerm(half3 c, half cosA)
{
    half t = pow(1 - cosA, 5);
    return c + (1 - c) * t;
}

half GetSpecularOcclusion(half metallic, half roughness, half occlusion)
{
	return lerp(occlusion, 1.0, metallic * (1.0 - roughness) * (1.0 - roughness));
}

half PerceptualRoughnessToMipmapLevel(half perceptualRoughness)
{
    return perceptualRoughness * 6;
}

half ComputeEnvMapMipFromRoughness(half roughness)
{
	half perceptualRoughness = roughness;
    perceptualRoughness = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness);
	return PerceptualRoughnessToMipmapLevel(perceptualRoughness);
}

half3 EnvBRDF(half3 specColor, half roughness, half NdotV) 
{
	// [ Lazarov 2013, "Getting More Physical in Call of Duty: Black Ops II" ]
	// Adaptation to fit our G term.
	const half4 c0 = { -1, -0.0275, -0.572, 0.022 };
	const half4 c1 = { 1, 0.0425, 1.04, -0.04 };
	half4 r = roughness * c0 + c1;
	half a004 = min( r.x * r.x, exp2( -9.28 * NdotV ) ) * r.x + r.y;
	half2 AB = half2( -1.04, 1.04 ) * a004 + r.zw;

	// Anything less than 2% is physically impossible and is instead considered to be shadowing
	// Note: this is needed for the 'specular' show flag to work, since it uses a SpecularColor of 0
	AB.y *= saturate( 50.0 * specColor.g );

	return specColor * AB.x + AB.y;
}

#endif // CUSTOM_STANDARD_BRDF_INCLUDED