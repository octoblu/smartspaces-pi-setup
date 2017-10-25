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
  echo '  -u, --upgrade    removes the old rotator and registers'
  echo '                   workspace hub services as LXDE autostart'
  echo '                   applications instead of using'
  echo '                   /etc/alternatives/x-session-manager'
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
  log "add_apt_key"
  local key_filepath

  key_filepath="$(mktemp)" || return 1

  curl \
    --fail \
    --location \
    --silent \
    --output "$key_filepath" \
    "https://meshblu-connector.octoblu.com/keys/445c1350.pub" || return 1

  apt-key add "$key_filepath"
}

add_apt_repository() {
  log "add_apt_repository"
  apt-get update && apt-get install -y --force-yes -o Dpkg::Options::="--force-confnew" apt-transport-https || return 1
  grep 'https://meshblu-connector.octoblu.com/apt/' /etc/apt/sources.list && return 0

  echo 'deb https://meshblu-connector.octoblu.com/apt/ stable main' >> /etc/apt/sources.list \
  && apt-get update
}

add_env() {
  log "add_env"
  ensure_line "/home/pi/.bashrc" "export MESHBLU_CONNECTOR_PM2_HOME=/var/run/meshblu-connector-pm2"
  ensure_line "/home/pi/.bashrc" "export MESHBLU_CONNECTOR_HOME=/usr/share/meshblu-connectors"

  echo "==================================="
  echo "To get the environment for running "
  echo " meshblu-connector-pm2, you'll want"
  echo " to 'source ~/.bashrc', or log out "
  echo " of the shell and back in again    "
  echo "==================================="
}

ensure_line() {
  local lastchar filename line

  filename="$1"
  line="$2"

  if grep --fixed-strings "$line" "$filename"; then
    return 0
  fi

  # ensure ends in newline
  lastchar=$(tail -c 1 "$filename")
  if [ lastchar != "" ]; then
    echo "" >> "$filename"
  fi

  echo "$line" >> "$filename"
}

set_username() {
  local tmpdir config_filename

  tmpdir="$(mktemp --directory)"
  pushd "$tmpdir" > /dev/null
  apt-get download meshblu-connector-pm2 | return 1
  config_filename="$(2>/dev/null apt-extracttemplates ./meshblu-connector-pm2* | head -n 1 | tr ' ' '\n' | grep '\.config')" || return 1

  chmod +x "$config_filename"
  debconf "$config_filename"
  debconf -omeshblu-connector-pm2 bash -c '. /usr/share/debconf/confmodule && db_set meshblu-connector-pm2/username pi'
  popd > /dev/null
  return
}

install_connectors() {
  log "install_connectors"
  apt-get purge -y \
    genisys-powermate-to-rotator \
    meshblu-connector-bash \
    meshblu-connector-left-right-http \
    meshblu-connector-powermate \
    smartspaces-pi-dashboard \
    azure-connector-citrix-receiver \
    &> /dev/null

  apt-get install -y --force-yes -o Dpkg::Options::="--force-confnew" debconf apt-utils || return 1


  set_username || return 1

  env MESHBLU_CONNECTOR_PM2_USERNAME=pi apt-get install \
      -y \
      --force-yes \
      -o Dpkg::Options::="--force-confnew" \
      meshblu-connector-configurator-pi-http \
      meshblu-connector-pm2 \
      meshblu-connector-websocket-to-meshblu \
      powermate-websocket \
      smartspaces-rotator-dashboard \
      smartspaces-rotator-dashboard-updater \
      azure-connector-citrix-receiver \
      wmctrl \
      xdotool
}

restart_connectors() {
  log "restart_connectors"
  local current_state
  current_state="$(systemctl is-active meshblu-connector-pm2)"

  if [ "$current_state" == "active" ]; then
    (sleep 1 && log "restart meshblu-connector-pm2" & systemctl restart meshblu-connector-pm2) &
    log "waiting 1s to restart meshblu-connector-pm2"
  else
    log "start meshblu-connector-pm2"
    systemctl start meshblu-connector-pm2
  fi
}

setup_bin_iBeacon() {
  local contents=$'#!/bin/bash\n\ncd /opt/Citrix/WorkspaceHub && sudo ./iBeacon.sh\n'
  echo "$contents" > /usr/local/bin/iBeacon \
  && chmod +x /usr/local/bin/iBeacon
}

setup_bin_WorkspaceHubControlService() {
  local contents=$'#!/bin/bash\n\ncd /opt/Citrix/WorkspaceHub && sudo ./WorkspaceHubControlService.sh\n'
  echo "$contents" > /usr/local/bin/WorkspaceHubControlService \
  && chmod +x /usr/local/bin/WorkspaceHubControlService
}

update_autostart() {
  local filename=/home/pi/.config/lxsession/LXDE-pi/autostart

  ensure_line "$filename" '@firefox http://localhost:3000' \
  && ensure_line "$filename" '@iBeacon' \
  && ensure_line "$filename" '@WorkspaceHubControlService'
}

upgrade_hub() {
  local upgrade_hub="$1"
  if [ "$upgrade_hub" != "true" ]; then
    return 0
  fi

  setup_bin_WorkspaceHubControlService \
  && setup_bin_iBeacon \
  && update_autostart \
  && update_x_session_manager
}

update_x_session_manager() {
  ln -nsf /usr/bin/startlxde-pi /etc/alternatives/x-session-manager
}

log() {
  local message="$1"
  local logfile="/var/log/smartspaces-pi-setup/smartspaces-pi-setup.log"

  mkdir -p "$(dirname "$logfile")" \
  && touch "$logfile" \
  && echo "$(date --iso=seconds)" "$message" >> "$logfile"
}

main() {
  local upgrade='false'
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
      -u | --upgrade)
        upgrade='true'
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


  log "pi-setup started" \
  && add_apt_key \
  && add_apt_repository \
  && install_connectors \
  && add_env \
  && restart_connectors \
  && upgrade_hub "$upgrade" \
  && log "pi-setup ended"

  local exit_code=$?

  if [ "$exit_code" != "0" ]; then
    log "failed"
    exit $exit_code
  fi
}

main "$@"
