#version 100
precision highp float;

// Pencil design expression of the project's optical profile, not Apple's
// native Liquid Glass implementation or a pixel-equivalent Flutter renderer.
// Use as the node's sole background fill at opacity 1. Children remain sharp.
// The host clips this fill to the node shape; retain its existing shadow only.
// Do not add background_blur, a second glass fill, or the old radial panel mask.
// Every visual input below must be bound to the existing Pencil variables.

/** @resolution */
uniform vec2 u_resolution;
/** @sdf */
uniform sampler2D u_sdf;
/**
 * @backdrop
 * @mipmap
 */
uniform sampler2D u_backdrop;

/** @label Refraction index */
uniform float u_ior;
/** @label Refraction width */
uniform float u_refractionWidth;
/** @label Scattering blur */
uniform float u_blur;
/**
 * @label Material tint
 * @color
 */
uniform vec4 u_tint;
/**
 * @label Edge light
 * @color
 */
uniform vec4 u_edgeLight;

/** @label Specular thickness */
uniform float u_specularThickness;
/** @label Specular sharpness */
uniform float u_specularSharpness;
/** @label Specular angle */
uniform float u_specularAngle;
/** @label Specular spread */
uniform float u_specularSpread;
/** @label Specular intensity */
uniform float u_specularIntensity;
/** @label Specular opposite intensity */
uniform float u_specularOppositeIntensity;
/** @label Glow thickness */
uniform float u_glowThickness;
/** @label Glow angle */
uniform float u_glowAngle;
/** @label Glow spread */
uniform float u_glowSpread;
/** @label Glow intensity */
uniform float u_glowIntensity;
/** @label Glow opposite intensity */
uniform float u_glowOppositeIntensity;

// Numerical tolerances and quadrature constants are algorithmic, not styling.
const float EPS = 0.00001;
const float PI = 3.141592653589793;
const float SQRT_TWO = 1.4142135623730951;

// A normalized 3 x 3 binomial quadrature. The offset gives this kernel unit
// variance before scaling by sigma. Pencil accepts two-argument sampling;
// the host mirrors backdrop samples outside the node, including refraction.
vec4 scatterBackdrop(vec2 uv, float sigma) {
    if (sigma <= EPS) return texture2D(u_backdrop, uv);
    vec2 stepUV = vec2(SQRT_TWO * sigma) / max(u_resolution, vec2(EPS));
    vec4 c = texture2D(u_backdrop, uv) * 0.25;
    c += texture2D(u_backdrop, uv + vec2(stepUV.x, 0.0)) * 0.125;
    c += texture2D(u_backdrop, uv - vec2(stepUV.x, 0.0)) * 0.125;
    c += texture2D(u_backdrop, uv + vec2(0.0, stepUV.y)) * 0.125;
    c += texture2D(u_backdrop, uv - vec2(0.0, stepUV.y)) * 0.125;
    c += texture2D(u_backdrop, uv + stepUV) * 0.0625;
    c += texture2D(u_backdrop, uv - stepUV) * 0.0625;
    c += texture2D(u_backdrop, uv + vec2(stepUV.x, -stepUV.y)) * 0.0625;
    c += texture2D(u_backdrop, uv + vec2(-stepUV.x, stepUV.y)) * 0.0625;
    return c;
}

// Two opposing arcs follow the actual shape normal, not an oval painted on
// top. Zero spread narrows the arc; zero intensity disables its light.
float lightArc(vec2 outward, float angle, float spread, float opposite) {
    float angleRadians = angle * PI / 180.0;
    float facing = dot(outward, vec2(cos(angleRadians), sin(angleRadians)));
    float arc = pow(clamp(abs(facing), 0.0, 1.0),
                    1.0 / max(clamp(spread, 0.0, 1.0), EPS));
    return arc * (facing < 0.0 ? max(opposite, 0.0) : 1.0);
}

float inwardRamp(float distanceInside, float thickness, float sharpness) {
    if (thickness <= EPS) return 0.0;
    float t = clamp(1.0 - distanceInside / thickness, 0.0, 1.0);
    float s = clamp(sharpness, 0.0, 1.0);
    return pow(t, 1.0 / max(1.0 - s, EPS));
}

void main() {
    vec2 resolution = max(u_resolution, vec2(EPS));
    vec2 uv = gl_FragCoord.xy / resolution;
    vec3 sdf = texture2D(u_sdf, uv).rgb;
    // Pencil SDF is positive inside, in local pixels. Its gb channels are
    // the gradient of increasing distance, so negate for the outward normal.
    float distanceInside = max(sdf.r, 0.0);
    vec2 gradient = sdf.gb;
    vec2 outward = -gradient / max(length(gradient), EPS);
    float width = max(u_refractionWidth, EPS);
    float depthFraction = clamp(distanceInside / width, 0.0, 1.0);
    float edgeFraction = 1.0 - depthFraction;

    // A circular bevel cross-section supplies the 3D surface normal.
    // Its optical depth is the existing bevel width: no extra gain or
    // unbound thickness constant is introduced to exaggerate the bend.
    vec3 normal = normalize(vec3(
        outward * sqrt(max(1.0 - depthFraction * depthFraction, 0.0)),
        depthFraction
    ) + vec3(0.0, 0.0, EPS));
    float ior = max(u_ior, 1.0);
    vec3 ray = refract(vec3(0.0, 0.0, -1.0), normal, 1.0 / ior);
    vec2 refractedUV = uv + ray.xy * width * edgeFraction / resolution;

    // The middle scatters; the beveled edge retains the sharp displaced
    // scene. Clear uses its own low blur/tint bindings, never a white mask.
    float sigma = max(u_blur, 0.0) * sqrt(depthFraction);
    vec4 backdrop = scatterBackdrop(refractedUV, sigma);
    vec3 backdropColor = backdrop.rgb / max(backdrop.a, EPS);
    float tintAlpha = clamp(u_tint.a, 0.0, 1.0);
    vec3 color = mix(backdropColor, u_tint.rgb, tintAlpha);
    float alpha = backdrop.a + tintAlpha * (1.0 - backdrop.a);

    // Schlick reflectance changes with the lens normal. The light's color
    // only lifts the real, tinted backdrop; no white silhouette is drawn.
    float r0 = (ior - 1.0) / (ior + 1.0);
    r0 *= r0;
    float fresnel = r0 + (1.0 - r0) * pow(1.0 - normal.z, 5.0);
    float specular = inwardRamp(distanceInside, u_specularThickness,
                               u_specularSharpness)
        * lightArc(outward, u_specularAngle, u_specularSpread,
                   u_specularOppositeIntensity)
        * max(u_specularIntensity, 0.0) * fresnel;
    float glow = inwardRamp(distanceInside, u_glowThickness, 0.0)
        * lightArc(outward, u_glowAngle, u_glowSpread,
                   u_glowOppositeIntensity)
        * max(u_glowIntensity, 0.0) * fresnel;
    float light = 1.0 - (1.0 - clamp(specular, 0.0, 1.0))
                           * (1.0 - clamp(glow, 0.0, 1.0));
    light *= clamp(u_edgeLight.a, 0.0, 1.0);
    color = mix(color, max(color, u_edgeLight.rgb), light);
    alpha += light * (1.0 - alpha);
    gl_FragColor = vec4(color * alpha, alpha);
}
