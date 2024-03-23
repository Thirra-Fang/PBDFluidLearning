
Shader "PBDFluid/Volume"
{
	Properties
	{
		AbsorptionCoff("Absorption Coff", Vector) = (0.45, 0.029, 0.018)
		AbsorptionScale("Absorption Scale", Range(0.01, 1000)) = 1.5
	}
		SubShader
	{
		Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }
		LOD 100

		GrabPass { "BackGroundTexture" }

		cull front
		ztest Always
		blend SrcAlpha OneMinusSrcAlpha

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			#define NUM_SAMPLES 64

			float AbsorptionScale;
			float3 AbsorptionCoff;
			float3 Translate, Scale, Size;
			sampler3D Volume;
			sampler2D BackGroundTexture;
			float PixelSize;

			struct v2f
			{
				float4 pos : SV_POSITION;
				float3 worldPos : TEXCOORD0;
				float4 grabPos : TEXCOORD1;
			};

			v2f vert(appdata_base v)
			{
				v2f OUT;
				OUT.pos = UnityObjectToClipPos(v.vertex);
				OUT.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
				OUT.grabPos = ComputeGrabScreenPos(OUT.pos);
				return OUT;
			}

			struct Ray 
			{
				float3 origin;
				float3 dir;
			};

			struct AABB 
			{
				float3 Min;
				float3 Max;
			};

			//find intersection points of a ray with a box
			//翻译：寻找一条射线和Box的交点
			bool IntersectBox(Ray r, AABB aabb, out float t0, out float t1)
			{
				float3 invR = 1.0 / r.dir;
				float3 tbot = invR * (aabb.Min - r.origin);
				float3 ttop = invR * (aabb.Max - r.origin);
				float3 tmin = min(ttop, tbot);
				float3 tmax = max(ttop, tbot);
				float2 t = max(tmin.xx, tmin.yz);
				t0 = max(t.x, t.y);
				t = min(tmax.xx, tmax.yz);
				t1 = min(t.x, t.y);
				return t0 <= t1;
			}
			
			fixed4 frag (v2f IN) : SV_Target
			{
				float3 pos = _WorldSpaceCameraPos;
				float3 grab = tex2Dproj(BackGroundTexture, IN.grabPos).rgb;
				//此面元的背景纹理
				
				Ray r;
				r.origin = pos;
				r.dir = normalize(IN.worldPos - pos);
				//从相机到该片元的射线

				AABB aabb;
				aabb.Min = float3(-0.5,-0.5,-0.5) * Scale + Translate;
				aabb.Max = float3(0.5,0.5,0.5) * Scale + Translate;
				//渲染的立方体的边界点

				//figure out where ray from eye hit front of cube
				float tnear, tfar;
				IntersectBox(r, aabb, tnear, tfar);

				//if eye is in cube then start ray at eye
				//如果摄像机在立方体内
				if (tnear < 0.0) tnear = 0.0;

				float3 rayStart = r.origin + r.dir * tnear;
				float3 rayStop = r.origin + r.dir * tfar;
				//立方体内射线起终点，世界坐标

				//convert to texture space
				rayStart -= Translate;
				rayStop -= Translate;
				rayStart = (rayStart + 0.5 * Scale) / Scale;
				rayStop = (rayStop + 0.5 * Scale) / Scale;
				//以立方体最小点为原点，归一化，纹理空间

				float3 start = rayStart;
				//归一化后的坐标
				float dist = distance(rayStop, rayStart);
				float stepSize = dist / float(NUM_SAMPLES);
				//此处可能有问题。不加权固定检测步数?
				//float stepSize = PixelSize/Scale;
				//int step = dist/stepSize;
				float3 ds = normalize(rayStop - rayStart) * stepSize;
				
				//accumulate density though volume along ray
				//计数射线上的粒子密度（其实应该不算密度？）应该是厚度纹理
				float density = 0;
				for (int i = 0; i < NUM_SAMPLES; i++, start += ds)
				{
					density += tex3D(Volume,start).x*stepSize;
				}
				/*while(distance(start,rayStart)<dist)
				{
					start+=ds;
					density+=tex3D(Volume,start).x;
				}*/

				float3 col = grab *exp(-AbsorptionCoff * density * AbsorptionScale);

				return float4(col, 1);
			}
			ENDCG
		}
	}
}

