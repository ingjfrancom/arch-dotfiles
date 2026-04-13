#version 100
precision mediump float;

varying vec2 v_texcoord;
uniform sampler2D tex;

void main() {
    vec4 color = texture2D(tex, v_texcoord);

    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 saturated = mix(vec3(gray), color.rgb, 1.8);

    saturated *= 1.05;

    gl_FragColor = vec4(saturated, color.a);
}
