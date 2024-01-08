FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y build-essential libnuma-dev git && \
    rm -rf /var/lib/apt/lists/*

RUN git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git && \
    cd rt-tests && \
    git checkout v2.6 && \
    make all && \
    make install
   
ENTRYPOINT ["cyclictest"]
