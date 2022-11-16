#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Load environment variables
source $SCRIPT_DIR/loadEnv.sh

# Uncomment when doing gas optimizations - for now, more trouble than it's worth
# forge snapshot --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUMBER "$@" >/dev/null && \
forge test --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUMBER "$@" --use $COMPILER_VERSION
