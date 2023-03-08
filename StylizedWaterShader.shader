Shader "Custom/StylizedWaterShader"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _FoamColor ("Foam Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _IntersectionTexture ("Intersection Texture", 2D) = "white" {}
        _IntersectionPow("Intersection Power", float) = 1
        _DepthIntersectionThreshold ("Depth Intersection Threshold", float) = 1
        _FoamNoise ("Foam Noise", 2D) = "white" {}
        _SpecularFactor ("Specular Factor", Range(0,10)) = 1.0
        [Normal] _Normal ("Water Normal", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(-2,2)) = 1.0
        _ShadowStrength("Shadow Strength", Range(0,1)) = 1.0

        _ReflectionRoughness("Reflection roughness", Range(0,1)) = 0
        _ReflectionNormalStrength("Reflection normal strength", Range(0,1)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent"}

        Blend SrcAlpha OneMinusSrcAlpha
        Zwrite Off
        LOD 200

        CGINCLUDE
        #include "UnityCG.cginc"

        sampler2D _FoamNoise;
        float4 _FoamNoise_ST;
        sampler2D _IntersectionTexture;
        float4 _IntersectionCamProperties;
        
        sampler2D _CameraDepthTexture;
         float _DepthIntersectionThreshold;
         float _IntersectionPow;

        float CalculateFoam(float3 worldPos, float2 texcoord, float depthDifference)
        {
            float2 intersectionRTUVs = worldPos.xz - _IntersectionCamProperties.xz;
            intersectionRTUVs= intersectionRTUVs/(_IntersectionCamProperties.w * 2);
            intersectionRTUVs += 0.5;

            float depthIntersection = saturate(depthDifference/ _DepthIntersectionThreshold);


            float intersectionVal =  clamp(tex2D(_IntersectionTexture, intersectionRTUVs).r, 0, 1);

            float intersectionTex = ((pow(intersectionVal, _IntersectionPow))) * depthIntersection;
            //float intersection = saturate((sin((1-intersectionTex) * 25.0 - _Time.y * 2.5) * 0.5 + 0.5) * pow(1-intersectionTex, 1.0) + pow(1-intersectionTex,5.0));
            float intersection = saturate((sin((1-intersectionTex) * 40.0 - _Time.y * 2) * 0.5 + 0.5) * pow(1-intersectionTex, 15.0) + pow(1-intersectionTex,3.0));
            
            float2 scrolledTexcoord = texcoord * _FoamNoise_ST.xy + _Time.y * _FoamNoise_ST.zw; //+ _Time.y + _FoamNoise_ST.zw;
            float foamTex = tex2D(_FoamNoise, scrolledTexcoord).x;
           // float foam = step(pow(intersection, _IntersectionPow), foamTex);
            //float foam = step(pow(intersection, _IntersectionPow), foamTex);
            float foam = smoothstep(intersection, intersection - 0.01, foamTex);


            return  foam;
        }

        float CalculateDepthDifference(float4 screenPos)
        {
            float depth = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(screenPos));
            //float2 screenPos = IN.screenPos.xy / IN.screenPos.w;
            //screenPos.x = 1- screenPos.x;
            float diff;
            if(unity_OrthoParams.w == 0)
            {
                depth = LinearEyeDepth(depth);
                diff = depth - screenPos.w;
            }
            else
            {
                float near = _ProjectionParams.y;
                float far = _ProjectionParams.z;
                #ifdef UNITY_REVERSED_Z
                    float dist = -lerp(near, far, depth);
                    float scrDis = -lerp(near, far, screenPos.z);
                #else
                    float dist = -lerp(far, near, depth);
                    float scrDis = -lerp(far, near, screenPos.z);
                #endif

                diff = dist - scrDis;
            }

            return diff;
        }

        ENDCG

        GrabPass
        {
            "_GrabTexture"
        }

        Pass
        {
            Tags
            {
                "LightMode" = "ShadowCaster"
            }
            BlendOp Add
            Blend One Zero
            ZWrite On
            Cull Off

            CGPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow

            #include "Lighting.cginc"
            #pragma multi_compile ShadowCaster

            struct v2fShadow
            {
                V2F_SHADOW_CASTER;
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float4 screenPos : TEXCOORD2;
            };

            sampler2D _MainTex;
            sampler3D _DitherMaskLOD;
            float _ShadowStrength;

            v2fShadow vertShadow(appdata_full v)
            {
                v2fShadow o;
                o.uv = v.texcoord;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.screenPos = ComputeScreenPos(UnityObjectToClipPos(v.vertex));
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                return o;
            }

            float4 fragShadow(v2fShadow i) : SV_Target
            {
                float depthDifference = CalculateDepthDifference(i.screenPos);
                float foam = CalculateFoam(i.worldPos, i.uv, depthDifference);
                float dither = tex3D(_DitherMaskLOD, float3(i.worldPos.xz * 500.0, _ShadowStrength * 0.9375)).a;
                clip(foam.x * dither - 0.1);
                SHADOW_CASTER_FRAGMENT(i)
            }

            ENDCG
        }

        //Pass
        //{
        
        CGPROGRAM
        #pragma surface surf Water fullforwardshadows vertex:vert alpha:fade
        #pragma target 5.0

        sampler2D _MainTex;
        sampler2D _Normal;
        float4 _Normal_ST;
        float _NormalStrength;

        struct Input
        {
            float2 uv_MainTex;
            //float2 uv_Normal;
            float4 grabPassUV;
            float2 texcoord;
            float3 worldPos;
            float4 screenPos;
            float3 worldNormal;
            INTERNAL_DATA
        };


        struct SurfaceOutputWater 
        {
            fixed3 Albedo;
            half3 Emission;
            fixed3 Normal;
            half Smoothness;
            half Alpha;
        };

        half _Glossiness;
        fixed4 _Color;
        fixed4 _FoamColor;
        float _SpecularFactor;
        sampler2D _GrabTexture;
        float _ReflectionNormalStrength;
        float _ReflectionRoughness;

       


        float4 LightingWater(SurfaceOutputWater s, float3 lightDir, half3 viewDir, half atten)
        {
            float4 col = float4(s.Albedo, s.Alpha);
            //dot(s.Normal, lightDir) returns how much the surface normal points towards the light
            //It has a value of 0 where the surface is paralell to the direction to the light, 
            //is has a value of 1 where the light points towards the light 
            //and a value of -1 where the surface points away.

            //Returns dot(s.Normal, lightDir) saturated to the range [0,1] as follows:

            //1) Returns 0 if x is less than 0; else
            //2) Returns 1 if x is greater than 1; else
            //3) Returns x otherwise.
            float ndotl = saturate(dot(s.Normal, normalize(lightDir)));
            float shadow = ndotl * atten;
            //multiply the color by the saturated light value
            col.rgb *= shadow;

           half3 h = normalize(lightDir + viewDir);
           float nh = max(0, dot(s.Normal,h));
           float spec = step(0.01, pow(nh,lerp(48.0,500,s.Smoothness)));
           col.rgb = spec * shadow * _LightColor0 * s.Smoothness * _SpecularFactor;

           return col;

        }

        
        float3 BoxProjection(float3 direction, float3 position, float4 cubemapPosition, float3 boxMin, float3 boxMax)
        {
            float3 factors = ((direction > 0 ? boxMax : boxMin) - position) / direction;
            float scalar = min(min(factors.x, factors.y), factors.z);
            if(cubemapPosition.w > 0)
            {
                direction = direction * scalar + (position - cubemapPosition);
            }
            return direction;
        }

        float3 SampleReflectionProbes(float3 worldPos, float3 normal)
        {
            half3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
            //float3 reflectionNormal = float3(normal.rg * _ReflectionNormalStrength, lerp(1, normal.b, saturate(_ReflectionNormalStrength)));
            half3 worldRefl = reflect(-worldViewDir,  normal);
            half4 skyData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, BoxProjection(worldRefl,worldPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin,unity_SpecCube0_BoxMax), _ReflectionRoughness * UNITY_SPECCUBE_LOD_STEPS);
            return skyData.rgb;
        }
 
        // Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
        // See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
        // #pragma instancing_options assumeuniformscaling
        UNITY_INSTANCING_BUFFER_START(Props)
            // put more per-instance properties here
        UNITY_INSTANCING_BUFFER_END(Props)


        void vert(inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input,o);
            o.grabPassUV = ComputeGrabScreenPos(UnityObjectToClipPos(v.vertex));
            o.texcoord = v.texcoord;
        }

        void surf (Input IN, inout SurfaceOutputWater o)
        {
            fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;

         
            float depthDifference = CalculateDepthDifference(IN.screenPos);
            float foam = CalculateFoam(IN.worldPos, IN.texcoord, depthDifference);
            //foam = depthIntersection;
            //float foam = smoothstep(intersection, intersection - 0.1, foamTex);

            float3 normals = UnpackNormalWithScale(tex2D(_Normal, IN.texcoord * _Normal_ST.xy + _Time.xy * _Normal_ST.zw), _NormalStrength);
            o.Normal = normals;

            fixed4 grabCol = tex2Dproj(_GrabTexture, IN.grabPassUV + float4(normals.xy * 2.0 - 1.0,0,0));
            float3 reflectionNormal = float3(o.Normal.rg * _ReflectionNormalStrength, lerp(1, o.Normal.b, saturate(_ReflectionNormalStrength)));
            float3 reflectionProbeColor = SampleReflectionProbes(IN.worldPos, WorldNormalVector(IN,reflectionNormal));


            
            //half3 skyColor = DecodeHDR(skyData, unity_SpecCube0_HDR);

            c.rgb += c.rgb * reflectionProbeColor.rgb;

            o.Albedo = lerp(grabCol.rgb,lerp(c.rgb, _FoamColor,foam),max(c.a, foam));
            //o.Albedo = lerp(grabCol.rgb, c.rgb, c.a);
            //o.Albedo = foam;
            //o.Albedo = tex2D(_Normal, IN.texcoord * _Normal_ST.xy);
            //o.Albedo = intersection;

           

            //o.Albedo = skyColor;
        
            o.Smoothness = _Glossiness;
            o.Alpha = 1.0;
        }
        ENDCG
        //}

        
    }
    FallBack "Diffuse"
}
