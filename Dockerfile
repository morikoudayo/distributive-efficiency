FROM nvidia/cuda:12.9.1-devel-ubuntu24.04 AS builder

RUN apt update
RUN apt install -y git cmake build-essential libcurl4-openssl-dev

WORKDIR /workspace

RUN git clone https://github.com/ggerganov/llama.cpp.git

WORKDIR /workspace/llama.cpp

RUN cmake -B build \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_CUDA=ON \
    -DLLAMA_CUDA_F16=ON \
    -DCMAKE_CUDA_ARCHITECTURES="61" \
    -DCMAKE_C_FLAGS="-march=znver3 -mtune=znver3 -mfma -mavx2 -mf16c -O3" \
    -DCMAKE_CXX_FLAGS="-march=znver3 -mtune=znver3 -mfma -mavx2 -mf16c -O3" \
    -DCMAKE_BUILD_TYPE=Release

RUN cmake --build build --config Release -j 8

FROM nvidia/cuda:12.9.1-runtime-ubuntu24.04

RUN apt update
RUN apt install -y libgomp1 libcurl4-openssl-dev

COPY --from=builder /workspace/llama.cpp/build/bin/* /usr/local/bin/

RUN mkdir /models