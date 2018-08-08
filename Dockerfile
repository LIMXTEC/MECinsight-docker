# Copyright (c) 2018 The MegaCoin MEC Core Developers (dalijolijo)

# Use an official Ubuntu runtime as a parent image
FROM limxtec/crypto-lib-ubuntu:16.04

LABEL maintainer="The MegaCoin MEC Core Developers"

ENV GIT LIMXTEC
USER root
WORKDIR /home
SHELL ["/bin/bash", "-c"]

RUN echo '*** MEC Insight Explorer Docker Solution ***'

# Make ports available to the world outside this container
# Default Port = 7951
# RPC Port = 7952
# Tor Port = 9051
# ZMQ Port = 28332 (Block and Transaction Broadcasting with ZeroMQ)
# API Port = 3001 (Insight Explorer is avaiable at http://yourip:3001/insight and API at http://yourip:3001/insight/api)

# Creating megacoin user
RUN adduser --disabled-password --gecos "" megacoin && \
    usermod -a -G sudo,megacoin megacoin

# Add NodeJS (Version 8) Source
RUN apt-get update && \
    apt-get install -y curl \
                       sudo && \
    curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -

# Running updates and installing required packages
# New version libzmq5-dev needed?
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y build-essential \
                            git \
                            libzmq3-dev \
                            nodejs \
                            supervisor \
                            vim \
                            wget

# Update Package npm to latest version
RUN npm i npm@latest -g

# Installing required packages for compiling
RUN apt-get install -y  apt-utils \
                        autoconf \
                        automake \
                        autotools-dev \
                        build-essential \
                        libboost-all-dev \
                        libevent-dev \
                        libminiupnpc-dev \
                        libssl-dev \
                        libtool \
                        pkg-config \
                        software-properties-common
RUN sudo add-apt-repository ppa:bitcoin/bitcoin
RUN sudo apt-get update && \
    sudo apt-get -y upgrade
RUN apt-get install -y libdb4.8-dev \
                       libdb4.8++-dev

# Cloning MegaCoin Git repository
RUN mkdir -p /home/megacoin/src/ && \
    cd /home/megacoin && \
    git clone https://github.com/LIMXTEC/Megacoin.git

# Compiling MegaCoin Sources
RUN cd /home/megacoin/Megacoin && \
    git checkout addindex && \
    ./autogen.sh && ./configure --disable-dependency-tracking --enable-tests=no --without-gui --disable-hardening && make

# Strip megacoind binary 
RUN cd /home/megacoin/Megacoin/src && \
    strip megacoind && \
    chmod 775 megacoind && \
    cp megacoind /home/megacoin/src/

# Remove source directory 
RUN rm -rf /home/megacoin/Megacoin

# Install bitcore-node-mec
RUN cd /home/megacoin && \
    git clone https://github.com/${GIT}/bitcore-node-mec.git bitcore-livenet && \
    cd /home/megacoin/bitcore-livenet && \
    npm install

ENV MEC_NET "/home/megacoin/bitcore-livenet"

# Create Bitcore Node
# Hint: bitcore-node create -d <bitcoin-data-dir> mynode
RUN cd ${MEC_NET}/bin && \
    chmod 777 bitcore-node && \
    sync && \
    ./bitcore-node create -d ${MEC_NET}/bin/mynode/data mynode

# Install insight-api-mec
RUN cd ${MEC_NET}/bin/mynode/node_modules && \
    git clone https://github.com/${GIT}/insight-api-mec.git && \
    cd ${MEC_NET}/bin/mynode/node_modules/insight-api-mec && \
    npm install

# Install insight-ui-mec
RUN cd ${MEC_NET}/bin/mynode/node_modules && \
    git clone https://github.com/${GIT}/insight-ui-mec.git && \
    cd ${MEC_NET}/bin/mynode/node_modules/insight-ui-mec && \
    npm install

# Install bitcore-message-mec
RUN cd ${MEC_NET}/bin/mynode/node_modules && \
    git clone https://github.com/${GIT}/bitcore-message-mec.git && \
    cd ${MEC_NET}/bin/mynode/node_modules/bitcore-message-mec && \
    npm install save

# Remove duplicate node_module 'bitcore-lib' to prevent startup errors such as:
#   "More than one instance of bitcore-lib found. Please make sure to require bitcore-lib and check that submodules do
#   not also include their own bitcore-lib dependency."
RUN rm -Rf ${MEC_NET}/bin/mynode/node_modules/bitcore-node-mec/node_modules/bitcore-lib-mec && \
    rm -Rf ${MEC_NET}/bin/mynode/node_modules/insight-api-mec/node_modules/bitcore-lib-mec && \
    rm -Rf ${MEC_NET}/bin/mynode/node_modules/bitcore-lib-mec

# Install bitcore-lib-mec (not needed: part of another module)
RUN cd ${MEC_NET}/bin/mynode/node_modules && \
    git clone https://github.com/${GIT}/bitcore-lib-mec.git && \
    cd ${MEC_NET}/bin/mynode/node_modules/bitcore-lib-mec && \
    npm install

# Install bitcore-build-mec
RUN cd ${MEC_NET}/bin/mynode/node_modules && \
    git clone https://github.com/${GIT}/bitcore-build-mec.git && \
    cd ${MEC_NET}/bin/mynode/node_modules/bitcore-build-mec && \
    npm install

# Install bitcore-wallet-service
# See: https://github.com/LIMXTEC/bitcore-wallet-service-joli/blob/master/installation.md
# Reference: https://github.com/m00re/bitcore-docker
# This will launch the BWS service (with default settings) at http://localhost:3232/bws/api.
# BWS needs mongoDB. You can configure the connection at config.js
#RUN cd ${MEC_NET}/bin/mynode/node_modules && \
#    git clone https://github.com/${GIT}/bitcore-wallet-service-joli.git && \
#    cd ${MEC_NET}/bin/mynode/node_modules/bitcore-wallet-service-joli && \
#    npm install
# Configuration needed before start
#RUN npm start
#RUN rm -Rf ${MEC_NET}/bin/mynode/node_modules/bitcore-wallet-service/node_modules/bitcore-lib-mec

# Cleanup
RUN apt-get -y remove --purge build-essential && \
    apt-get -y autoremove && \
    apt-get -y clean

# Copy megacoind to the correct bitcore-livenet/bin/ directory
RUN cp /home/megacoin/src/megacoind ${MEC_NET}/bin/

# Copy JSON bitcore-node.json
COPY bitcore-node.json ${MEC_NET}/bin/mynode/

# Copy Supervisor Configuration
COPY *.sv.conf /etc/supervisor/conf.d/

# Copy start script
COPY start.sh /usr/local/bin/start.sh
RUN rm -f /var/log/access.log && mkfifo -m 0666 /var/log/access.log && \
    chmod 755 /usr/local/bin/*

ENV TERM linux
CMD ["/usr/local/bin/start.sh"]
