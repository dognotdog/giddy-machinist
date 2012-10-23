#version 150


in vec4 in_vertex;
in vec3 in_normal;
in vec4 in_color;
in vec4 in_texcoord0;
in vec4 in_texcoord1;

uniform mat4 normalMatrix;
uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 mvpMatrix;
uniform mat4 textureMatrix0;

//uniform vec4 lightPos;

out vec3 var_normal;
out vec4 var_vertex;
out vec4 var_color;
out vec4 var_texcoord0;
out vec4 var_texcoord1;

void main()
{
	var_normal = mat3(normalMatrix)*in_normal;
	
	var_vertex = modelViewMatrix*in_vertex;
	
	var_texcoord0 = textureMatrix0 * in_texcoord0;
	var_texcoord1 = textureMatrix0 * in_texcoord1;
	
	var_color = in_color;
	
	gl_Position = mvpMatrix*in_vertex;
	
}