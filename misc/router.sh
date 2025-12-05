#!/bin/bash

# Get arguments
if ! CLiArguments=$(getopt --options="hu" --name "FLUXION V1.0" -- "$@");then
    echo -e "\033[31mParameter error detected"
    exit 1
fi

eval set -- "$CLiArguments" 

while [ "$1" != "" ] && [ "$1" != "--" ]; do
    case "$1" in
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  -h, --help    Show this help message"
            echo "  -u            Update mode"
            exit 0
            ;;
        -u)
            UPDATE_MODE=1
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done
