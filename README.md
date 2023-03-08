# UnityWaterShader
HLSL water shader made in Unity.

The stylized water shader provided is made using a Unity standard surface shader. It incorporates an extra camera that uses an orthographic frustum box that extends the water plane with a small distance between the near and far planes to create an intersection texture to identify objects in the water. This texture is then processed through a signed distance field (SDF), resulting in a texture used to draw foam on the water. The program also uses a depth texture as an alternative method for generating foam. To create a reflection on the water's surface, the shader utilizes a reflection probe.

The SDF generation code is made by Carl Carlsen.
http://cec.dk
