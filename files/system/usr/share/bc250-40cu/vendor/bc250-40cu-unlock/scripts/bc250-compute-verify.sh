#!/usr/bin/env bash
# bc250-compute-verify.sh - heavy Vulkan compute correctness test for BC-250.

set -euo pipefail

ELEMENTS=16777216
PASSES=3
ITERS=64
KEEP_TMP=0

usage() {
	cat <<EOF
Usage: $0 [--elements N] [--passes N] [--iters N] [--keep-tmp]

Runs a Vulkan compute correctness test with:
  - FP32 fma chains
  - integer multiply/add
  - bitwise rotate/xor/shift patterns
  - LDS shared-memory read/write
  - full per-element CPU golden comparison

ELEMENTS must be a multiple of 256. Default: $ELEMENTS
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--elements)
			ELEMENTS="${2:?missing value for --elements}"
			shift 2
			;;
		--passes)
			PASSES="${2:?missing value for --passes}"
			shift 2
			;;
		--iters)
			ITERS="${2:?missing value for --iters}"
			shift 2
			;;
		--keep-tmp)
			KEEP_TMP=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "ERROR: unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

case "$ELEMENTS:$PASSES:$ITERS" in
	*[!0-9:]*|"")
		echo "ERROR: --elements, --passes, and --iters must be positive integers" >&2
		exit 2
		;;
esac

if [ "$ELEMENTS" -le 0 ] || [ "$PASSES" -le 0 ] || [ "$ITERS" -le 0 ]; then
	echo "ERROR: --elements, --passes, and --iters must be positive integers" >&2
	exit 2
fi

if [ $((ELEMENTS % 256)) -ne 0 ]; then
	echo "ERROR: --elements must be a multiple of 256" >&2
	exit 2
fi

command -v glslangValidator >/dev/null 2>&1 || {
	echo "ERROR: glslangValidator not found" >&2
	exit 1
}
command -v gcc >/dev/null 2>&1 || {
	echo "ERROR: gcc not found" >&2
	exit 1
}

TMPDIR="$(mktemp -d)"
if [ "$KEEP_TMP" -eq 0 ]; then
	trap 'rm -rf "$TMPDIR"' EXIT
else
	echo "Keeping temporary files in $TMPDIR"
fi

cat >"$TMPDIR/bc250_compute_verify.comp" <<'GLSL'
#version 450

layout(local_size_x = 256) in;

layout(std430, set = 0, binding = 0) readonly buffer InputA {
	uint a[];
};

layout(std430, set = 0, binding = 1) readonly buffer InputB {
	uint b[];
};

layout(std430, set = 0, binding = 2) writeonly buffer OutputInt {
	uint out_int[];
};

layout(std430, set = 0, binding = 3) writeonly buffer OutputFp {
	uint out_fp[];
};

layout(push_constant) uniform Params {
	uint n;
	uint seed;
	uint pass;
	uint iters;
} pc;

shared uint lds[256];

uint rotl32(uint v, uint s)
{
	s &= 31u;
	return s == 0u ? v : ((v << s) | (v >> (32u - s)));
}

void main()
{
	uint idx = gl_GlobalInvocationID.x;
	uint lid = gl_LocalInvocationID.x;
	uint x = a[idx] ^ pc.seed ^ (pc.pass * 0x9e3779b9u);
	uint y = b[idx] + rotl32(idx ^ pc.seed, pc.pass + 7u);
	float f = uintBitsToFloat(0x3f800000u | (x & 0x007fffffu));

	for (uint j = 0u; j < pc.iters; ++j) {
		x = x * 1664525u + 1013904223u + j + pc.pass;
		x ^= rotl32(y + j * 0x45d9f3bu, j + pc.pass);
		y += x ^ (j * 0x27d4eb2du) ^ (x >> ((j & 7u) + 1u));
		f = fma(f, 1.0009765625, float(int(y & 255u) - 128) * 0.00000011920928955078125);
	}

	lds[lid] = x ^ y ^ pc.seed;
	barrier();

	uint peer0 = lds[(lid * 17u + pc.pass) & 255u];
	uint peer1 = lds[(lid + 1u) & 255u];
	x ^= peer0 + rotl32(peer1, lid);
	y ^= rotl32(peer0 ^ peer1, pc.pass + 11u);

	out_int[idx] = x ^ y ^ rotl32(idx + pc.seed, pc.pass);
	out_fp[idx] = floatBitsToUint(f);
}
GLSL

cat >"$TMPDIR/bc250_compute_verify.c" <<'C'
#define _POSIX_C_SOURCE 200809L

#include <vulkan/vulkan.h>

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define LOCAL_SIZE 256u

#define CHECK(call) do { \
	VkResult _res = (call); \
	if (_res != VK_SUCCESS) { \
		fprintf(stderr, "%s failed: %d at line %d\n", #call, _res, __LINE__); \
		return 1; \
	} \
} while (0)

struct params {
	uint32_t n;
	uint32_t seed;
	uint32_t pass;
	uint32_t iters;
};

static uint32_t rotl32(uint32_t v, uint32_t s)
{
	s &= 31u;
	return s == 0u ? v : (uint32_t)((v << s) | (v >> (32u - s)));
}

static uint32_t f32_bits(float f)
{
	uint32_t u;
	memcpy(&u, &f, sizeof(u));
	return u;
}

static float bits_f32(uint32_t u)
{
	float f;
	memcpy(&f, &u, sizeof(f));
	return f;
}

static uint32_t fp32_ordered_bits(uint32_t bits)
{
	if (bits & 0x80000000u)
		return 0x80000000u - (bits & 0x7fffffffu);
	return 0x80000000u + bits;
}

static uint32_t fp32_ulp_distance(uint32_t a, uint32_t b)
{
	uint32_t oa = fp32_ordered_bits(a);
	uint32_t ob = fp32_ordered_bits(b);

	return oa > ob ? oa - ob : ob - oa;
}

static void pre_lds_expected(uint32_t idx, const uint32_t *a, const uint32_t *b,
			     const struct params *p, uint32_t *x_out,
			     uint32_t *y_out, uint32_t *fp_out)
{
	uint32_t x = a[idx] ^ p->seed ^ (p->pass * 0x9e3779b9u);
	uint32_t y = b[idx] + rotl32(idx ^ p->seed, p->pass + 7u);
	float f = bits_f32(0x3f800000u | (x & 0x007fffffu));

	for (uint32_t j = 0; j < p->iters; ++j) {
		x = x * 1664525u + 1013904223u + j + p->pass;
		x ^= rotl32(y + j * 0x45d9f3bu, j + p->pass);
		y += x ^ (j * 0x27d4eb2du) ^ (x >> ((j & 7u) + 1u));
		f = fmaf(f, 1.0009765625f,
			 (float)((int)(y & 255u) - 128) * 0.00000011920928955078125f);
	}

	*x_out = x;
	*y_out = y;
	*fp_out = f32_bits(f);
}

static void final_expected(uint32_t idx, const uint32_t *lds,
			   uint32_t x, uint32_t y, const struct params *p,
			   uint32_t *int_out)
{
	uint32_t lid = idx & (LOCAL_SIZE - 1u);
	uint32_t peer0 = lds[(lid * 17u + p->pass) & 255u];
	uint32_t peer1 = lds[(lid + 1u) & 255u];

	x ^= peer0 + rotl32(peer1, lid);
	y ^= rotl32(peer0 ^ peer1, p->pass + 11u);
	*int_out = x ^ y ^ rotl32(idx + p->seed, p->pass);
}

static uint32_t find_memory_type(VkPhysicalDevice pd, uint32_t bits,
				 VkMemoryPropertyFlags flags)
{
	VkPhysicalDeviceMemoryProperties props;

	vkGetPhysicalDeviceMemoryProperties(pd, &props);
	for (uint32_t i = 0; i < props.memoryTypeCount; ++i) {
		if ((bits & (1u << i)) &&
		    (props.memoryTypes[i].propertyFlags & flags) == flags)
			return i;
	}

	return UINT32_MAX;
}

static int read_file(const char *path, char **buf, size_t *size)
{
	FILE *f = fopen(path, "rb");
	long len;

	if (!f)
		return 1;
	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		return 1;
	}
	len = ftell(f);
	if (len <= 0) {
		fclose(f);
		return 1;
	}
	rewind(f);
	*buf = malloc((size_t)len);
	if (!*buf) {
		fclose(f);
		return 1;
	}
	if (fread(*buf, 1, (size_t)len, f) != (size_t)len) {
		fclose(f);
		free(*buf);
		return 1;
	}
	fclose(f);
	*size = (size_t)len;
	return 0;
}

static double now_sec(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	const char *spv_path;
	uint32_t n;
	uint32_t passes;
	uint32_t iters;
	const VkDeviceSize bytes_in = 0;
	VkApplicationInfo app = {
		.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
		.pApplicationName = "bc250-compute-verify",
		.apiVersion = VK_API_VERSION_1_1,
	};
	VkInstanceCreateInfo ici = {
		.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		.pApplicationInfo = &app,
	};
	VkInstance instance;
	VkPhysicalDevice pds[16];
	uint32_t pd_count = 16;
	VkPhysicalDevice pd = VK_NULL_HANDLE;
	VkPhysicalDeviceProperties pd_props;
	uint32_t queue_family = UINT32_MAX;
	VkQueueFamilyProperties qprops[32];
	uint32_t qcount = 32;
	float priority = 1.0f;
	VkDeviceQueueCreateInfo qci = {
		.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		.queueCount = 1,
		.pQueuePriorities = &priority,
	};
	VkDeviceCreateInfo dci = {
		.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.queueCreateInfoCount = 1,
		.pQueueCreateInfos = &qci,
	};
	VkDevice dev;
	VkQueue queue;
	VkBuffer buffers[4] = {0};
	VkDeviceMemory memories[4] = {0};
	void *maps[4] = {0};
	VkDescriptorSetLayoutBinding bindings[4];
	VkDescriptorSetLayoutCreateInfo dsli = {
		.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		.bindingCount = 4,
		.pBindings = bindings,
	};
	VkDescriptorSetLayout dsl;
	VkPushConstantRange pcr = {
		.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
		.offset = 0,
		.size = sizeof(struct params),
	};
	VkPipelineLayoutCreateInfo plci = {
		.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
		.setLayoutCount = 1,
		.pSetLayouts = &dsl,
		.pushConstantRangeCount = 1,
		.pPushConstantRanges = &pcr,
	};
	VkPipelineLayout pipeline_layout;
	char *spv = NULL;
	size_t spv_size = 0;
	VkShaderModuleCreateInfo smci = {
		.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
	};
	VkShaderModule shader;
	VkComputePipelineCreateInfo cpci = {
		.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
	};
	VkPipeline pipeline;
	VkDescriptorPoolSize pool_size = {
		.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
		.descriptorCount = 4,
	};
	VkDescriptorPoolCreateInfo dpci = {
		.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
		.maxSets = 1,
		.poolSizeCount = 1,
		.pPoolSizes = &pool_size,
	};
	VkDescriptorPool pool;
	VkDescriptorSetAllocateInfo dsai = {
		.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
		.descriptorSetCount = 1,
	};
	VkDescriptorSet ds;
	VkCommandPoolCreateInfo cmdp_ci = {
		.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
	};
	VkCommandPool cmd_pool;
	VkFenceCreateInfo fci = {
		.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
	};
	VkFence fence;
	uint64_t total_errors = 0;
	uint64_t total_fp_errors = 0;
	uint64_t total_int_errors = 0;
	uint32_t first_error_pass = UINT32_MAX;

	(void)bytes_in;
	if (argc != 5) {
		fprintf(stderr, "usage: %s shader.spv elements passes iters\n", argv[0]);
		return 2;
	}

	spv_path = argv[1];
	n = (uint32_t)strtoul(argv[2], NULL, 0);
	passes = (uint32_t)strtoul(argv[3], NULL, 0);
	iters = (uint32_t)strtoul(argv[4], NULL, 0);
	if (!n || !passes || !iters || (n % LOCAL_SIZE) != 0) {
		fprintf(stderr, "invalid elements/passes/iters\n");
		return 2;
	}

	const VkDeviceSize bytes = (VkDeviceSize)n * sizeof(uint32_t);

	CHECK(vkCreateInstance(&ici, NULL, &instance));
	CHECK(vkEnumeratePhysicalDevices(instance, &pd_count, pds));
	for (uint32_t i = 0; i < pd_count; ++i) {
		vkGetPhysicalDeviceProperties(pds[i], &pd_props);
		if (pd_props.vendorID == 0x1002 && strstr(pd_props.deviceName, "BC-250")) {
			pd = pds[i];
			break;
		}
	}
	if (pd == VK_NULL_HANDLE) {
		for (uint32_t i = 0; i < pd_count; ++i) {
			vkGetPhysicalDeviceProperties(pds[i], &pd_props);
			if (pd_props.vendorID == 0x1002) {
				pd = pds[i];
				break;
			}
		}
	}
	if (pd == VK_NULL_HANDLE) {
		fprintf(stderr, "AMD Vulkan device not found\n");
		return 1;
	}

	vkGetPhysicalDeviceProperties(pd, &pd_props);
	vkGetPhysicalDeviceQueueFamilyProperties(pd, &qcount, qprops);
	for (uint32_t i = 0; i < qcount; ++i) {
		if (qprops[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
			queue_family = i;
			break;
		}
	}
	if (queue_family == UINT32_MAX) {
		fprintf(stderr, "compute queue not found\n");
		return 1;
	}

	qci.queueFamilyIndex = queue_family;
	CHECK(vkCreateDevice(pd, &dci, NULL, &dev));
	vkGetDeviceQueue(dev, queue_family, 0, &queue);

	for (uint32_t i = 0; i < 4; ++i) {
		VkBufferCreateInfo bci = {
			.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
			.size = bytes,
			.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
			.sharingMode = VK_SHARING_MODE_EXCLUSIVE,
		};
		VkMemoryRequirements req;
		VkMemoryAllocateInfo mai = {
			.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		};
		uint32_t mem_type;

		CHECK(vkCreateBuffer(dev, &bci, NULL, &buffers[i]));
		vkGetBufferMemoryRequirements(dev, buffers[i], &req);
		mem_type = find_memory_type(pd, req.memoryTypeBits,
					    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
					    VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
		if (mem_type == UINT32_MAX) {
			fprintf(stderr, "host visible coherent memory not found\n");
			return 1;
		}
		mai.allocationSize = req.size;
		mai.memoryTypeIndex = mem_type;
		CHECK(vkAllocateMemory(dev, &mai, NULL, &memories[i]));
		CHECK(vkBindBufferMemory(dev, buffers[i], memories[i], 0));
		CHECK(vkMapMemory(dev, memories[i], 0, bytes, 0, &maps[i]));
	}

	for (uint32_t i = 0; i < n; ++i) {
		((uint32_t *)maps[0])[i] = i * 17u + 3u;
		((uint32_t *)maps[1])[i] = rotl32(i ^ 0x9e3779b9u, i & 31u) + 0x85ebca6bu;
		((uint32_t *)maps[2])[i] = 0;
		((uint32_t *)maps[3])[i] = 0;
	}

	for (uint32_t i = 0; i < 4; ++i) {
		bindings[i].binding = i;
		bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
		bindings[i].descriptorCount = 1;
		bindings[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
		bindings[i].pImmutableSamplers = NULL;
	}
	CHECK(vkCreateDescriptorSetLayout(dev, &dsli, NULL, &dsl));
	CHECK(vkCreatePipelineLayout(dev, &plci, NULL, &pipeline_layout));
	if (read_file(spv_path, &spv, &spv_size)) {
		fprintf(stderr, "failed to read SPIR-V shader: %s\n", spv_path);
		return 1;
	}
	smci.codeSize = spv_size;
	smci.pCode = (const uint32_t *)spv;
	CHECK(vkCreateShaderModule(dev, &smci, NULL, &shader));
	cpci.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
	cpci.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
	cpci.stage.module = shader;
	cpci.stage.pName = "main";
	cpci.layout = pipeline_layout;
	CHECK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipeline));

	CHECK(vkCreateDescriptorPool(dev, &dpci, NULL, &pool));
	dsai.descriptorPool = pool;
	dsai.pSetLayouts = &dsl;
	CHECK(vkAllocateDescriptorSets(dev, &dsai, &ds));
	for (uint32_t i = 0; i < 4; ++i) {
		VkDescriptorBufferInfo dbi = {
			.buffer = buffers[i],
			.offset = 0,
			.range = bytes,
		};
		VkWriteDescriptorSet wds = {
			.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
			.dstSet = ds,
			.dstBinding = i,
			.descriptorCount = 1,
			.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
			.pBufferInfo = &dbi,
		};
		vkUpdateDescriptorSets(dev, 1, &wds, 0, NULL);
	}

	cmdp_ci.queueFamilyIndex = queue_family;
	CHECK(vkCreateCommandPool(dev, &cmdp_ci, NULL, &cmd_pool));
	CHECK(vkCreateFence(dev, &fci, NULL, &fence));

	printf("device=%s queue_family=%u elements=%u passes=%u iters=%u\n",
	       pd_props.deviceName, queue_family, n, passes, iters);

	for (uint32_t pass = 0; pass < passes; ++pass) {
		VkCommandBufferAllocateInfo cbai = {
			.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
			.commandPool = cmd_pool,
			.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
			.commandBufferCount = 1,
		};
		VkCommandBuffer cmd;
		VkCommandBufferBeginInfo cbbi = {
			.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
		};
		struct params p = {
			.n = n,
			.seed = 0xa5a5a5a5u ^ pass * 0x12345u,
			.pass = pass,
			.iters = iters,
		};
		uint64_t pass_errors = 0;
		uint64_t pass_fp_errors = 0;
		uint64_t pass_int_errors = 0;
		double t0;
		double t1;

		memset(maps[2], 0, (size_t)bytes);
		memset(maps[3], 0, (size_t)bytes);

		CHECK(vkAllocateCommandBuffers(dev, &cbai, &cmd));
		CHECK(vkBeginCommandBuffer(cmd, &cbbi));
		vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
		vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout,
					0, 1, &ds, 0, NULL);
		vkCmdPushConstants(cmd, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT,
				   0, sizeof(p), &p);
		vkCmdDispatch(cmd, n / LOCAL_SIZE, 1, 1);
		CHECK(vkEndCommandBuffer(cmd));

		{
			VkSubmitInfo si = {
				.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
				.commandBufferCount = 1,
				.pCommandBuffers = &cmd,
			};
			t0 = now_sec();
			CHECK(vkQueueSubmit(queue, 1, &si, fence));
			CHECK(vkWaitForFences(dev, 1, &fence, VK_TRUE, UINT64_MAX));
			t1 = now_sec();
			CHECK(vkResetFences(dev, 1, &fence));
		}

		for (uint32_t base = 0; base < n; base += LOCAL_SIZE) {
			uint32_t x[LOCAL_SIZE];
			uint32_t y[LOCAL_SIZE];
			uint32_t fp[LOCAL_SIZE];
			uint32_t lds[LOCAL_SIZE];

			for (uint32_t lane = 0; lane < LOCAL_SIZE; ++lane) {
				uint32_t idx = base + lane;
				pre_lds_expected(idx, maps[0], maps[1], &p,
						 &x[lane], &y[lane], &fp[lane]);
				lds[lane] = x[lane] ^ y[lane] ^ p.seed;
			}

			for (uint32_t lane = 0; lane < LOCAL_SIZE; ++lane) {
				uint32_t idx = base + lane;
				uint32_t want_int;
				uint32_t got_int = ((uint32_t *)maps[2])[idx];
				uint32_t got_fp = ((uint32_t *)maps[3])[idx];

				final_expected(idx, lds, x[lane], y[lane], &p, &want_int);
				if (got_int != want_int) {
					if (pass_errors < 16) {
						fprintf(stderr,
							"int mismatch pass=%u idx=%u got=0x%08x want=0x%08x\n",
							pass, idx, got_int, want_int);
					}
					pass_errors++;
					pass_int_errors++;
				}
				{
					uint32_t ulp_diff = fp32_ulp_distance(got_fp, fp[lane]);

					if (ulp_diff > (p.iters / 3 + 2)) {
						if (pass_errors < 16) {
							fprintf(stderr,
								"fp mismatch pass=%u idx=%u got=0x%08x want=0x%08x ulp=%" PRIu32 "\n",
								pass, idx, got_fp, fp[lane], ulp_diff);
						}
						pass_errors++;
						pass_fp_errors++;
					}
				}
			}
		}

		printf("pass=%u dispatch_sec=%.6f errors=%" PRIu64 " int_errors=%" PRIu64 " fp_errors=%" PRIu64 "\n",
		       pass, t1 - t0, pass_errors, pass_int_errors, pass_fp_errors);

		if (pass_errors && first_error_pass == UINT32_MAX)
			first_error_pass = pass;
		total_errors += pass_errors;
		total_int_errors += pass_int_errors;
		total_fp_errors += pass_fp_errors;
		vkFreeCommandBuffers(dev, cmd_pool, 1, &cmd);
	}

	printf("summary elements=%u passes=%u total_checked=%" PRIu64 " errors=%" PRIu64 " int_errors=%" PRIu64 " fp_errors=%" PRIu64 "\n",
	       n, passes, (uint64_t)n * passes * 2u, total_errors,
	       total_int_errors, total_fp_errors);

	if (first_error_pass != UINT32_MAX)
		printf("first_error_pass=%u\n", first_error_pass);

	vkDestroyFence(dev, fence, NULL);
	vkDestroyCommandPool(dev, cmd_pool, NULL);
	vkDestroyDescriptorPool(dev, pool, NULL);
	vkDestroyPipeline(dev, pipeline, NULL);
	vkDestroyShaderModule(dev, shader, NULL);
	vkDestroyPipelineLayout(dev, pipeline_layout, NULL);
	vkDestroyDescriptorSetLayout(dev, dsl, NULL);
	for (uint32_t i = 0; i < 4; ++i) {
		vkUnmapMemory(dev, memories[i]);
		vkFreeMemory(dev, memories[i], NULL);
		vkDestroyBuffer(dev, buffers[i], NULL);
	}
	vkDestroyDevice(dev, NULL);
	vkDestroyInstance(instance, NULL);
	free(spv);

	return total_errors ? 2 : 0;
}
C

echo "Compiling compute verifier..."
glslangValidator -V "$TMPDIR/bc250_compute_verify.comp" -o "$TMPDIR/bc250_compute_verify.spv" >/dev/null
gcc -std=c11 -O2 -Wall -Wextra -o "$TMPDIR/bc250_compute_verify" \
	"$TMPDIR/bc250_compute_verify.c" -lvulkan -lm

echo "Running BC-250 compute verifier..."
"$TMPDIR/bc250_compute_verify" "$TMPDIR/bc250_compute_verify.spv" "$ELEMENTS" "$PASSES" "$ITERS"
