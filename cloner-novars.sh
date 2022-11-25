#!/bin/bash

## This script assumes that production website is on server A,
## development environments are on server B,
## and development environments are called dev1, dev2, v5, prepro and net.

## This scrips also assumes that SSH port for production server is TCP/22,
## and that production server has an access control list which allows
## development server to access via SSH, with public key authentication,
## but only if SSH key is loaded in the SSH agent by the operator running the script,
## in order to prevent malicious parties to run it and exfiltrate data.

## Global variables
# Paths in external server
PROD_PATH="/var/www/production"
PROD_TMP_PATH="/home/ubuntu/tmp"
PROD_USER="ubuntu"
PROD_HOST="production-website.com"

# Paths in localhost
BASE_PATH="/var/www/development"
LOCAL_TMP_PATH="/home/ubuntu/tmp"
LOCAL_USER="ubuntu"
LOCAL_HOST="development-website.net"

# Naming conventions
## WARNING: If a new environment is added, please amend parameterValidation() function accordingly.
ENV_NAME_PRODUCTION="prod"
ENV_NAME_DEV2="dev2"
ENV_NAME_DEV1="dev1"
ENV_NAME_V5="v5"
ENV_NAME_PREPRO="prepro"
ENV_NAME_NET="net"

# Activating extglob in order to be able to use inverted expressions, as we do not want to remove wp-config.php from
# each environment. We use inverted expression in deleteDestinationFolderFiles() function.
# For some reason it errors when activated within a function, so applied globally.
shopt -s extglob

parameterValidation() {
  # Checking $1 and $2 are not empty, as we need source and destination.
  # Checking $1 (source) contains either production or development environments.
  # Checking $2 (destination) contains development environments. Destination cannot be a production environment.
  # Checking $1 is different than $2.
  if [[ -n $1 && -n $2 ]] && \
  [[ $1 == "$ENV_NAME_PRODUCTION" || $1 == "$ENV_NAME_DEV1" || $1 == "$ENV_NAME_DEV2" || \
  $1 == "$ENV_NAME_PREPRO" || $1 == "$ENV_NAME_V5" || $1 == "$ENV_NAME_NET" ]] && \
  [[ $2 == "$ENV_NAME_DEV1" || $2 == "$ENV_NAME_DEV2" || $2 == "$ENV_NAME_PREPRO" || \
  $2 == "$ENV_NAME_V5" || $2 == "$ENV_NAME_NET" ]] && \
  [[ $1 != $2 ]]; then
    echo "[Parameter Validation]: Specified environments are correct."
  else
    echo "[Parameter Validation]: Parameters are missing or incorrect. Please run the script again with the relevant parameters."
    echo "Example: ./cloner.sh dev1 dev2"
    exit 1
  fi
}

sshAgentCheck() {
  if [[ $1 == "$ENV_NAME_PRODUCTION" ]]; then
    echo "[SSH Agent Check]: Testing SSH connection with external server..."
    ssh $PROD_USER@$PROD_HOST -A "echo "[SSH Agent Check]: Test is successful.""
    if [[ $? -ne 0 ]]; then
      echo "[SSH Agent Check]: The connection was unsuccessful. Please make sure you have the relevant SSH key loaded in the SSH agent."
      exit 1
    else
      echo "[SSH Agent Check]: Passed test."
    fi
  else
    echo "[SSH Agent Check]: Source and destination environments are within the same server. Skipping check..."
  fi
}

wpCliInstallationCheck() {
  if [[ $1 == "$ENV_NAME_PRODUCTION" ]]; then
    echo "[WP-CLI Check]: Confirming there is a valid WP-CLI installation in the remote server..."
    REMOTE_WPCLI_BIN=$(ssh $PROD_USER@$PROD_HOST -A "echo $(which wp)")
    if [[ -z REMOTE_WPCLI_BIN ]]; then
      echo "[WP-CLI Check]: There is no WP-CLI installation in the remote user. Please install it and run the script again."
      exit 1
    else
      echo "[WP-CLI Check]: Remote server has a valid WP-CLI installation."
    fi
  fi

  echo "[WP-CLI Check]: Confirming there is a valid WP-CLI installation in the local server..."
  if [[ -z $(which wp) ]]; then
    echo "[WP-CLI Check]: There is no WP-CLI installation in this user. Please install it and run the script again."
    exit 1
  else
    LOCAL_WPCLI_BIN=$(which wp)
    echo "[WP-CLI Check]: Local server has a valid WP-CLI installation."
  fi
}

deleteDestinationFolderFiles() {
  set -e # Exit script upon error - start
  echo "[DST Deletion]: Deleting files from destination folder..."
  rm -rf "$BASE_PATH"/"$2"/!("wp-config.php")
  echo "[DST Deletion]: Files have been deleted."
  set +e # Exit script upon error - end
}

copyFromSourceToDestination() {
  # No error handling as some files are expected to error out due to permissions
  if [[ $1 == "$ENV_NAME_PRODUCTION" ]]; then
    echo "[SRC to DST Clone]: Copying files from source to destination, and exporting database from source..."
    ssh $PROD_USER@$PROD_HOST -A "\
    rsync -az $PROD_PATH/* $LOCAL_USER@$LOCAL_HOST:$BASE_PATH/$2;\
    $REMOTE_WPCLI_BIN @prod db export $PROD_TMP_PATH/prod.sql --set-gtid-purged=OFF;\
    rsync -az $PROD_TMP_PATH/prod.sql $LOCAL_USER@$LOCAL_HOST:$LOCAL_TMP_PATH"
  else
    echo "[SRC to DST Clone]: Copying files from source to destination..."
    rsync -az $BASE_PATH/$1/ $BASE_PATH/$2/ --exclude=wp-config.php
    echo "[SRC to DST Clone]: Files are copied."
    echo "[SRC to DST Clone]: Exporting database from source to a SQL file..."
    $LOCAL_WPCLI_BIN @$1 db export $LOCAL_TMP_PATH/prod.sql --set-gtid-purged=OFF
    echo "[SRC to DST Clone]: SQL file has been created."
  fi

  chown -R $LOCAL_USER:www-data $BASE_PATH/$2
}

deleteSqlFiles() {
  if [[ $1 == "$ENV_NAME_PRODUCTION" ]]; then
    echo "[DB Deletion]: Deleting database SQL file in remote server..."
    ssh $PROD_USER@$PROD_HOST -A "rm -rf $PROD_TMP_PATH/prod.sql"
    echo "[DB Deletion]: Database SQL file has been deleted in remote server."
    echo "[DB Deletion]: Deleting database SQL file in local server..."
    rm -rf "$LOCAL_TMP_PATH/prod.sql"
    echo "[DB Deletion]: Database SQL file has been deleted in local server."
  else
    echo "[DB Deletion]: Deleting database SQL file in local server..."
    rm -rf "$LOCAL_TMP_PATH/prod.sql"
    echo "[DB Deletion]: Database SQL file has been deleted in local server."
  fi
}

importSqlFiles() {
  set -e # Exit script upon error - start
  echo "[SQL Import]: Importing database to destination..."
  $LOCAL_WPCLI_BIN @$2 db import $LOCAL_TMP_PATH/prod.sql
  echo "[SQL Import]: Database has been imported."
  set +e # Exit script upon error - end
}

postCloneQueries() {
  if [[ $1 == "$ENV_NAME_PRODUCTION" ]]; then
    echo "[Post Clone Tasks]: Executing post clone tasks..."

    echo "[Post Clone Tasks]: Post clone tasks have been executed."
  else
    echo "No post-script tasks to do"
  fi

  echo "===="
  echo "Cloning tasks have been completed."
}

# Verifying that passed parameters are valid. Passing $1 and $2 parameters to the function.
parameterValidation "$1" "$2"

# Checking SSH agent is loaded with relevant key. Passing $1 parameter to the function.
sshAgentCheck "$1"

# Checking WP-CLI tool is present in both source and destination environments. Passing parameter $1 to the function.
wpCliInstallationCheck "$1"

# Initiating tasks related to the clone.
## 1) Cleaning up the destination directory. Passing parameter $2 to the function.
deleteDestinationFolderFiles "$1" "$2"

## 2) Copying files and database from source to destination. Passing parameters $1 and $2 to the function.
copyFromSourceToDestination "$1" "$2"

## 3) Importing database to destination. Passing parameters $1 and $2 to the function.
importSqlFiles "$1" "$2"

## 4) Removing database file from server, as it has already been imported. Passing parameter $1 to the function.
deleteSqlFiles "$1"

## 5) Running queries after completing the clone. Passing $2 as parameter to the function.
postCloneQueries "$1" "$2"

