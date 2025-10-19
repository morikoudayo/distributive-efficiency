# Use bash instead of sh
SHELL := /bin/bash

# Docker image & model path
IMAGE = llm
MODEL_PATH = $(HOME)/models
MODEL_FILE = GLM-4.5-Air-UD-Q3_K_XL-00001-of-00002.gguf
MODEL_URL = https://huggingface.co/unsloth/GLM-4.5-Air-GGUF/resolve/main/Q3_K_M/GLM-4.5-Air-Q3_K_M-00001-of-00002.gguf
DOCKER_RUN = docker run --gpus all --cap-add=IPC_LOCK --ulimit memlock=-1:-1 --rm -v $(MODEL_PATH):/models $(IMAGE) bash -c

# ----------------------------------------
# Docker Build
# ----------------------------------------

# Build Docker image
build:
	docker build -t $(IMAGE) .

# Download model
download-model:
	@mkdir -p $(MODEL_PATH)
	wget $(MODEL_URL) -O $(MODEL_PATH)/$(MODEL_FILE)

# 共通実行コマンド
RUN_CMD = llama-cli -m /models/$(MODEL_FILE) -p '$(PROMPT)' --temp 0.0 --mlock --no-mmap --ctx-size 512
PROMPT = A is taller than B, and C is shorter than B. Who is the tallest?

# ----------------------------------------
# Cases
# ----------------------------------------

# Case A: テンソル種別ベースのオフロード（Attention層 GPU, FFN層 CPU, その他の層 CPU）
case-a:
	$(DOCKER_RUN) "$(RUN_CMD) -ngl 0 \
		--override-tensor 'blk\.[0-9]+\.ffn_.*=CPU' \
		--override-tensor 'blk\.[0-9]+\.attn_.*=CUDA0'"

# Case B: テンソル種別ベースのオフロード（Attention層 GPU, FFN層 CPU, その他の層 GPU）
case-b:
	$(DOCKER_RUN) "$(RUN_CMD) \
		--override-tensor 'blk\.[0-9]+\.ffn_.*=CPU' \
		--override-tensor 'blk\.[0-9]+\.attn_.*=CUDA0'"

# Case C: テンソル種別ベースのオフロード（Attention層 と 先頭から27層のFFN層 GPU, 余りのFFN層とpost_ffw層・post_attention層はすべてCPU）
case-c:
	$(DOCKER_RUN) "$(RUN_CMD) \
		--override-tensor 'blk\.([0-9]|1[0-9]|2[0-7])\.ffn_.*=CUDA0' \
		--override-tensor 'blk\.(2[8-9]|[3-6][0-9])\.ffn_.*=CPU' \
		--override-tensor 'blk\.[0-9]+\.(post_ffw_.*|post_attention_.*)=CPU' \
		--override-tensor 'blk\.[0-9]+\.attn_.*=CUDA0'"

# Case D: テンソル種別ベースのオフロード（Attention層 と 先頭から27層のFFN層とpost_ffw層・post_attention層はすべてGPU, 余りのFFN層はCPU）
case-d:
	$(DOCKER_RUN) "$(RUN_CMD) \
		--override-tensor 'blk\.([0-9]|1[0-9]|2[0-7])\.ffn_.*=CUDA0' \
		--override-tensor 'blk\.(2[8-9]|[3-6][0-9])\.ffn_.*=CPU' \
		--override-tensor 'blk\.[0-9]+\.(post_ffw_.*|post_attention_.*)=CUDA0' \
		--override-tensor 'blk\.[0-9]+\.attn_.*=CUDA0'"

# Case E: テンソル種別ベースのオフロード（Attention層 と 先頭から27層のFFN層、先頭から27層のPOST_FFW、先頭から27層のPOST_ATTENTION層 GPU, 余りのFFN、POST_FFW、POST_ATTENTION層 CPU）
case-e:
	$(DOCKER_RUN) "$(RUN_CMD) \
		--override-tensor 'blk\.([0-9]|1[0-9]|2[0-7])\.(ffn_.*|post_ffw_.*|post_attention_.*)=CUDA0' \
		--override-tensor 'blk\.(2[8-9]|[3-6][0-9])\.(ffn_.*|post_ffw_.*|post_attention_.*)=CPU' \
		--override-tensor 'blk\.[0-9]+\.attn_.*=CUDA0'"

# Case F: テンソル種別ベースのオフロード（Attention層 と 先頭から28層のFFN層、先頭から28層のPOST_FFW、先頭から28層のPOST_ATTENTION層 GPU, 余りのFFN、POST_FFW、POST_ATTENTION層 CPU）
case-f:
	$(DOCKER_RUN) "$(RUN_CMD) \
		--override-tensor 'blk\.([0-9]|1[0-9]|2[0-8])\.(ffn_.*|post_ffw_.*|post_attention_.*)=CUDA0' \
		--override-tensor 'blk\.(29|[3-6][0-9])\.(ffn_.*|post_ffw_.*|post_attention_.*)=CPU' \
		--override-tensor 'blk\.[0-9]+\.attn_.*=CUDA0'"

# Case G: 層数ベースのオフロード
case-g:
	$(DOCKER_RUN) "$(RUN_CMD) -ngl 34"

# Case X: テンソル種別ベースのオフロード（Attention層 と 先頭から27層のFFN層とpost_ffw層・post_attention層はすべてGPU, 余りのFFN層はCPU）
case-x:
	$(DOCKER_RUN) "$(RUN_CMD) \
		--override-tensor 'blk\.([0-9]|1[0-9]|2[0-8])\.ffn_.*=CUDA0' \
		--override-tensor 'blk\.(29|[3-6][0-9])\.ffn_.*=CPU' \
		--override-tensor 'blk\.[0-9]+\.attn_.*=CUDA0'"

# Case Y: テンソル種別ベースのオフロード（Attention層 と 先頭から27層のFFN層とpost_ffw層・post_attention層はすべてGPU, 余りのFFN層はCPU）
case-y:
	$(DOCKER_RUN) "$(RUN_CMD) \
		--override-tensor 'blk\.[7-9]\.ffn_.*=CPU' \
		--override-tensor 'blk\.([1-6][0-9])\.ffn_.*=CPU'"

# ----------------------------------------
# Benchmark Configuration
# ----------------------------------------
CASES ?= case-x
RUNS ?= 10
BENCHMARK_LOG = benchmark.log

# Spinner animation characters (used in shell scripts)
SPINNER_CHARS = /-\\|

# AWK script to extract eval speed from output
define EXTRACT_SPEED
/eval time.*tokens per second\)$$/ && !/prompt eval/ { \
	match($$0, /([0-9]+\.[0-9]+) tokens per second\)$$/, arr); \
	if (arr[1]) printf "%.2f tok/s", arr[1]; \
	exit; \
}
endef

# AWK script to calculate average speed for a case
define CALC_AVERAGE
BEGIN { in_section = 0; skip_next = 0; sum = 0; count = 0; } \
$$0 ~ case_name " RESULTS" { in_section = 1; skip_next = 1; next; } \
skip_next { skip_next = 0; next; } \
in_section && /^========================================$$/ { in_section = 0; next; } \
in_section && /eval time.*tokens per second\)$$/ && !/prompt eval/ { \
	match($$0, /([0-9]+\.[0-9]+) tokens per second\)$$/, arr); \
	if (arr[1]) { sum += arr[1]; count++; } \
} \
END { if (count > 0) printf "%-15s | %15.2f\n", case_display, sum/count; }
endef

# Benchmark: Run specified cases multiple times and collect performance metrics
# Usage: make benchmark CASES="case-a case-b case-c" RUNS=10
benchmark:
	@echo "========================================" > $(BENCHMARK_LOG)
	@echo "Performance Benchmark Full Log" >> $(BENCHMARK_LOG)
	@echo "Date: $$(date)" >> $(BENCHMARK_LOG)
	@echo "Cases: $(CASES)" >> $(BENCHMARK_LOG)
	@echo "Runs per case: $(RUNS)" >> $(BENCHMARK_LOG)
	@echo "========================================" >> $(BENCHMARK_LOG)
	@echo ""
	@echo "========================================"
	@echo "Benchmark Configuration"
	@echo "========================================"
	@echo "Cases: $(CASES)"
	@echo "Runs per case: $(RUNS)"
	@echo "========================================"
	@echo ""
	@for case in $(CASES); do \
		case_upper=$$(echo $$case | tr 'a-z-' 'A-Z_'); \
		echo ""; \
		echo "========================================"; \
		echo "Starting benchmark: $$case ($(RUNS) runs)"; \
		echo "========================================"; \
		echo "" >> $(BENCHMARK_LOG); \
		echo "========================================" >> $(BENCHMARK_LOG); \
		echo "$$case_upper RESULTS ($(RUNS) runs)" >> $(BENCHMARK_LOG); \
		echo "========================================" >> $(BENCHMARK_LOG); \
		for i in $$(seq 1 $(RUNS)); do \
			echo "" >> $(BENCHMARK_LOG); \
			echo "----------------------------------------" >> $(BENCHMARK_LOG); \
			echo "$$case: Run $$i/$(RUNS)" >> $(BENCHMARK_LOG); \
			echo "----------------------------------------" >> $(BENCHMARK_LOG); \
			tmpfile=$$(mktemp); \
			logfile=$$(mktemp); \
			( \
				$(MAKE) $$case 2>&1 | tee -a $(BENCHMARK_LOG) | tee $$tmpfile > /dev/null; \
				echo "DONE" > $$logfile; \
			) & \
			make_pid=$$!; \
			spinner_idx=0; \
			spinner_chars="$(SPINNER_CHARS)"; \
			while [ ! -f $$logfile ] || [ "$$(cat $$logfile 2>/dev/null)" != "DONE" ]; do \
				char=$${spinner_chars:$$spinner_idx:1}; \
				printf "\r[$$case] Run $$i/$(RUNS) - $$char"; \
				spinner_idx=$$(( (spinner_idx + 1) % 4 )); \
				sleep 0.1; \
			done; \
			wait $$make_pid 2>/dev/null || true; \
			result=$$(awk '$(EXTRACT_SPEED)' $$tmpfile); \
			rm -f $$tmpfile $$logfile; \
			printf "\r[$$case] Run $$i/$(RUNS) - ✓ $$result\n"; \
		done; \
	done
	@echo ""
	@echo "========================================" >> $(BENCHMARK_LOG)
	@echo "Benchmark completed!" >> $(BENCHMARK_LOG)
	@echo "========================================" >> $(BENCHMARK_LOG)
	@echo ""
	@echo "========================================"
	@echo "Performance Summary"
	@echo "========================================"
	@printf "%-15s | %s\n" "Case" "Speed (tok/s)"
	@echo "========================================"
	@for case in $(CASES); do \
		case_upper=$$(echo $$case | tr 'a-z-' 'A-Z_'); \
		awk -v case_name="$$case_upper" -v case_display="$$case" '$(CALC_AVERAGE)' $(BENCHMARK_LOG); \
	done
	@echo "========================================"
	@echo ""
	@echo "Full log: $(BENCHMARK_LOG)"
	@echo ""

# ----------------------------------------
# Utility
# ----------------------------------------

.PHONY: build download-model case-a case-b case-c case-d case-e case-f case-g case-x case-y benchmark
