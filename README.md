# Remote Backup (rmbackup)

Remote server backup with rsync and config files
Based on [Backup mit RSYNC] (http://wiki.ubuntuusers.de/Skripte/Backup_mit_RSYNC)

rmbackup is a bash script that uses rsync to do incremental centralized backups of remote servers. It can be configured by config files.

There has to be a user on the remote server that is able to run rsync with root privileges and the backup server must be able to login without a password. The script should be run by cron on the backup server.

## Setting things up with a Linux remote server and a FreeBSD backup server
**On the remote Server:**

- Create a user named _rmbackup_:
	
		$ adduser rmbackup

- Edit sudo config to allow rmbackup group to run rsync with no password:
	
		$ visudo

		# /etc/sudoers

		Cmnd_Alias RSYNC = /usr/bin/rsync
		%rmbackup ALL=(ALL) NOPASSWD: RSYNC

**On the backup Server:**

- Copy your public key to the remote server. Run this as the user that will take the backups:
	
		$ ssh-copy-id rmbackup@<remoteserver>

**On the remote Server:**

- Manually set the password to **\*** in /etc/shadow to prevent console logins, the shell can be set to /bin/bash, as there are no interactive logins.

		# /etc/shadow

		rmbackup:*:15753:0:99999:7:::

**On the backup Server:**

- Create a config file in rmbackup.d/:

		$ cp sample.conf.dist <remotehost>.conf

		#Sample conf for backup script
		
		## SSH config for the remote server (default port is 22)
		SSH_USER="rmbackup"
		SSH_SERVER="example.com"
		SSH_PORT=22
		
		# Which folders sould be backed up from the remote server?
		REMOTE_SOURCES=(/root /etc /home /var)
		
		# In which folder should we store the backups on the backup server 
		# (subdirs for the server will be created by the script)?
		
		TARGET="/Backups/"
		
		# Additional command line parameters for ssh (verbose mode, exclude patterns...
		# see man rsync for further information)
		# RSYNC_CONF=(-v)
		
- Change the path to _rmbackup.d_ in rmbackup.sh:

		# rmbackup.sh
		
		#!/bin/bash
		...		
		# Where to look for config files
		CONFLOCATION=/etc/rmbackup.d/*.conf

- Setup the cronjob for the user that does the backups:

		$ crontab -e

		# /etc/crontab - root's crontab for FreeBSD
		#
		# $FreeBSD: release/9.1.0/etc/crontab 194170 2009-06-14 06:37:19Z brian $
		#
		SHELL=/usr/local/bin/bash
		PATH=/etc:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root
  		
		#minute hour mday month wday command
		#
		0 */1 * * * /home/rmbackup/bin/backup.sh

Backups will now be taken hourly.

## Changelog

**2013-02-21**
- Added the ability to backup mysql databases (just drop a .my.cnf in the remote users home dir)

**2013-02-20**

 - We're now unsetting the config before loading a new one
 - Mail sending after backup can now be specified per host instead of a global setting

**2013-02-18**

- First commit

## License

rmbackup is distributed under the MIT license, which is similar in effect to the BSD license.

> Copyright 2013 Christian Busch (http://github.com/chrisb86)
> 
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
> 
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
> 
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.