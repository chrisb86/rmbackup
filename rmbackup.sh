#!/bin/bash

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
CONFLOCATION=/etc/rmbackup.d/*.conf

# Uncomment and add your address if you want to receive the script ouput via e-mail
#MAILREC="jdoe@example.com"

# Give the paths to used tools
SSH="/usr/bin/ssh"; LN="/bin/ln"; ECHO="/bin/echo"; DATE="/bin/date";
MAIL="/usr/bin/mail"; RSYNC="/usr/local/bin/rsync";
LAST="last"; INC="--link-dest=../$LAST"

### Do not edit below this line ###

# Loop through configs configs
for f in $CONFLOCATION
do
  # set some rsync parameters
  RSYNC_CONF_DEFAULT=(--rsync-path='sudo rsync' --delete --quiet)

  # Date format for naming the snapshot folders
  TODAY=$($DATE +%Y-%m-%d)

  # load config file
  source $f
  
  LOG=$0.log
  echo $($DATE)" starting backup for "$SSH_SERVER" (using config file"$f")" >> $LOG

  # some path fiddeling
  if [ "${TARGET:${#TARGET}-1:1}" != "/" ]; then
    TARGET=$TARGET/
  fi

  TARGET=$TARGET$SSH_SERVER/

    if [ "$SSH_USER" ] && [ "$SSH_PORT" ]; then
      S="$SSH -p $SSH_PORT -l $SSH_USER";
    fi

    # do the backup
    for SOURCE in "${REMOTE_SOURCES[@]}"
      do
        if [ "$S" ] && [ "$SSH_SERVER" ] && [ -z "$TOSSH" ]; then
          $ECHO "$RSYNC -e \"$S\" -avR \"$SSH_SERVER:$SOURCE\" ${RSYNC_CONF_DEFAULT[@]} ${RSYNC_CONF[@]} $TARGET$TODAY $INC"  >> $LOG 
          $RSYNC -e "$S" -avR "$SSH_SERVER:\"$SOURCE\"" "${RSYNC_CONF_DEFAULT[@]}" "${RSYNC_CONF[@]}" "$TARGET"$TODAY $INC >> $LOG 2>&1 
          if [ $? -ne 0 ]; then
            ERROR=1
          fi 
        fi 
    done

    # move the folders and link "last"
    if ( [ "$S" ] && [ "$SSH_SERVER" ] && [ -z "$TOSSH" ] ) || ( [ -z "$S" ] );  then
      $ECHO "$LN -nsf $TARGET$TODAY $TARGET$LAST" >> $LOG
      $LN -nsf "$TARGET"$TODAY "$TARGET"$LAST  >> $LOG 2>&1 
      if [ $? -ne 0 ]; then
        ERROR=1
      fi 
    fi
  echo $($DATE)" finished backup for "$SSH_SERVER"." >> $LOG

  # send mail if it's configured
  if [ -n "$MAILREC" ]; then
    if [ $ERROR ];then
      $MAIL -s "Error Backup $LOG" $MAILREC < $LOG
    else
      $MAIL -s "Backup $LOG" $MAILREC < $LOG
    fi
  fi

done