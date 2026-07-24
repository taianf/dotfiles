FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl build-essential pkg-config libssl-dev xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

RUN sh <(curl -L https://nixos.org/nix/install) --no-daemon
ENV PATH="/root/.nix-profile/bin:${PATH}"
RUN nix-channel --update && nix-env -iA nixpkgs.nixfmt

RUN pip install --no-cache-dir pre-commit

WORKDIR /src
ENTRYPOINT ["pre-commit", "run", "--all-files"]
