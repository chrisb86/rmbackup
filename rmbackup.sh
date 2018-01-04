#!/usr/bin/env sh

# Remote server backup with rsync and config files
# Based on http://wiki.ubuntuusers.de/Skripte/Backup_mit_RSYNC

# Copyright 2013 Christian Busch
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

# Where to look for config files
CONFLOCATION=/root/bin/rmbackup.d/*.conf

# Give the paths to used tools
SSH="/usr/bin/ssh"; LN="/bin/ln"; ECHO="/bin/echo"; DATE="/bin/date";
MAIL="/usr/bin/mail"; RSYNC="/usr/local/bin/rsync";
LAST="last"; INC="--link-dest=../$LAST"

# Date format for naming the snapshot folders
TODAY=$($DATE +%Y-%m-%d)

# set some rsync parameters
RSYNC_CONF_DEFAULT=(--rsync-path='sudo rsync' --delete --quiet)

LOG=/tank/Backups/rmbackup.log

### Do not edit below this line ###

while [ $# -gt 0 ]; do    # Until we run out of parameters . . .
  if [ $1 = "--backup-mysql" ] || [ $1 = "-m" ]; then
    DOBACKUPMYSQL="true"
  elif [ $1 = "--backup-files" ] || [ $1 = "-f" ]; then
    DOBACKUPFILES="true"
  elif [ $1 = "--cleanup" ] || [ $1 = "-c" ]; then
    CLEANUP="true"
  elif [ $1 = "--verbose" ] || [ $1 = "-v" ]; then
    VERBOSE="true"
  fi
  shift       # Check next set of parameters.
done

# Loop through configs
for f in $CONFLOCATION
do
  # Set some defaults
  SSH_PORT=22
  KEEP=14

  # load config file
  source $f

  # some path fiddeling
  if [ "${TARGET:${#TARGET}-1:1}" != "/" ]; then
    TARGET=$TARGET/
  fi

  if [ "$SSH_USER" ] && [ "$SSH_PORT" ]; then
      S="$SSH -p $SSH_PORT -l $SSH_USER $SSH_ARGS";
  fi

  TARGET=$TARGET$SSH_SERVER/

  ## Create target folder if it doesn't exist
  mkdir -p $TARGET

  if [ "$CLEANUP" == "true" ]; then

    $ECHO $($DATE)" starting cleanup for "$SSH_SERVER" (using config file "$f")" >> $LOG

    find $TARGET -type d \( ! -iname "mysql" ! -iname "last" ! -iname ".*" \) -maxdepth 1 -mtime +$KEEP -exec rm -r '{}' '+'
    find $TARGET/mysql/ -type d -maxdepth 1 -mtime +$KEEP -exec rm -r '{}' '+'
  fi

  if [ "$DOBACKUPFILES" == "true" ]; then

    $ECHO $($DATE)" starting file backup for "$SSH_SERVER" (using config file "$f")" >> $LOG

    # do the backup
    for SOURCE in "${REMOTE_SOURCES[@]}"
    do
      if [ "$S" ] && [ "$SSH_SERVER" ] && [ -z "$TOSSH" ]; then
        if [ "$VERBOSE" == "true" ]; then
          $ECHO "$RSYNC -e \"$S\" -avR \"$SSH_SERVER:$SOURCE\" ${RSYNC_CONF_DEFAULT[@]} ${RSYNC_CONF[@]} $TARGET$TODAY $INC"  >> $LOG
        fi
        $RSYNC -e "$S" -avR "$SSH_SERVER:\"$SOURCE\"" "${RSYNC_CONF_DEFAULT[@]}" "${RSYNC_CONF[@]}" "$TARGET"$TODAY $INC >> $LOG 2>&1 
        if [ $? -ne 0 ]; then
          ERROR=1
        fi 
      fi 
    done

    # move the folders and link "last"
    if ( [ "$S" ] && [ "$SSH_SERVER" ] ) || ( [ -z "$S" ] );  then
      if [ "$VERBOSE" == "true" ]; then
        $ECHO "$LN -nsf $TARGET$TODAY $TARGET$LAST" >> $LOG
      fi
      $LN -nsf "$TARGET"$TODAY "$TARGET"$LAST  >> $LOG 2>&1 
      if [ $? -ne 0 ]; then
        ERROR=1
      fi 
    fi
    $ECHO $($DATE)" finished file backup for "$SSH_SERVER"." >> $LOG
  fi

  # Backup MySQL databases

  if [ "$DOBACKUPMYSQL" == "true" ]; then

    # Check if there's a .my.cnf on the remote server
    HASMYCNF=`$S $SSH_SERVER "test -e ~/.my.cnf && echo 1 || echo 0"`

    # Run mysql backup for all databases if we have a .my.cnf
    if [ ${HASMYCNF} = 1 ]; then

      $ECHO $($DATE)" starting mysql backup for "$SSH_SERVER"." >> $LOG

      # Create the backup target if it doesn't exist
      TARGET="$TARGET/mysql/$TODAY"
      mkdir -p $TARGET

      # Get databases
      DATABASES=$($S $SSH_SERVER mysql -Bse "'show databases;'")

      # dump the compressed databases to target
      for D in $DATABASES;
      do
       if [ "$D" != "information_schema" ] && [ "$D" != "performance_schema" ]; then
        if [ "$VERBOSE" == "true" ]; then
          $ECHO "$S $SSH_SERVER mysqldump $D | gzip -c > $TARGET/$D.sql.gz" >> $LOG
        fi
        $S $SSH_SERVER mysqldump $D | gzip -c > $TARGET/$D.sql.gz
       fi
      done
      
      $ECHO $($DATE)" finished mysql backup for "$SSH_SERVER"." >> $LOG
    else
      $ECHO $($DATE)" Couldn't find .my.cnf on "$SSH_SERVER". Skipping MySQL backup." >> $LOG
    fi
  fi

  # Unset server specific variables
  unset SSH_USER
  unset SSH_SERVER
  unset SSH_PORT
  unset SSH_ARGS
  unset S
  unset REMOTE_SOURCES
  unset TARGET
  unset RSYNC_CONF
  unset DATABASES
  unset D
  unset hasMycnf
  unset MAILREC
  unset ERROR
  unset KEEP

  # send mail if it's configured
  if [ -n "$MAILREC" ]; then
    if [ $ERROR ];then
      $MAIL -s "Error Backup $SSH_SERVER $LOG" $MAILREC < $LOG
    else
      $MAIL -s "Backup $SSH_SERVER $LOG" $MAILREC < $LOG
    fi
  fi
done