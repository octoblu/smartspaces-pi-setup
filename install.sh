#!/bin/bash

SCRIPT_NAME='install'

assert_required_params() {
  local example_arg="$1"

  if [ -n "$example_arg" ]; then
    return 0
  fi

  usage

  if [ -z "$example_arg" ]; then
    echo "Missing example_arg argument"
  fi

  exit 1
}

debug() {
  local cyan='\033[0;36m'
  local no_color='\033[0;0m'
  local message="$@"
  matches_debug || return 0
  (>&2 echo -e "[${cyan}${SCRIPT_NAME}${no_color}]: $message")
}

err_echo() {
  echo "$@" 1>&2
}

fatal() {
  err_echo "$@"
  exit 1
}

matches_debug() {
  if [ -z "$DEBUG" ]; then
    return 1
  fi
  # shellcheck disable=2053
  if [[ $SCRIPT_NAME == $DEBUG ]]; then
    return 0
  fi
  return 1
}

script_directory(){
  local source="${BASH_SOURCE[0]}"
  local dir=""

  while [ -h "$source" ]; do # resolve $source until the file is no longer a symlink
    dir="$( cd -P "$( dirname "$source" )" && pwd )"
    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source" # if $source was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  done

  dir="$( cd -P "$( dirname "$source" )" && pwd )"

  echo "$dir"
}

usage(){
  echo "USAGE: ${SCRIPT_NAME}"
  echo ''
  echo 'Description: ...'
  echo ''
  echo 'Arguments:'
  echo '  -h, --help       print this help text'
  echo '  -v, --version    print the version'
  echo ''
  echo 'Environment:'
  echo '  DEBUG            print debug output'
  echo ''
}

version(){
  local directory
  directory="$(script_directory)"

  if [ -f "$directory/VERSION" ]; then
    cat "$directory/VERSION"
  else
    echo "unknown-version"
  fi
}

add_apt_key() {
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 445C1350
}

add_apt_repository() {
  # && apt-get install -y software-properties-common apt-transport-https \
  # && add-apt-repository -y 'deb https://meshblu-connector.octoblu.com/apt/ stable main' \
  apt-get update && apt-get install -y apt-transport-https || return 1
  grep 'https://meshblu-connector.octoblu.com/apt/' /etc/apt/sources.list && return 0

  echo 'deb https://meshblu-connector.octoblu.com/apt/ stable main' >> /etc/apt/sources.list \
  && apt-get update
}

install_connectors() {
  env MESHBLU_CONNECTOR_PM2_USERNAME=pi apt-get install \
    -y \
    meshblu-connector-pm2 \
    meshblu-connector-configurator-pi-http \
    meshblu-connector-powermate \
    meshblu-connector-left-right-http \
    wmctrl \
    xdotool
}

restart_connectors() {
  systemctl stop meshblu-connector-pm2 && systemctl start meshblu-connector-pm2
}

main() {
  # Define args up here
  while [ "$1" != "" ]; do
    local param value
    param="$1"
    # shellcheck disable=2034
    value="$2"

    case "$param" in
      -h | --help)
        usage
        exit 0
        ;;
      -v | --version)
        version
        exit 0
        ;;
      # Arg with value
      # -x | --example)
      #   example="$value"
      #   shift
      #   ;;
      # Arg without value
      # -e | --example-flag)
      #   example_flag='true'
      #   ;;
      *)
        if [ "${param::1}" == '-' ]; then
          echo "ERROR: unknown parameter \"$param\""
          usage
          exit 1
        fi
        # Set main arguments
        # if [ -z "$main_arg" ]; then
        #   main_arg="$param"
        # elif [ -z "$main_arg_2"]; then
        #   main_arg_2="$param"
        # fi
        ;;
    esac
    shift
  done

  # assert_required_params "$example_arg"
  add_apt_key \
  && add_apt_repository \
  && install_connectors \
  && restart_connectors
}

main "$@"
