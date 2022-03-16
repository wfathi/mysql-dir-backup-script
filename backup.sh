#!/bin/bash

#---------------------- Variables used in the script ---------------------------

CONF_FILE="backup.cfg"
ROOTSCRIPT=$(grep -w "ROOTSCRIPT" "$CONF_FILE" | cut -d ":" -f2)

MYSQL_HOST=$(grep -w "MYSQL_HOST" "$CONF_FILE" | cut -d ":" -f2)
MYSQL_USER=$(grep -w "MYSQL_USER" "$CONF_FILE" | cut -d ":" -f2)
MYSQL_PSWD=$(grep -w "MYSQL_PSWD" "$CONF_FILE" | cut -d ":" -f2)
MYSQL_LOCAL_RETENTION=$(grep -w "MYSQL_LOCAL_RETENTION" "$CONF_FILE" | cut -d ":" -f2)
MYSQL_LOCAL_ROOT=$(grep -w "MYSQL_LOCAL_ROOT" "$CONF_FILE" | cut -d ":" -f2)
MYSQL_LOCAL_NUMBER_ARCHIVE=$(grep -w "MYSQL_LOCAL_NUMBER_ARCHIVE" "$CONF_FILE" | cut -d ":" -f2)
MYSQL_DB_LIST=$(grep -w "MYSQL_DB_LIST" "$CONF_FILE" | cut -d ":" -f2)

BCKP_SERVER_NAME=$(grep -w "BCKP_SERVER_NAME" "$CONF_FILE" | cut -d ":" -f2)
BCKP_SERVER_ROOT=$(grep -w "BCKP_SERVER_ROOT" "$CONF_FILE" | cut -d ":" -f2)
BCKP_SERVER_DST=$(grep -w "BCKP_SERVER_DST" "$CONF_FILE" | cut -d ":" -f2)
DIR_REMOTE_RETENTION=$(grep -w "DIR_REMOTE_RETENTION" "$CONF_FILE" | cut -d ":" -f2)
DIR_LIST=$(grep -w "DIR_LIST" "$CONF_FILE" | cut -d ":" -f2)

BCKP_COMMAND='rdiff-backup'

#--------------------- Functions for backing up the database---------------------
# Creating a directory for a local backup
function mysql_local_backupdir(){
	MYSQL_LOCAL_ROOT="$1"
	DATE=$(date +"%y-%m-%d-%H")
	if [ ! -d "$MYSQL_LOCAL_ROOT" ]  
	then
		mkdir "$MYSQL_LOCAL_ROOT"
	fi
	mkdir "$MYSQL_LOCAL_ROOT"/"$DATE"
	mkdir "$MYSQL_LOCAL_ROOT"/"$DATE"/logs
}

# Listing the databases to backup
function mysql_listing_database(){
	MYSQL_LOCAL_ROOT="$1"
	MYSQL_DB_LIST="$2"
	mysql -h $MYSQL_HOST -u $MYSQL_USER -e "show databases" | cut -d " " -f1 | sed '1d' > /$MYSQL_LOCAL_ROOT/$MYSQL_DB_LIST	
}

# Execution of the backup
function mysql_backup() {
	COMPRESSOR="gzip"
	DATE=$(date +"%y-%m-%d-%H")
	MYSQL_LOCAL_ROOT="$1"
	MYSQL_DB_LIST="$2"
	MYSQLDUMP_OPTIONS="--dump-date --no-autocommit --single-transaction --hex-blob --triggers -R -E"
	while read DB_NAME
	do
		echo "Backing up $DB_NAME..."
		mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PSWD $DB_NAME $MYSQLDUMP_OPTIONS \
		> $COMPRESSOR $MYSQL_LOCAL_ROOT/$DATE/$DB_NAME.zip 2>> $MYSQL_LOCAL_ROOT/$DATE/logs/$DB_NAME.log
	done < /$MYSQL_LOCAL_ROOT/$MYSQL_DB_LIST
}

# Purgig the old backups
function mysql_purge() {
	MYSQL_LOCAL_ROOT="$1"
	MYSQL_LOCAL_RETENTION="$2"
	if [ ! -d $MYSQL_LOCAL_ROOT ]
	then 
		echo "Error: Directory does not exist !"
		exit 0
	else
		find $MYSQL_LOCAL_ROOT -mtime +$MYSQL_LOCAL_RETENTION -exec rm -rf {} \;
	fi 	
}

# Executing all the functions concerning mysql backup
function mysql_backup_main() {
	MYSQL_LOCAL_ROOT=$1
	MYSQL_DB_LIST=$2
	MYSQL_LOCAL_RETENTION=$3
	mysql_local_backupdir $MYSQL_LOCAL_ROOT
	mysql_listing_database $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST

	mysql_backup $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST
	
	mysql_purge $MYSQL_LOCAL_ROOT $MYSQL_LOCAL_RETENTION
}
echo "Backing up mysql databases..."
mysql_backup_main $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST $MYSQL_LOCAL_RETENTION

#-------------------Functions for backing up Files and Directories-------------------------------

function listing_dir(){
	ROOTSCRIPT=$1
	DIR_LIST=$2
	ls -d -- /*/ | grep -v -w "media\|mnt\|proc\|run\|sys\|dev" | cut -d "/" -f2 \
		> /$ROOTSCRIPT/$DIR_LIST
}

function dir_remote_backup() {
	BCKP_SERVER_DST=$1
	BCKP_SERVER_NAME=$2
	BCKP_SERVER_ROOT=$3
	DIR_LIST=$4
	BCKP_COMMAND=$5
	while read DIR_BEING_BCKP
	do
		echo "Backuping $DIR_BEING_BCKP..."
		$BCKP_COMMAND /$DIR_BEING_BCKP $BCKP_SERVER_DST@$BCKP_SERVER_NAME::$BCKP_SERVER_ROOT/$BCKP_SERVER_DST/$DIR_BEING_BCKP
	done < /$ROOTSCRIPT/$DIR_LIST
}

function dir_remote_purge() {
	BCKP_SERVER_DST=$1
	BCKP_SERVER_NAME=$2
	BCKP_SERVER_ROOT=$3
	DIR_LIST=$4
	DIR_REMOTE_RETENTION=$5
	BCKP_COMMAND=$6
	while read DIR_BEING_BCKP
	do
		echo "Purging $DIR_BEING_BCKP..."
		$BCKP_COMMAND --remove-older-than $DIR_REMOTE_RETENTION --force $BCKP_SERVER_DST@$BCKP_SERVER_NAME::/$BCKP_SERVER_ROOT/$BCKP_SERVER_DST/$DIR_BEING_BCKP
	done < /$ROOTSCRIPT/$DIR_LIST
}

function dir_backup_main() {
	BCKP_SERVER_DST=$1
	BCKP_SERVER_NAME=$2
	BCKP_SERVER_ROOT=$3
	DIR_LIST=$4
	DIR_REMOTE_RETENTION=$5
	BCKP_COMMAND=$6
	ROOTSCRIPT=$7

	listing_dir $ROOTSCRIPT $DIR_LIST
	dir_remote_backup $BCKP_SERVER_DST $BCKP_SERVER_NAME $BCKP_SERVER_ROOT $DIR_LIST $BCKP_COMMAND
	dir_remote_purge $BCKP_SERVER_DST $BCKP_SERVER_NAME $BCKP_SERVER_ROOT $DIR_LIST $DIR_REMOTE_RETENTION $BCKP_COMMAND
}

echo "Backing up local directories..."
dir_backup_main $BCKP_SERVER_DST $BCKP_SERVER_NAME $BCKP_SERVER_ROOT $DIR_LIST $DIR_REMOTE_RETENTION $BCKP_COMMAND $ROOTSCRIPT
