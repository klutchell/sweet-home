ARG USER=me
ARG UID=1000

FROM nixos/nix as nix

RUN mkdir -p /output/store && \
    nix-env --profile /output/profile --option filter-syscalls false -i home-manager nix && \
    cp -va $(nix-store -qR /output/profile) /output/store

FROM alpine

ARG USER
ARG UID

# Depending on how you build docker complains about
# copying over /usr/local so remove it as the files
# will be copied from the first stage
RUN rm -rf /usr/local

# Copy nix dependencies
COPY --from=nix --chown=${UID} /output/store /nix/store
COPY --from=nix /output/profile/ /usr/local/

# Copy the version to be loaded as an env var
COPY VERSION /etc/version

# Install minimal tools and create user
RUN apk --update add --no-cache sudo tini iputils git tzdata procps openssh-server && \
    adduser -D -s /bin/bash -u $UID $USER && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers && \
    chmod 0440 /etc/sudoers && \
    chown ${USER} /nix && \
    # Configure sshd for non root usage \ 
    sed -i '/^#PasswordAuthentication/c\PasswordAuthentication no' /etc/ssh/sshd_config && \
    sed -i '/^#PidFile/c\PidFile \/tmp\/sshd.pid' /etc/ssh/sshd_config && \
    sed -i 's/^#HostKey \/etc\/ssh/HostKey ~\/.config\/etc\/ssh/' /etc/ssh/sshd_config && \
    # Create env file an symlinks for bash an zsh
    echo "export SWEET_HOME_VERSION=$(cat </etc/version)" > /etc/env && \
    ln -s /etc/env /etc/zshenv && \
    ln -s /etc/env /etc/bashrc

USER ${UID}

# Set environment variables
ENV USER ${USER}
ENV HOME /home/${USER}

# These variables are usually set from /etc/profile but
# we want them there for all shells
ENV LANG=C.UTF-8
ENV CHARSET=UTF-8
ENV TERM=xterm-256color

# Nix variables
ENV NIX_PATH="${HOME}/.nix-defexpr/channels"
ENV NIX_PROFILES="/nix/var/nix/profiles/default ${HOME}/.nix-profile"
ENV NIX_SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
ENV MANPATH="$HOME/.nix-profile/share/man:$MANPATH"
ENV PATH="$HOME/.nix-profile/bin:$PATH"

# Setup ash to use variables in /etc/env
ENV ENV="/etc/env" 

# Add nixpath channel but don't update it yet.
# The update and install of default packages will happen on
# the entrypoint
RUN mkdir -p ${HOME}/.config/nixpkgs && \
    nix-channel --add https://nixos.org/channels/nixpkgs-unstable

# Copy local files
COPY --chown=${UID} home.nix ${HOME}/.config/nixpkgs/
COPY entry.sh /usr/local/bin/
COPY welcome.txt /etc/motd

# Add fake bash for those tools that require it
COPY bash.stub /bin/bash

ENTRYPOINT ["tini", "--", "entry.sh"]

WORKDIR $HOME
VOLUME $HOME

