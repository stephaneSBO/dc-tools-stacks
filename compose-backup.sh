#!/usr/bin/env bash

### Bash Environment Setup
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# set -o xtrace
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
IFS=$'\n'

# Fully backup a docker-compose project, including all images, named and unnamed volumes, container filesystems, config, logs, and databases. 
project_dir="${1:-$PWD}"
if [ -f "$project_dir/docker-compose.yml" ]; then
    echo "[i] Found docker-compose config at $project_dir/docker-compose.yml"
else
    echo "[X] Could not find a docker-compose.yml file in $project_dir"
    exit 1
fi

project_name=$(basename "$project_dir")
backup_time=$(date +"%Y-%m-%d_%H-%M")
backup_dir="$project_dir/backups/$backup_time"

# Source any needed environment variables
[ -f "$project_dir/docker-compose.env" ] && source "$project_dir/docker-compose.env"
[ -f "$project_dir/.env" ] && source "$project_dir/.env"


echo "[+] Backing up $project_name project to $backup_dir"
mkdir -p "$backup_dir"

echo "    - Saving docker-compose.yml config"
cp $project_dir/docker-compose.yml $backup_dir/docker-compose.yml
echo "step1"

# Optional: run a command inside the contianer to dump your application's state/database to a stable file
echo "    - Saving application state to ./dumps"
echo "step2"
mkdir -p "$backup_dir/dumps"
# your database/stateful service export commands to run inside docker go here, e.g.
#   docker-compose exec postgres env PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip -9 > "$backup_dir/dumps/$POSTGRES_DB.sql.gz"
#   docker-compose exec redis redis-cli SAVE
#   docker-compose exec redis cat /data/dump.rdb | gzip -9 > "$backup_dir/dumps/redis.rdb.gz"

# Optional: pause the containers before backing up to ensure consistency
# docker-compose pause
echo "step3"
for service_name in $(docker-compose config --services); do
    image_id=$(docker-compose images -q "$service_name")
    image_name=$(docker image inspect --format '{{json .RepoTags}}' "$image_id" | jq -r '.[0]')
    container_id=$(docker-compose ps -q "$service_name")
    echo "step4"
    service_dir="$backup_dir/$service_name"
    echo "[*] Backing up ${project_name}__${service_name} to ./$service_name..."
    mkdir -p "$service_dir"
    
    # # save image
    # echo "step5"
    # echo "    - Saving $image_name image to ./$service_name/image.tar"
    # docker save --output "$service_dir/image.tar" "$image_id"
    # echo "step6"
    # if [[ -z "$container_id" ]]; then
    #     echo "    - Warning: $service_name has no container yet."
    #     echo "         (has it been started at least once?)"
    #     echo "step7"
    #     continue
    # fi
echo "step8"
    # save config
    echo "    - Saving container config to ./$service_name/config.json"
    echo "step9
    "docker inspect "$container_id" > "$service_dir/config.json"

    # save logs
    echo "    - Saving stdout/stderr logs to ./$service_name/docker.{out,err}"
    docker logs "$container_id" > "$service_dir/docker.out" 2> "$service_dir/docker.err"

    # save data volumes
    mkdir -p "$service_dir/volumes"
    echo "step20"
    for source in $(docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$container_id"); do
        echo "step21"
        volume_dir="$service_dir/volumes$source"
        echo "    - Saving $source volume to ./$service_name/volumes$source"
        echo "step22"
        mkdir -p $(dirname "$volume_dir")
        echo "step23"
        cp -a -r "$source" "$volume_dir"
        echo "step24"
    done

    # save container filesystem
    echo "    - Saving container filesystem to ./$service_name/container.tar"
    docker export --output "$service_dir/container.tar" "$container_id"

    # save entire container root dir
    echo "    - Saving container root to $service_dir/root"
    cp -a -r "/var/lib/docker/containers/$container_id" "$service_dir/root"
done

echo "[*] Compressing backup folder to $backup_dir.tar.gz"
tar -zcf "$backup_dir.tar.gz" --totals "$backup_dir" && rm -Rf "$backup_dir"

echo "[√] Finished Backing up $project_name to $backup_dir.tar.gz."

# Resume the containers if paused above
# docker-compose unpause