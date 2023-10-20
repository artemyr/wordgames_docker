#!/bin/bash
set -e
#first cd current dir
cd "$(dirname "${BASH_SOURCE[0]}")"

export DEFAULT_USER="1000";
export DEFAULT_GROUP="1000";

export USER_ID=`id -u`
export GROUP_ID=`id -g`
export USER=$USER


if [ "$USER_ID" == "0" ];
then
    export USER_ID=$DEFAULT_USER;
fi

if [ "$GROUP_ID" == "0" ];
then
    export GROUP_ID=$DEFAULT_GROUP;
fi


test -e "./.env" || { cp .env.example .env; };
#load .env
export $(egrep -v '^#' .env | xargs)

if [ $# -eq 0 ]
  then
    echo "HELP:"
    echo "make env - copy .env.example to .env"
    echo "init - initialize bitrix and project repositories"
    echo "make dump - make dump and push to db rep"
    echo "db import FILE - load FILE to mysql"
    echo "db renew - load dump from repo, fresh db and apply"
    echo "db - run db cli"
    echo "db export > file.sql - export db to file"
    echo "build - make docker build"
    echo "up - docker up daemon"
    echo "down - docker down"
    echo "down full - docker down all containers"
    echo "run - run in php container from project root"
fi

function applyDump {
    cat $1 | docker exec -i ${PROJECT_PREFIX}_mysql mysql -u $MYSQL_USER -p"$MYSQL_PASSWORD" $MYSQL_DATABASE;
    return $?
}

function runInMySql {
    local command=$@
    docker exec -i ${PROJECT_PREFIX}_mysql su mysql -c "$command"
    return $?
}

function runInPhp {
    local command=$@
    echo $command;
    docker exec -i ${PROJECT_PREFIX}_php su www-data -c "$command"
    return $?
}

function enterInPhp {
    docker exec -it ${PROJECT_PREFIX}_php su www-data
    return $?
}

function makeDump {
    runInMySql "export MYSQL_PWD='$MYSQL_PASSWORD'; mysqldump -u $MYSQL_USER $MYSQL_DATABASE" > $1
    return $?
}

function makeDumpOnServer() {
  sshpass -p $REMOTE_SSH_PASS ssh -p$REMOTE_SSH_PORT -o StrictHostKeyChecking=no -T $REMOTE_SSH_USER@$REMOTE_SSH_HOST <<-SSH
    if [ -f dump.sql.gz ]; then
        rm $REMOTE_MYSQL_DUMP_PATH
    fi
    mysqldump -h$REMOTE_MYSQL_HOST -u$REMOTE_MYSQL_USER -p'$REMOTE_MYSQL_PASS' $REMOTE_MYSQL_DB_NAME | gzip - > $REMOTE_MYSQL_DUMP_PATH
SSH
  return $?
}

function removeDumpFromServer() {
  sshpass -p $REMOTE_SSH_PASS ssh -p $REMOTE_SSH_PORT -o StrictHostKeyChecking=no -T $REMOTE_SSH_USER@$REMOTE_SSH_HOST <<-SSH
    if [ -f dump.sql.gz ]; then
        rm $REMOTE_MYSQL_DUMP_PATH
    fi
SSH
  return $?
}

function getDumpFromServer() {
  sshpass -p $REMOTE_SSH_PASS rsync -rzclEt -e 'ssh -p $REMOTE_SSH_PORT' --progress $REMOTE_SSH_USER@$REMOTE_SSH_HOST:$REMOTE_MYSQL_DUMP_PATH dump.sql.gz
    return $?
}

function loadDumpToDocker() {
  if [ -f dump.sql.gz ]; then
    docker/dctl.sh db import containers/mysql/drop_all_tables.sql
    gunzip -c dump.sql.gz | docker/dctl.sh db import -
  fi
  return $?
}

function syncBitrix() {
  sshpass -p $REMOTE_SSH_PASS rsync -rzclEt -e 'ssh -p $REMOTE_SSH_PORT' --progress --delete-after --exclude='web_release' --exclude='backup' --exclude='cache' --exclude='cache' --exclude='.settings_extra.php' --exclude='.settings.php' --exclude='php_interface' $REMOTE_SSH_USER@$REMOTE_SSH_HOST:$REMOTE_BITRIX_URL $LOCAL_BITRIX_URL
  return $?
}

function syncDb() {
  makeDumpOnServer
  getDumpFromServer
  removeDumpFromServer
  loadDumpToDocker
}

function syncUpload() {
  sshpass -p $REMOTE_SSH_PASS rsync -rzclEt -e 'ssh -p $REMOTE_SSH_PORT' --progress --delete-after --exclude='*.gz' $REMOTE_SSH_USER@$REMOTE_SSH_HOST:$REMOTE_UPLOAD_URL $LOCAL_UPLOAD_URL
  return $?
}

if [ "$1" == "make" ];
  then
    if [ "$2" == "env" ];
        then
            cp .env.example .env
    fi
    
    if [ "$2" == "dump" ];
        then
          git clone $DATABASE_REPO ../docker/data/mysql/dump || echo "not clone repo"
          makeDump ../docker/data/mysql/dump/database.sql;
          cd ../docker/data/mysql/dump;
          git add database.sql
          git commit -a -m 'update database'
          git push origin master
          echo "PUSH SUCCESS"
    fi
fi

if [ "$1" == "sync" ]; then
  if [ "$2" == "" ]; then
      echo "Menu:"
      echo "sync files - Обновляет папки bitrix и upload - скачивая их с площадки"
      echo "sync db - Обновляет базу данных на основании бд площадки"
      echo "sync upload - Обновляет локальную папку upload с площадки"
      echo "sync bitrix - Обновляет локальную папку битрикс с площадки"
      echo "sync all - Обновляет базу данных, папки upload и bitrix"
  fi
  if [ "$2" == "upload" ]; then
    syncUpload
  fi
  if [ "$2" == "db" ]; then
    syncDb
  fi
  if [ "$2" == "bitrix" ]; then
    syncBitrix
  fi
  if [ "$2" == "all" ]; then
    syncDb
    syncBitrix
    syncUpload
  fi
  if [ "$2" == "files" ]; then
    syncBitrix
    syncUpload
  fi
fi

if [ "$1" == "db" ];
  then
    if [ "$2" == "" ];
        then
        docker exec -it ${PROJECT_PREFIX}_mysql mysql -u $MYSQL_USER -p"$MYSQL_PASSWORD" $MYSQL_DATABASE;
    fi

    if [ "$2" == "export" ];
        then
        runInMySql "export MYSQL_PWD='$MYSQL_PASSWORD'; mysqldump -u $MYSQL_USER $MYSQL_DATABASE"
    fi


    if [ "$2" == "import" ];
        then
        applyDump $3
    fi

    if [ "$2" == "renew" ];
        then
        rm -rf "../docker/data/mysql/dump" || echo "old dump not found"
        git clone $DATABASE_REPO ../docker/data/mysql/dump
        tar -xvf "../docker/data/mysql/dump/database.tar.bz2" -C "../docker/data/mysql/dump/"
        applyDump "../docker/containers/mysql/drop_all_tables.sql"
        applyDump "../docker/data/mysql/dump/database.sql"
    fi
fi

if [ "$1" == "build" ];
  then
    docker-compose -p ${PROJECT_PREFIX} build 
fi

if [ "$1" == "init" ];
  then
    docker-compose -p ${PROJECT_PREFIX} build;
    docker-compose -p ${PROJECT_PREFIX} up -d;

    if [ ! -f "../${PROJECT_PREFIX}/composer.lock" ]; then
        runInPhp "cd ${PROJECT_PREFIX}/ && composer install"
    fi
fi

if [ "$1" == "up" ];
  then
  docker-compose -p ${PROJECT_PREFIX} build 
  docker-compose -p ${PROJECT_PREFIX} up -d;
fi

if [ "$1" == "down" ];
  then
    if [ "$2" == "full" ];
        then
           docker stop $(docker ps -q);
        else
           docker-compose -p ${PROJECT_PREFIX} down
    fi
fi

if [ "$1" == "run" ];
  then
    if [ "$2" == "" ];
        then
        docker exec -it ${PROJECT_PREFIX}_php su www-data -c "cd ~; bash -l";
    else
    runInPhp "${@:2}"
    fi
fi

if [ "$1" == "in" ];
  then
    enterInPhp "${@:2}"
fi
