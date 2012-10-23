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
	vec3 NN = normalize(var_normal);
//	vec3 lighting = lightPos.xyz - var_vertex.xyz/var_vertex.w;
	vec3 lighting = lightPos.xyz;
	vec3 lightdir = normalize(lighting);
	float ldot = min(1.0, 1.0/dot(lighting,lighting));
	
	vec4 tex0color = texture(textureMap, var_texcoord0.xy);
	//vec4 tex0color = vec4(1.0,1.0,1.0,1.0)*0.5;
	
	//	gl_FragColor = vec4(tex0color.rgb, tex0color.a)*color;
	//	gl_FragColor = vec4(1.0,1.0,1.0,1.0);
	float diffuse = -min(0.0,dot(NN, lightdir)*(float(gl_FrontFacing)*2.0 - 1.0));
//	out_fragColor = vec4(tex0color.rgb*(0.5*diffuse*ldot + 1.0*var_color.rgb), tex0color.a);
	out_fragColor = vec4(tex0color.rgb*(0.9*diffuse*ldot + 0.1*var_color.rgb), tex0color.a);
}
