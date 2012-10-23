#version 150

uniform sampler2D	textureMap;
uniform vec4		lightPos;

in vec3 var_normal;
in vec4 var_vertex;
in vec4 var_color;
in vec4 var_texcoord0;

out vec4 out_fragColor;

void main()
{	
	vec4 tex0color = texture(textureMap, var_texcoord0.xy);

	out_fragColor = tex0color*var_color;
}
