docker build \
--build-arg="EXTRA_BAZEL_ARGS=--local_resources 3072,1.0,1.0 --host_javabase=@local_jdk//:jdk" \
--build-arg="VERSION=0.26.1" \
--build-arg="TENSORFLOW_VERSION=2.0.0" \
-t local/alpine-py3-tensorflow-jupyter:2.0.0 .