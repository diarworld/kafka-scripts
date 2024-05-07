#!/bin/bash

# -------------------------------------
# Variables section:
# -------------------------------------

pattern="Configs for user-principal .* are SCRAM"

KAFKA_BIN="kafka/bin"	#<-- < this-github-repo >/kafka_automation/scripts/[ kafka/bin ]
LINE=${LINE}user---     #<-- " --------------------user---"
DEBUG=$DEBUG            #<-- enable: DEBUG="enable", disable: DEBUG=""
vault_url=$VAULT_URL
vault_engine=$VAULT_ENGINE
vault_engine_path=$VAULT_PATH

# -------------------------------------
# Functions section:
# -------------------------------------

debug_msg() {
    #TEXT_MSG=$1
    if [[ $DEBUG ]]; then echo -e "$LINE\n $1\n$LINE"; fi
}


debug_cmd() {
    #CMD=$1
    if [[ $DEBUG ]]; then "$@"; fi
}


usage() {
  # Print script usage tip
  echo "Usage: $0 -n <usernames> -t <project> -e <environment>" 1>&2
  exit 1
}


check_params() {
  # Check input parameters are correct
  if [ -z "${usernames}" ] || [ -z "${project}" ]; then usage; fi
}


check_user() {
  debug_msg "CHECK_USER"              ##<-- debug MSG 0

  # Check if user already exists or not
  echo -e "Checking if user exists:\n"
  debug_cmd "echo" "$KAFKA_BIN/kafka-configs.sh --zookeeper $zookeeper --describe --entity-name $username --entity-type users"
  kafka_configs_out=$($KAFKA_BIN/kafka-configs.sh --zookeeper ${zookeeper} --describe --entity-name ${username} --entity-type users)
  #debug_cmd "echo" "kafka_configs_out= $kafka_configs_out"

  if [[ $? != 0 ]]; then
    echo -e "\n\tError occured during user check!"
    exit -20
  else
    [[ $(echo -e ${kafka_configs_out} | egrep "${pattern}") ]] && return 0 || return 1
  fi
}


check_vault_output() {
  # Check if calling http API to vault returning errors
  if [[ ${1} != 0 ]]; then
    echo -e "\n\tError: Unable to access ${vault_url}. Details: ${2}"
    exit -10
  else
    vault_errors=$(echo "${2}" | jq -r '.errors[0]')
    if [[ "${vault_errors}" != "null" ]]; then
      echo -e "\n\tError: Unable to retrieve secrets from Vault! \n\n\tDetails: ${vault_errors}"
      exit -11
    fi
  fi

  return 0
}


check_vault_access() {
  debug_msg "CHECK_VAULT_ACCESS"      ##<-- debug MSG 1

  # Separate function to offload create_user function
  vault_output=$(
    curl -s -H "X-Vault-Token: ${vault_token}" \
    --request GET \
    ${vault_url}/${vault_engine}/data/${vault_engine_path}
  )
  check_vault_output $? "${vault_output}"
  return 0
}


check_zookeeper() {
  debug_msg "CHECK_ZOOKEEPER"         ##<-- debug MSG 2

  # Check for available zookeeper from configuration (in case of maintenance of some nodes)
  [[ ${zookeeper_auth_path} != "" ]] && client_configs create
  echo -e "Checking for 1st available zookeeper:\n"
  #debug_cmd "echo" "KAFKA_OPTS="
  #debug_cmd "echo" "$KAFKA_OPTS"

  error_available=1
  for zookeeper_host in ${zookeeper_hosts}; do
    r=$(echo 'QUIT' | nc -w 4 ${zookeeper_host} ${zookeeper_port}; echo $?)
    if [[ $r != 0 ]]; then
      echo -e "\tError: ${zookeeper_host}:${zookeeper_port} is not available!.\n"
    else
      error_available=0
      echo -e "\tFound available zookeeper: ${zookeeper}\n"
      zookeeper=${zookeeper_host}:${zookeeper_port}${zookeeper_tree}
      debug_cmd "echo" "$KAFKA_BIN/kafka-configs.sh --zookeeper $zookeeper --describe --entity-name $usernames --entity-type users"
      kafka_configs_out=$($KAFKA_BIN/kafka-configs.sh --zookeeper ${zookeeper} --describe --entity-name ${usernames} --entity-type users)

      if [[ $? != 0 ]]; then
        echo -e "\tError: zookeeper ${zookeeper} is not available!.\n"
        return 1
      else
        echo -e "\tFound available zookeeper: ${zookeeper}\n"
        return 0
      fi
    fi
  done

  [[ $error_available != 0 ]] && echo -e "\n\tError: zookeeper error: ${error_available}" && exit -30
  return 1
}

get_vault_token() {
  debug_msg "GET_VAULT_TOKEN"         ##<-- debug MSG 3

##<-- Old version delete after test
  # Get token fot Vault access using approle
  #vault_output=$(curl -s --request POST --data @${vault_approle_config} ${vault_url}/auth/${vault_approle_name}/login)
  #check_vault_output $? "${vault_output}"
  #vault_token=$(echo -e ${vault_output} | jq -r '.auth.client_token')
##<-- Old version delete after test

  vault_token=$VAULT_TOKEN

  debug_cmd "echo" "$VAULT_ADDR"
  debug_cmd "echo" 'get vault_token from environment'
#  debug_cmd "echo" "$vault_token"
}


check_kafka_directory() {
  debug_msg "CHECK_KAFKA_DIR"         ##<-- debug MSG 4

  kafka_dir_output=$(ls $KAFKA_BIN | grep sh | wc -l)
  if [[ $? != 0 ]]; then
     echo -e "\n\tNo executable .sh in $KAFKA_BIN!"
     exit
  else
    echo -e "\n\tKafka Command line in $KAFKA_BIN: FOUND success!"
  fi
}


get_kafka_configs() {
  debug_msg "GET_KAFKA_CONFIGS"       ##<-- debug MSG 5

  # Kafka environments configuration is stored as json in Vault
  # We'll get specific data from json, based on project and environment
  get_vault_token

  debug_cmd "echo" "request GET $vault_url/$vault_engine/data/$vault_engine_path"

  vault_output=$(
    curl -s -H "X-Vault-Token: ${vault_token}" \
    --request GET \
    ${vault_url}/${vault_engine}/data/${vault_engine_path}
  )

  check_vault_output $? "${vault_output}"

  project_map=$(echo -e "${vault_output}" | jq -r --arg project "$project" '.data.data.config[] | select((.project | tostring ) == $project )')
  [[ -z ${project_map} ]] && echo -e "\n\tError: Project ${project} doesn't exist!" && exit 45

  env_config=$(echo -e ${project_map} | jq -r --arg env "$env" '.environments[$env]')
  [[ ${env_config} == "null" ]] && echo -e "\n\tError: Environment ${env} wasn't found for project ${project}!" && exit 50

  zookeeper_hosts=$(echo -e ${env_config} | jq -r '.zookeeper_hosts[]')
  zookeeper_port=$(echo -e ${env_config} | jq -r '.zookeeper_port')
  zookeeper_tree=$(echo -e ${env_config} | jq -r '.zookeeper_tree_path // ""')
  zookeeper_auth_path=$(echo -e ${env_config} | jq -r '.vault_zookeeper_auth_path // ""')

  if [[ ${zookeeper_auth_path} != "" ]]; then
    debug_cmd "echo" "request GET $vault_url/$vault_engine/data/$zookeeper_auth_path"
    vault_output=$(curl -s -H "X-Vault-Token: ${vault_token}" --request GET ${vault_url}/${vault_engine}/data/${zookeeper_auth_path})
    check_vault_output $? "${vault_output}"
    zookeeper_user=$(echo -e ${vault_output} | jq -r '.data.data | keys[0]')
    debug_cmd "echo" "zookeeper_user = $zookeeper_user"
    zookeeper_password=$(echo -e ${vault_output} | jq -r --arg zookeeper_user "$zookeeper_user" '.data.data[$zookeeper_user]')
  fi

  vault_tree_path=$(echo -e ${env_config} | jq -r '.vault_tree_path')
  client_filename=$(dirname $0)/${project}_${env}_$(basename $0).properties
}


client_configs() {
  debug_msg "CLIENT_CONFIGS"          ##<-- debug MSG 6

  # Function is managing client configuration file
  # used to connect to sasl protected clusters
  case $1 in
  create)
    echo -e "Client {\norg.apache.zookeeper.server.auth.DigestLoginModule required\nusername=\"${zookeeper_user}\"\npassword=\"${zookeeper_password}\";\n};" > ${client_filename}
    export KAFKA_OPTS="-Djava.security.auth.login.config=${client_filename}"
    debug_cmd "echo" "KAFKA_OPTS = -Djava.security.auth.login.config=$client_filename"
    ;;
  delete)
    rm -rf ${client_filename}
    unset KAFKA_OPTS
    ;;
  *)
    echo "I don't know who are you!"
    ;;
  esac

  debug=$(ls $client_filename &>2); if [[ $? == 0 ]]; then
  debug_cmd "echo" 'cat client_filename = < client filename >'; fi
  #debug_cmd "cat" "$client_filename"; fi
}


save_password() {
  debug_msg "SAVE_PASSWORD"           ##<-- debug MSG 7

  debug_cmd "echo" "request GET $vault_url/$vault_engine/data/$vault_tree_path"

  # Save credentials to Hashicorp Vault
  vault_output=$(
    curl -s -H "X-Vault-Token: ${vault_token}" \
    --request GET \
    ${vault_url}/${vault_engine}/data/${vault_tree_path}
  )

  check_vault_output $? "${vault_output}"

  new_data=$(echo ${vault_output} | jq -r '.data' | jq -r '.data.'\"${username}\"' = '\"${user_password}\"'')

  echo -e "\nSaving password to Vault:\n"
  debug_cmd "echo" "request POST $vault_url/$vault_engine/data/$vault_tree_path"
  vault_output=$(
    curl -s -H "X-Vault-Token: ${vault_token}" \
    --request POST \
    --data "${new_data}" \
    ${vault_url}/${vault_engine}/data/${vault_tree_path}
  )

  check_vault_output $? "${vault_output}"

  echo -e "Password saved Successfully. Details: ${vault_output}"
#  echo -e "\nCreated user: ${username} with password: ${user_password}"
}


create_user() {
  debug_msg "CREATE_USER"             ##<-- debug MSG 8

  # Create user
  get_kafka_configs

  debug_cmd "echo" "---------DEBUG MSG---------"
  debug_cmd "echo" "check_zookeeper = $check_zookeeper"
  debug_cmd "echo" "username        = $username"
  debug_cmd "echo" "check_user      = $check_user"
  debug_cmd "echo" "check_vault_access = $check_vault_access"

  if check_zookeeper; then
    for username in $(echo -e ${usernames} | tr ',' ' '); do
      if check_user; then
        echo -e "\n\tUser already exists. Skipping creation.."
      else
        echo -e "\tUser was not found. Creating.."
        user_password=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 14)
        if check_vault_access; then
          debug_cmd "echo" "$KAFKA_BIN/kafka-configs.sh --zookeeper ${zookeeper} --alter --add-config SCRAM-SHA-256= iterations=8192,password= 'user_password',SCRAM-SHA-512= iterations=8192,password= 'user_password' "
          $KAFKA_BIN/kafka-configs.sh --zookeeper ${zookeeper} --alter --add-config "SCRAM-SHA-256=[iterations=8192,password=${user_password}],SCRAM-SHA-512=[iterations=8192,password=${user_password}]" \
          --entity-type users --entity-name ${username}
          if [[ $? == 0 ]]; then
            echo -e "\n\tUser ${username} created successfully!"
            save_password
          else
            echo -e "\n\tError occured during user creation!"
            exit -21
          fi
        fi
      fi
    done

    debug_cmd "echo" "run...client_configs delete"
    client_configs delete
  fi
}


# -------------------------------------
# Main section:
# -------------------------------------

# Parsing input parameters
while getopts ":n:t:e:" opt; do
  case "${opt}" in
  n)
    usernames=${OPTARG}
    ;;
  t)
    project=${OPTARG}
    ;;
  e)
    env=${OPTARG}
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND - 1))


echo "------vault-envs-----"
echo "$VAULT_ADDR $VAULT_ENGINE  $VAULT_PATH"
check_kafka_directory
check_params
create_user
