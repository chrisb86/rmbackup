#!/usr/bin/env sh

## rmbackup.sh
# Create incremental backups of remote servers with ssh, rsync and config files

# Copyright 2013 Christian Baer
# http://github.com/chrisb86/

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

rmbackup=`basename -- $0`
rmbackup_pid=$$
rmbackup_conf_file="/usr/local/etc/rmbackup.conf"

VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"
log_date_format="%Y-%m-%d %H:%M:%S" # For logging purposses when config file  isn't there

rmbackup_usage_backup="Usage: $rmbackup backup [-f CONFIGFILE] [-vd]"
rmbackup_usage_cleanup="Usage: $rmbackup cleanup [-f CONFIGFILE] [-vd]"

# Show help screen
# Usage: help exitcode
help () {
  echo "Usage: $rmbackup command {params}"
  echo
  echo "backup                Backup all defined hosts."
  echo "  [-f CONFIGFILE]     Backup only specified host."
  echo "  [-v]                Turn on verbose mode."
  echo "  [-d]                Turn on debug mode (includes -v)."
  echo "cleanup               Cleanup old backups."
  echo "  [-f CONFIGFILE]     Cleanup only specified hosts backups."
  echo "  [-v]                Turn on verbose mode."
  echo "  [-d]                Turn on debug mode (includes -v)."
  echo "help                  Show this screen"
  exit $1
}

# Print and log messages when verbose mode is on
# Usage: chat [0|1|2|3] MESSAGE
## 0 = regular output
## 1 = error messages
## 2 = verbose messages
## 3 = debug messages

chat () {
    messagetype=$1
    message=$2
    log=$log_dir/$log_file
    log_date=$(date "+$log_date_format")

    if [ $messagetype = 0 ]; then
      echo "[$log_date] [INFO] $message" | tee -a $log ;
    fi
#
    if [ $messagetype = 1 ]; then
      echo "[$log_date] [ERROR] $message" | tee -a $log ; exit 1;
    fi

    if [ $messagetype = 2 ] && [ "$VERBOSE" = true ]; then
      echo "[$log_date] [INFO] $message" | tee -a $log
    fi

    if [ $messagetype = 3 ] && [ "$DEBUG" = true ]; then
      echo "[$log_date] [DEBUG] $message" | tee -a $log
    fi
}

# Load config file and set default variables
# Usage: init [CONFIGFILE]
init () {

  [ ! -f "$rmbackup_conf_file" ] && chat 1 "Config file $rmbackup_conf_file not found. Exiting."

  . $rmbackup_conf_file

  rmbackup_conf_location="${CONF_LOCATION:-/usr/local/etc/rmbackup.d}"
  rmbackup_pid_file="${PID_FILE:-/var/run/rmbackup.pid}"
  backup_timestamp_format="${BACKUP_TIMESTAMP_FORMAT:-%Y-%m-%d}"
  log_dir="${LOG_DIR:-/var/log}"
  log_file="${LOG_FILE:-rmbackup.log}"
  log_date_format="${LOG_DATE_FORMAT:-%Y-%m-%d %H:%M:%S}"
  backups_dir="$BACKUPS_DIR"
  backups_path_last="${LAST:-last}"
  backups_path_inprog="${INPROG:-inProgress}"
  rsync="${RSYNC_PATH:-/usr/local/bin/rsync}"
  rsync_conf_default="${RSYNC_CONF_DEFAULT:---del --quiet}"
  ssh="${SSH_PATH:-/usr/bin/ssh}"
  remote_privileges_path_default="${REMOTE_PRIVILEGES_PATH:-/usr/local/bin/doas}"
  remote_rsync_path_default="${REMOTE_RSYNC_PATH:-/usr/local/bin/rsync}"
  global_keep="${GLOBAL_KEEP_DAYS:-14}"

  chat 2 "Starting $rmbackup with PID $rmbackup_pid."

  chat 3 "rmbackup: $rmbackup"
  chat 3 "rmbackup_pid: $rmbackup_pid"
  chat 3 "rmbackup_conf_file: $rmbackup_conf_file"
  chat 3 "rmbackup_conf_location: $rmbackup_conf_location"
  chat 3 "rmbackup_pid_file: $rmbackup_pid_file"
  chat 3 "backup_timestamp_format: $backup_timestamp_format"
  chat 3 "log_dir: $log_dir"
  chat 3 "log_file: $log_file"
  chat 3 "log_date_format: $log_date_format"
  chat 3 "backups_dir: $backups_dir"
  chat 3 "backups_path_last: $backups_path_last"
  chat 3 "backups_path_inprog: $backups_path_inprog"
  chat 3 "rsync: $rsync"
  chat 3 "rsync_conf_default: $rsync_conf_default"
  chat 3 "ssh: $ssh"
  chat 3 "remote_privileges_path_default: $remote_privileges_path_default"
  chat 3 "remote_rsync_path_default: $remote_rsync_path_default"
  chat 3 "global_keep :$global_keep"
  chat 3 "VERBOSE: $VERBOSE"
  chat 3 "DEBUG: $DEBUG"

  if [ -z "$backups_dir" ]; then chat 1 "Target directory for backups not set. Please set it in $rmbackup_conf_file!"; fi
}

# Check if script is already running
# Usage: checkpid
checkPID () {

	touch $rmbackup_pid_file

	# Get stored PID from file
	rmbackup_stored_pid=`cat $rmbackup_pid_file`

	# Check if stored PID is in use
	rmbackup_pid_is_running=`ps aux | awk '{print $2}' | grep $rmbackup_stored_pid`

  chat 3 "rmbackup_pid: $rmbackup_pid"
  chat 3 "rmbackup_stored_pid: $rmbackup_stored_pid"
  chat 3 "rmbackup_pid_is_running: $rmbackup_pid_is_running"

	if [ "$rmbackup_pid_is_running" ]; then
		# If stored PID is already in use, skip execution
		chat 1 "Skipping because $rmbackup is running (PID: $rmbackup_stored_pid)."
	else
		# Update PID file
		echo $rmbackup_pid > $rmbackup_pid_file
    chat 0 "Starting work."
	fi
}

# Link the specified directory to $backups_path_last
# Usage: backup_host DIRECTORY
link_last () {
  link_source_dir=$1

  chat 2 "Symlinking $link_source_dir to $backup_target/$backups_path_last."
  chat 3 "ln -nsf $link_source_dir $backup_target/$backups_path_last"
  ln -nsf "$link_source_dir" "$backup_target/$backups_path_last"

  unset link_source_dir
}

# Loads a config file and backups the host
# Usage: backup_host CONFIGFILE
backup_host () {

  config_file=$1

  # Check if config file exists and exit if not.
  if [ ! -f "$1" ] ; then chat 1 "Config file $config_file not found."; fi

  chat 2 "Loading Config file $config_file"
  chat 3 "config_file: $config_file"

  # Load config file
  . $config_file

  ssh_port="${SSH_PORT:-22}"
  privileges="${PRIVILEGES_PATH:-$remote_privileges_path_default}"
  remote_rsync_path="${RSYNC_PATH:-$remote_rsync_path_default}"
  ssh_server="$SSH_SERVER"
  ssh_alias="${SSH_ALIAS:-$SSH_SERVER}"
  ssh_user="$SSH_USER"
  ssh_args="$SSH_ARGS"
  rsync_conf="${rsync_conf_default} ${RSYNC_CONF}"
  backup_target="$backups_dir/$ssh_alias"
  backup_last="$backup_target/$backups_path_last"
  backup_timestamp=$(date "+$backup_timestamp_format")
  remote_sources=${REMOTE_SOURCES}
  latest_backup=`find $backup_target -type d \( ! -iname "$backups_path_inprog" ! -iname "$backups_path_last" ! -iname ".*" \) -maxdepth 1 -print | sort -r | head -n 1`

  chat 3 "ssh_port: $ssh_port"
  chat 3 "privileges $privileges"
  chat 3 "remote_rsync_path: $remote_rsync_path"
  chat 3 "ssh_server: $ssh_server"
  chat 3 "ssh_alias: $ssh_alias"
  chat 3 "ssh_user: $ssh_user"
  chat 3 "ssh_args: $ssh_args"
  chat 3 "rsync_conf: ${rsync_conf}"
  chat 3 "backup_target: $backup_target"
  chat 3 "backup_last: $backup_last"
  chat 3 "backup_target: $backup_target"
  chat 3 "backup_last: $backup_last"
  chat 3 "backup_timestamp: $backup_timestamp"
  chat 3 "remote_sources: ${remote_sources}"
  chat 3 "latest_backup: $latest_backup"

  chat 0 "Starting backup for $ssh_alias (using config file $config_file)"

  ## Prepare the target directory
  if [ ! -d "$backup_target/$backups_path_inprog" ]; then
    chat 2 "Preparing target directory."

    if [ -d "$backup_target/$backup_timestamp" ]; then
      chat 2 "Current backup directory exists. Moving $backup_target/$backup_timestamp to $backup_target/$backups_path_inprog."
      chat 3 "mv $backup_target/$backup_timestamp $backup_target/$backups_path_inprog"
      mv "$backup_target/$backup_timestamp" "$backup_target/$backups_path_inprog"

      link_last "$backup_target/$backups_path_inprog"
    else
      chat 2 "Creating $backup_target/$backups_path_inprog."
      chat 3 "mkdir -p $backup_target/$backups_path_inprog"
      mkdir -p "$backup_target/$backups_path_inprog"
    fi
  else
    chat 2 "Target directory $backup_target/$backups_path_inprog exists"
  fi

  ## Check if $backups_path_last symlink exists in backup folder.
  ## If not, symlink the last complete backup to $backups_path_last
  ## If no backup exists, link $backups_path_inprog to $backups_path_last
  ## Create target folder if it doesn't exist

  if [ ! -L "$backup_target/$backups_path_last" ]; then
    chat 2 "$backup_target/$backups_path_last not found."
    if [ -d "$latest_backup" ]  && [ "$latest_backup" -ne "$backup_target" ]; then
      chat 2 "Latest backup is $latest_backup."
      link_last "$latest_backup"
    else
      chat 2 "Latest backup not found."
      link_last "$backup_target/$backups_path_inprog"
    fi
  fi

  for source in ${remote_sources}
  do
    chat 2 "Backing up $ssh_alias:$source to $backup_target/$backups_path_inprog."
    chat 3 "$rsync -e \"$ssh -p $ssh_port -l $ssh_user $ssh_args\" --link-dest=\"$backup_last\" -aR $ssh_server:$source --rsync-path=$privileges $remote_rsync_path ${rsync_conf} \"$backup_target/$backups_path_inprog\""

    $rsync -e "$ssh -p $ssh_port -l $ssh_user $ssh_args" --link-dest="$backup_last" -aR "$ssh_server:$source" --rsync-path="$privileges $remote_rsync_path" ${rsync_conf} "$backup_target/$backups_path_inprog"
  done

  if [ $? -ne 0 ]; then
    ERROR=1
  #[TODO] Implement error Handling. Mail?
  else
    chat 2 "Finishing backup."

    ## Rename transfer dir to backup_timestamp
    chat 3 "mv $backup_target/$backups_path_inprog $backup_target/$backup_timestamp"
    mv "$backup_target"/"$backups_path_inprog" "$backup_target"/"$backup_timestamp"

    link_last "$backup_target/$backup_timestamp"

    chat 0 "Finished backup for $ssh_alias."

    chat 2 "Cleaning up variables."
    chat 3 "unset ssh_port privileges remote_rsync_path ssh_server ssh_alias ssh_user ssh_args rsync_conf backup_target backup_last backup_timestamp remote_sources latest_backup SSH_PORT PRIVILEGES_PATH RSYNC_PATH SSH_SERVER SSH_ALIAS SSH_USER SSH_ARGS RSYNC_CONF REMOTE_SOURCES ERROR"

    unset ssh_port privileges remote_rsync_path ssh_server ssh_alias ssh_user ssh_args rsync_conf backup_target backup_last backup_timestamp remote_sources latest_backup SSH_PORT PRIVILEGES_PATH RSYNC_PATH SSH_SERVER SSH_ALIAS SSH_USER SSH_ARGS RSYNC_CONF REMOTE_SOURCES ERROR
  fi
}

# Sources a config file and cleans up the backups for this specific host that are older than $keep days
# Usage: backup_host CONFIGFILE
cleanup_host () {

  #[TODO] What if all backups are older than $keep days? Prevent from deleting the last backups!

  config_file=$1

  # Check if config file exists and exit if not.
  if [ ! -f "$1" ] ; then chat 1 "Config file $config_file not found."; fi

  chat 2 "Loading Config file $config_file"
  chat 3 "config_file: $config_file"

  # Load config file
  . $config_file

  ssh_server="$SSH_SERVER"
  ssh_alias="${SSH_ALIAS:-$SSH_SERVER}"
  backup_target="$backups_dir/$ssh_alias"
  keep="${KEEP_DAYS:-$global_keep}"

  chat 3 "ssh_server: $ssh_server"
  chat 3 "ssh_alias: $ssh_alias"
  chat 3 "backup_target: $backup_target"
  chat 3 "keep: $keep"

  chat 2 "Deleting backups in $backup_target that are older than $keep days."
  chat 3 "find $backup_target -type d \( ! -iname \"$backups_path_inprog\" ! -iname \"$backup_last\" ! -iname \".*\" \) -maxdepth 1 -mtime +$keep -exec rm -r '{}' '+'"

  find $backup_target -type d \( ! -iname "$backups_path_inprog" ! -iname "$backup_last" ! -iname ".*" \) -maxdepth 1 -mtime +$keep -exec rm -r '{}' '+'
}

case "$1" in
  ######################## rmbackup.sh HELP ########################
  help)
  help 0
  ;;
  ######################## rmbackup.sh BACKUP ########################
  backup)
  shift; while getopts :f:vd arg; do case ${arg} in
    f) config_file=${OPTARG};;
    v) VERBOSE=true;;
    d) DEBUG=true; VERBOSE=true;;
    ?) init; chat 1 "$rmbackup_usage_backup";;
    :) init; chat 1 "$rmbackup_usage_backup";;
  esac; done; shift $(( ${OPTIND} - 1 ))

  init
  checkPID

  if [ -n "$config_file" ]; then
    backup_host $config_file
  else
    for f in $rmbackup_conf_location/*.conf
    do
      backup_host $f
    done
  fi
  chat 2 "All jobs done. Exiting."
  ;;
  ######################## rmbackup.sh CLEANUP ########################
  cleanup)
  shift; while getopts :f:vd arg; do case ${arg} in
    f) config_file=${OPTARG};;
    v) VERBOSE=true;;
    d) DEBUG=true; VERBOSE=true;;
    ?) init; chat 1 "$rmbackup_usage_cleanup";;
    :) init; chat 1 "$rmbackup_usage_cleanup";;
  esac; done; shift $(( ${OPTIND} - 1 ))

  init
  checkPID

  if [ -n "$config_file" ]; then
    cleanup_host $config_file
  else
    for f in $rmbackup_conf_location/*.conf
    do
      cleanup_host $f
    done
  fi
  chat 2 "All jobs done. Exiting."
  ;;
  *)
  help 1
  ;;
esac
