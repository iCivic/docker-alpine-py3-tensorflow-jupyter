FROM alpine:3.10 as bazel

ARG VERSION
ARG EXTRA_BAZEL_ARGS

ENV BAZEL_VERSION     $VERSION
ENV EXTRA_BAZEL_ARGS  $EXTRA_BAZEL_ARGS
# ENV BAZEL_VERSION 0.26.1
# ENV EXTRA_BAZEL_ARGS="--local_resources 3072,1.0,1.0 --host_javabase=@local_jdk//:jdk"

ENV JAVA_HOME  /usr/lib/jvm/default-jvm
ENV PATH $JAVA_HOME/bin:$PATH
ENV CLASSPATH=.:$JAVA_HOME/lib/tools.jar:$JAVA_HOME/lib/dt.jar 

COPY ./packages/bazel-0.26.1-dist.zip /tmp/bazel-dist.zip

RUN set -x \
    && echo 'http://mirrors.ustc.edu.cn/alpine/v3.10/main' > /etc/apk/repositories \
    && echo 'http://mirrors.ustc.edu.cn/alpine/v3.10/community' >>/etc/apk/repositories \
    && apk update \
    && apk --no-cache add \
        g++ \
        libstdc++ \
        openjdk8 \
    && apk --no-cache add --virtual .builddeps \
        bash \
        build-base \
        linux-headers \
        python3-dev \
        wget \
        zip \
    && mkdir /tmp/bazel \
#    && wget -q -O /tmp/bazel-dist.zip https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-dist.zip \
    && unzip -q -d /tmp/bazel /tmp/bazel-dist.zip \
    && cd /tmp/bazel \
    # add -fpermissive compiler option to avoid compilation failure 
    && sed -i -e '/"-std=c++0x"/{h;s//"-fpermissive"/;x;G}' tools/cpp/cc_configure.bzl \
    # add '#include <sys/stat.h>' to avoid mode_t type error 
    && sed -i -e '/#endif  \/\/ COMPILER_MSVC/{h;s//#else/;G;s//#include <sys\/stat.h>/;G;}' third_party/ijar/common.h \
    && cd /tmp/bazel \
    && ln -s /usr/bin/python3 /usr/bin/python \
    # # add jvm opts for circleci
    # && sed -i -E 's/(jvm_opts.*\[)/\1 "-Xmx1024m",/g' src/java_tools/buildjar/BUILD \
    && bash compile.sh \
    ## install
    && cp output/bazel /usr/local/bin/ \
    ## cleanup 
    && apk del .builddeps \
    && cd / \
    && rm -rf /tmp/bazel*
	
FROM alpine:3.10

ARG TENSORFLOW_VERSION
ENV LOCAL_RESOURCES 2048,.5,1.0
ENV TENSORFLOW_VERSION $TENSORFLOW_VERSION

# Tensorflow[源码安装时bazel行为解析] https://www.cnblogs.com/shouhuxianjian/p/9416934.html
# https://github.com/Docker-Hub-frolvlad/docker-alpine-python3
# https://github.com/smizy/docker-bazel
COPY ./packages/tensorflow-2.0.0.tar.gz /tmp/tensorflow-2.0.0.tar.gz
COPY ./wheelhouse /mnt/wheelhouse
COPY ./conf/pip.conf ~/.pip/pip.conf

COPY --from=bazel /usr/local/bin/bazel  /usr/bin/

RUN set -x \   
    && echo 'http://mirrors.ustc.edu.cn/alpine/v3.10/main' > /etc/apk/repositories \
    && echo 'http://mirrors.ustc.edu.cn/alpine/v3.10/community' >>/etc/apk/repositories \
    && apk update \
    && apk add -U tzdata \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && apk del tzdata

# This hack is widely applied to avoid python printing issues in docker containers.
# See: https://github.com/Docker-Hub-frolvlad/docker-alpine-python3/pull/13
ENV PYTHONUNBUFFERED=1

RUN echo "**** install Python ****" && \
    apk add --no-cache python3 && \
    if [ ! -e /usr/bin/python ]; then ln -sf python3 /usr/bin/python ; fi && \
    \
    echo "**** install pip ****" && \
    python3 -m ensurepip && \
    rm -r /usr/lib/python*/ensurepip && \
    pip3 install --no-cache --upgrade --find-links=/mnt/wheelhouse pip setuptools wheel && \
    if [ ! -e /usr/bin/pip ]; then ln -s pip3 /usr/bin/pip ; fi && \
	python --version && \
	pip --version

RUN apk add --no-cache python3-tkinter py3-numpy py3-numpy-f2py freetype libpng libjpeg-turbo imagemagick graphviz git

RUN apk add --no-cache --virtual=.build-deps \
        bash \
        cmake \
        curl \
        freetype-dev \
        g++ \
        libjpeg-turbo-dev \
        libpng-dev \
        linux-headers \
        make \
        musl-dev \
        openblas-dev \
        openjdk8 \
        patch \
        perl \
        python3-dev \
        py-numpy-dev \
        rsync \
        sed \
        swig \
        zip \
    && : prepare for building TensorFlow \
    && : build TensorFlow pip package \
    && cd /tmp \
    && : curl -SL https://github.com/tensorflow/tensorflow/archive/v${TENSORFLOW_VERSION}.tar.gz | tar xzf - \
	&& tar xzf tensorflow-${TENSORFLOW_VERSION}.tar.gz \
    && cd tensorflow-${TENSORFLOW_VERSION} \
    && : musl-libc does not have "secure_getenv" function \
    && sed -i -e '/JEMALLOC_HAVE_SECURE_GETENV/d' third_party/jemalloc.BUILD \
    && PYTHON_BIN_PATH=/usr/bin/python \
        PYTHON_LIB_PATH=/usr/lib/python3.6/site-packages \
        CC_OPT_FLAGS="-march=native" \
        TF_NEED_JEMALLOC=1 \
        TF_NEED_GCP=0 \
        TF_NEED_HDFS=0 \
        TF_NEED_S3=0 \
        TF_ENABLE_XLA=0 \
        TF_NEED_GDR=0 \
        TF_NEED_VERBS=0 \
        TF_NEED_OPENCL=0 \
        TF_NEED_CUDA=0 \
        TF_NEED_MPI=0 \
        bash configure \
    && bazel build -c opt --local_resources ${LOCAL_RESOURCES} //tensorflow/tools/pip_package:build_pip_package \
    && ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg \
    && : \
    && : install python modules including TensorFlow \
    && cd \
    && pip3 install --no-cache-dir /tmp/tensorflow_pkg/tensorflow-${TENSORFLOW_VERSION}-cp36-cp36m-linux_x86_64.whl \
    && pip3 install --no-cache-dir pandas scipy jupyter \
    && pip3 install --no-cache-dir scikit-learn matplotlib Pillow \
    && pip3 install --no-cache-dir google-api-python-client \
    && : \
    && : clean up unneeded packages and files \
    && apk del .build-deps \
    && rm -f /usr/bin/bazel \
    && rm -rf /tmp/* /root/.cache

# 利用Docker环境配置jupyter notebook服务器 https://blog.csdn.net/eswai/article/details/79437428
RUN mkdir -p /data \
    && jupyter notebook --generate-config --allow-root \
    && sed -i -e "/c\.NotebookApp\.allow_root/a c.NotebookApp.allow_root = True" \
        -e "/c\.NotebookApp\.ip/a c.NotebookApp.ip = '*'" \
		-e "/c\.NotebookApp\.notebook_dir/a c.NotebookApp.notebook_dir = '/data'" \
        -e "/c\.NotebookApp\.open_browser/a c.NotebookApp.open_browser = False" \
            /root/.jupyter/jupyter_notebook_config.py

RUN ipython profile create \
    && sed -i -e "/c\.InteractiveShellApp\.matplotlib/a c.InteractiveShellApp.matplotlib = 'inline'" \
            /root/.ipython/profile_default/ipython_kernel_config.py

ADD init.sh /usr/local/bin/init.sh	
RUN chmod u+x /usr/local/bin/init.sh

EXPOSE 8888
CMD ["/usr/local/bin/init.sh"]
