#!/bin/bash
#
#	*EXAMPLE* Script for daily backup
#	
#	Before the backup takes place a snapshot of the current backupfile is taken.
#	This is done by calling a script $snapscript. 
#	Using a snapshot supporting filesystem (btrfs,xfs...) is recommended 
#	for the backupdestination. If BTRFS is used you may have a look to 
#           https://github.com/dolorosus/btrfs-snapshot-rotation
#
#	After the snapshot is taken, most of the active services are shutdown.
#	You should adapt the function *progs()* according to your needs.
#
#	Also you should take a closer look to *setup()*. Change the variables according
#	your filesystem structure.
#
#	2019-05-10	Comments
#
#	2019-04-30	initial commit by Dolorosus
#
#

setup () {
	#
	# Define some fancy colors, but only if connected to a terminal.
	# Thus output to file will be not cluttered anymore
	#
	[ -t 1 ] && {
		RED=$(tput setaf 1)
		GREEN=$(tput setaf 2)
		YELLOW=$(tput setaf 3)
		BLUE=$(tput setaf 4)
		MAGENTA=$(tput setaf 5)
		CYAN=$(tput setaf 6)
		WHITE=$(tput setaf 7)
		RESET=$(tput setaf 9)
		BOLD=$(tput bold)
		NOATT=$(tput sgr0)
	}||{
		RED=""
		GREEN=""
		YELLOW=""
		BLUE=""
		MAGENTA=""
		CYAN=""
		WHITE=""
		RESET=""
		BOLD=""
		NOATT=""
	}
	
	TICK="[${GREEN}✓${NOATT}]"
	CROSS="[${RED}✗${NOATT}]"
	INFO="[i]"
	QST="[?]"
	DONE="${GREEN} done!${NOATT}"
	MYNAME=$(basename $0)
	
	export stamp=$(date +%y%m%d_%H%M%S)
	export destvol="/mnt/USB64"
	export destpath="${destvol}/BACKUPS" 
	export snappath="${destvol}/.snapshots/BACKUPS"
	export destpatt="MyRaspi-2*_[0-9]*.img"
	export bcknewname="MyRaspi-${stamp}.img"
	export tmppre="\#"

	
	export bckscript="/home/pi/scripts/RaspiBackup.sh"
	export snapscript="/home/pi/scripts/btrfs-snapshot-rotation.sh"
	export mark="manual"
	export versions=28
	#
	# adapt according to your needs
	#
	export prog='mysql pihole-FTL lighttpd syncthing@pi docker containerd lightdm log2ram cockpit mattermost'
}


msg () {
	echo "${INFO} ${YELLOW}${1}${NOATT}"
}
msgok () {
	echo "${TICK} ${YELLOW}${1}${NOATT}"
}

errexit () {
	
	case "${1}" in
		1)	echo "${CROSS}${RED} You have to be root to run this script${NOATT}"
			exit ${1};;
				
		10)	echo "${CROSS}${RED} More than one backupfile according to ${destpath}/${destpatt} found."
			echo "Can't decide which one to use.${NOATT}"
			exit ${1};;

		11)	echo "${CROSS}${RED} backupfile according to ${destpath}/${destpatt} is no flatfile.${NOATT}"
			exit ${1};;

		12)	echo "${CROSS}${RED} backupfile according to ${destpath}/${destpatt} is empty.${NOATT}"
			exit ${1};;
        
		20)	echo "${CROSS}${RED} No executable file $bckscript found.${NOATT}"
			exit ${1};;

		21)	echo "${CROSS}${RED} No executable file $snapscript found.${NOATT}"
			exit ${1};;
			
		25)	echo "${TICK} ${YELLOW}${action} $prog failed${NOATT}"
			;;
			
		30) echo "${RED}something went wrong..."
			echo "the incomplete backupfile is named: ${destpath}/${tmppre}${bcknewname}"
			echo "Resolve the issue, rename the the backupfile and restart"
			echo "Good luck!${NOATT}"
			exit ${1};;
			
		*)	echo "${RED}An unknown error occured${NOATT}" 
			exit 99;;
	esac
}

progs () {

	local action=${1:=start}
	local setopt=$-

	set +e
	systemctl ${action} ${prog} >/dev/null 2>&1
	[ -z "${setopt##*e*}" ] && set -e
	
	[ "${action}" == "start" ] && pihole restartdns
  
	return 0	
}

do_inital_backup () {
	
 	local creopt="-c -s 4000 "
	progs stop

	msg "starting backup_: $bckscript start ${creopt} ${destpath}/${tmppre}${bcknewname}"
	backup="ko"
	$bckscript start ${creopt} "${destpath}/#${bcknewname}" && {
		msg "moving  ${destpath}/#${bcknewname} to ${destpath}/${bcknewname}"
		mv "${destpath}/#${bcknewname}" "${destpath}/${bcknewname}"  
		msgok "Backup successful"
		msg "Backupfile is_: ${destpath}/${bcknewname}"
		backup="ok" 
}

	progs start

	  [ ${backup} = "ok" ] && return 0
	errexit 30
}


do_backup () {
	
	local creopt="${1}"
	
	progs stop

	# move the destination to a temporary filename while 
	# the backup is working
	[ -z "${creopt}" ] && {	
	msg "moving ${bckfile} to ${destpath}/#${bcknewname}"
	mv "${bckfile}" "${destpath}/#${bcknewname}"
	}
	msg "starting backup_: $bckscript start ${creopt} ${destpath}/${tmppre}${bcknewname}"
	backup="ko"
	$bckscript start ${creopt} "${destpath}/#${bcknewname}"  && {
		backup="ok"
		msg "moving  ${destpath}/#${bcknewname} to ${destpath}/${bcknewname}"
		mv "${destpath}/#${bcknewname}" "${destpath}/${bcknewname}"
		msgok "Backup successful"
	 	msg "Backupfile is_: ${destpath}/${bcknewname}"  
	}
  
	progs start

	[ ${backup} = "ok" ] && return 0
  	errexit 30
  
}

# ===============================================================================================================
# Main
# ===============================================================================================================
#
# Please, do not disturb
#
trap "progs start" SIGTERM SIGINT

setup

#
# Bailout in case of uncaught error
#
set -e

[ $(/usr/bin/id -u) == "0" ] || errexit 1
[ "$(ls -1 ${destpath}/${destpatt}|wc -l)" == "0" ] && {
	progs stop
	do_inital_backup 
	progs start
	exit 0
}

#
# some checks 
#
[ "$(ls -1 ${destpath}/${destpatt}|wc -l)" == "1" ] || errexit 10

bckfile="$(ls -1 ${destpath}/${destpatt})" 
[ -f "${bckfile}" ] || errexit 11
[ -s "${bckfile}" ] || errexit 12

#
# some more checks...
#
[ -x "${bckscript}" ] || errexit 20
[ -x "${snapscript}" ] || errexit 21

#
# create a snapshot of current state
#
${snapscript}  ${destpath} ${destvol}/.snapshots/BACKUPS ${mark} ${versions}

#
# Rotate the logfiles
#
logrotate  -f /etc/logrotate.conf

#
# finally do the backup
#
do_backup

#
# All's Well That Ends Well
#
exit 0
# ===============================================================================================================
# End of daily.sh
# ===============================================================================================================
