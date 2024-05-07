#!/bin/bash

# -------------------------------------
# Variables section:
# -------------------------------------
num='^[1-9][0-9]*$'

#vault_url="https://vault.lmru.adeo.com/v1/dba"
#vault_engine="Kafka"
#vault_engine_path="EnvironmentMap"

KAFKA_BIN="kafka/bin"	#<-- < this-github-repo >/kafka_automation/scripts/[ kafka/bin ]
LINE=${LINE}conn---     #<-- " ---------------connector---"
DEBUG=$DEBUG            #<-- enable: DEBUG="enable", disable: DEBUG=""
vault_url=$VAULT_URL
vault_engine=$VAULT_ENGINE
vault_engine_path=$VAULT_PATH

ssh_user="root"
ssh_key="central_key"
#ssh_key="/var/lib/jenkins/.ssh/central_key"


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
  echo "Usage: $0 -t <project> -e <environment> -c <connector_config>" 1>&2
  exit 1
}


check_params() {
  debug_msg "CHECK_PARAMS"              ##<-- debug MSG 00
  # Check input parameters are correct

  check_config=$(cat "${connector_config}" | jq)
  [[ $? != 0 ]] && echo -e "Error occured during parsing. Input connector configuration is not a valid json." && exit -2
##  debug_cmd "echo" "check_config = $check_config"

  connector_name=$(cat "${connector_config}" | jq -r '.name')
  [[ ${connector_name} == "null" ]] && echo -e "Error occured during parsing. Missing name key." && exit -3
##  debug_cmd "echo" "connector_name = $connector_name"

  if [ -z "${connector_config}" ] || [ -z "${project}" ]; then usage;  fi
}


check_connector() {
  debug_msg "CHECK_CONNECTOR"           ##<-- debug MSG 0

  # Check if connector already exists or not
  echo -e "Checking if connector ${connector_name} exists:\n"
  debug_cmd "echo" "curl -s --max-time 10 $connect_auth $kafka_connect_url/$connector_name"
  kafka_configs_out=$(curl -s --max-time 10 ${connect_auth} ${kafka_connect_url}/${connector_name})
  #debug_cmd "echo" "kafka_configs_out= $kafka_configs_out"


  if [[ $? != 0 ]]; then
    echo -e "\n\tError occured during connector check!"
    exit -20
  else
    [[ $(echo -e ${kafka_configs_out} | jq -r '.error_code') == "null" ]] && return 0 || return 1
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
  debug_msg "CHECK_VAULT_ACCESS"        ##<-- debug MSG 1

  # Separate function to offload create_user function
  vault_output=$(
    curl -s -H "X-Vault-Token: ${vault_token}" \
    --request GET \
    ${vault_url}/${vault_engine}/data/${vault_engine_path}
  )

  check_vault_output $? "${vault_output}"
  return 0
}


check_connect() {
  debug_msg "CHECK_CONNECT"             ##<-- debug MSG 2

  echo -e "Checking for 1st available kafka connect:\n"

  for connect_host in ${connect_hosts}; do
    kafka_connect_url="http://${connect_host}:${connect_port}/connectors"
	debug_cmd "echo" "curl -s --max-time 10 $connect_auth $kafka_connect_url/$connector_name"
    kafka_configs_out=$(curl -s --max-time 10 ${connect_auth} ${kafka_connect_url}/${connector_name})
	#debug_cmd "echo" "kafka_configs_out= $kafka_configs_out"

    if [[ $? != 0 ]]; then
      echo -e "\tError: Kafka connect ${kafka_connect_url} is not available!.\n"
    else
      echo -e "\tFound available kafka connect: ${kafka_connect_url}\n"
      return 0
    fi
  done
  return 1
}


check_ssh() {
  echo "-----BEGIN OPENSSH PRIVATE KEY-----" > ${ssh_key}
  echo $PRIVATE_KEY > tmp_file;
  sed 's/ --.*$//;s/^.*-- //' tmp_file | sed 's/ /\n/g' | grep -v -P "(BEGIN|OPENSSH|PRIVATE|KEY|END)" >> ${ssh_key}
  echo "-----END OPENSSH PRIVATE KEY-----" >> ${ssh_key}
  
  chmod 600 ${ssh_key}; rm -f tmp_file;
  
  debug=$(ls $ssh_key &>2); if [[ $? == 0 ]]; then
  debug_cmd "echo" 'cat ssh_key = ...'  #; fi
  debug_cmd "cat" "$ssh_key"; fi

  debug_cmd "echo" "ssh -i ssh_key StrictHostKeyChecking=no PasswordAuthentication no ConnectTimeout=10 $ssh_user @ $connect_host"
  ssh -i ${ssh_key} -o StrictHostKeyChecking=no -o "PasswordAuthentication no" -o ConnectTimeout=10 ${ssh_user}@${connect_host} exit
  if [[ $? != 0 ]]; then
    debug_cmd "echo" "func check_ssh() return code 1: $?"
    return 1
  else
    return 0
  fi
	# [[ $? == 0 ]] && return 0 || return 1
}


set_default_params() {
  debug_msg "SET_DEFAULT_PARAMS"        ##<-- debug MSG 3

  # Will set default kafka_partitions = number of kafka brokers_num
  # And default kafka_replication_factor to 3 if there are 3 or more brokers, else - 1
  if [[ -z ${kafka_replication_factor} ]]; then
    if [[ ! -z ${brokers_num} ]] && [[ ${brokers_num} =~ ${num} ]] && [[ ${brokers_num} -ge 3 ]]; then
      kafka_replication_factor=3
    else
      kafka_replication_factor=1
    fi
  fi

  if [[ -z ${kafka_partitions} ]]; then
    if [[ ! -z ${brokers_num} ]] && [[ ${brokers_num} =~ ${num} ]]; then
      kafka_partitions=${brokers_num}
    fi
  fi

  if [[ ! $(grep "topic.creation.default.partitions" "${connector_config}") ]]; then
    sed -i ${connector_config} -e "s#\(\"config\" *: *{\)#\1\n\t\"topic.creation.default.partitions\": \"${kafka_partitions}\",#g"
  fi

  if [[ ! $(grep "topic.creation.default.replication.factor" "${connector_config}") ]]; then
    sed -i ${connector_config} -e "s#\(\"config\" *: *{\)#\1\n\t\"topic.creation.default.replication.factor\": \"${kafka_replication_factor}\",#g"
  fi
}


secure_connector_config() {
  debug_msg "SEQURE_CONNECTOR_CONFIG"   ##<-- debug MSG 4

  if [[ $(grep KafkaSourceConnector ${connector_config}) ]]; then
    echo -e "Mirror tool has no credentials. Nothing to secure!"
    secured_connector_config=${connector_config}
  else
    if [[ $(grep MongoDbConnector ${connector_config}) ]]; then
      user=$(cat ${connector_config} | jq -r '.config["mongodb.user"]')
      password=$(cat ${connector_config} | jq -r '.config["mongodb.password"]')
      secured_credentials="${connector_name}.mongodb.user=${user}\n${connector_name}.mongodb.password=${password}"
      secured_connector_config=$(cat ${connector_config} | jq | sed -e 's#"mongodb.user":.*,#"mongodb.user":"${file:'"${connect_secure_file_path}"':'"${connector_name}"'.mongodb.user}",#g' -e 's#"mongodb.password":.*,#"mongodb.password":"${file:'"${connect_secure_file_path}"':'"${connector_name}"'.mongodb.password}",#g')
    else
      if [[ $(grep MongoSourceConnector ${connector_config}) ]]; then
        uri=$(cat ${connector_config} | jq -r '.config["connection.uri"]')
        secured_credentials="${connector_name}.connection.uri=${uri}"
        secured_connector_config=$(cat ${connector_config} | jq | sed -e 's#"connection.uri":.*,#"connection.uri":"${file:'"${connect_secure_file_path}"':'"${connector_name}"'.connection.uri}",#g')
      else
        if [[ $(grep JdbcSourceConnector ${connector_config}) ]]; then
          user=$(cat ${connector_config} | jq -r '.config["connection.user"]')
          password=$(cat ${connector_config} | jq -r '.config["connection.password"]')
          secured_credentials="${connector_name}.connection.user=${user}\n${connector_name}.connection.password=${password}"
          secured_connector_config=$(cat ${connector_config} | jq | sed -e 's#"connection.user":.*,#"connection.user":"${file:'"${connect_secure_file_path}"':'"${connector_name}"'.connection.user}",#g' -e 's#"connection.password":.*,#"connection.password":"${file:'"${connect_secure_file_path}"':'"${connector_name}"'.connection.password}",#g')
        else
          user=$(cat ${connector_config} | jq -r '.config["database.user"]')
          password=$(cat ${connector_config} | jq -r '.config["database.password"]')
          secured_credentials="${connector_name}.database.user=${user}\n${connector_name}.database.password=${password}"
          secured_connector_config=$(cat ${connector_config} | jq | sed -e 's#"database.user":.*,#"database.user":"${file:'"${connect_secure_file_path}"':'"${connector_name}"'.database.user}",#g' -e 's#"database.password":.*,#"database.password":"${file:'"${connect_secure_file_path}"':'"${connector_name}"'.database.password}",#g')
        fi
      fi
    fi
  fi
}


update_secure_file() {
  debug_msg "UPDATE_SECURE_FILE"        ##<-- debug MSG 5

  echo -e "\n\tAddind credentials to connect secure file\n"
  for connect_host in ${connect_hosts}; do
    if check_ssh; then
      debug_cmd "echo" "ssh -i ssh_key -o StrictHostKeyChecking=no ${ssh_user}@${connect_host}  secured_credentials >>..."
      ssh -i ${ssh_key} -o StrictHostKeyChecking=no ${ssh_user}@${connect_host} "echo -e \"${secured_credentials}\" >> ${connect_secure_file_path}"
    else
      debug_cmd "echo" "func check_ssh() return code 1: $?"
      echo -e "Error connecting to ${connect_host} with private key file!"
      exit -50
    fi
  done
}


get_vault_token() {
  debug_msg "GET_VAULT_TOKEN"           ##<-- debug MSG 6

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


get_kafka_configs() {
  debug_msg "GET_KAFKA_CONFIGS"         ##<-- debug MSG 7

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
  connect_hosts=$(echo -e ${env_config} | jq -r '.connect_hosts[]?')
  connect_port=$(echo -e ${env_config} | jq -r '.connect_port')

  [[ ${connect_hosts} == "" || connect_port == "null" ]] && echo "There are no Kafka-connect hosts or port defined for ${project} ${env} enviroment!" && exit 0

  connect_auth_path=$(echo -e ${env_config} | jq -r '.vault_connect_auth_path // ""')
  connect_secure_file_path=$(echo -e ${env_config} | jq -r '.connect_secure_file_path // ""')
  vault_connectors_config_path=$(echo -e ${env_config} | jq -r '.vault_connectors_config_path // ""')

  if [[ ${connect_auth_path} != "" ]]; then
    debug_cmd "echo" "request GET $vault_url}/$vault_engine/data/$connect_auth_path"
    vault_output=$(curl -s -H "X-Vault-Token: ${vault_token}" --request GET ${vault_url}/${vault_engine}/data/${connect_auth_path})
    check_vault_output $? "${vault_output}"
    connect_user=$(echo -e ${vault_output} | jq -r '.data.data | keys[0]')
    connect_password=$(echo -e ${vault_output} | jq -r --arg connect_user "$connect_user" '.data.data[$connect_user]')
    connect_auth="-u ${connect_user}:${connect_password}"
  fi
  brokers_num=$(echo -e ${env_config} | jq -r '.broker_hosts | length')
}


save_connector_config() {
  debug_msg "SAVE_CONNECTOR_CONFIG"     ##<-- debug MSG 8
  # Save credentials to Hashicorp Vault

  echo -e "\nSaving connector to Vault:\n"
  vault_connector_config=$(cat ${connector_config})

  debug_cmd "echo" "request POST (data : vault_connector_config) $vault_url/$vault_engine/data/$vault_connectors_config_path/$connector_name"

  vault_output=$(
    curl -s -H "X-Vault-Token: ${vault_token}" \
    --request POST \
    --data "{\"data\":${vault_connector_config}}" \
    ${vault_url}/${vault_engine}/data/${vault_connectors_config_path}/${connector_name}
  )

  check_vault_output $? "${vault_output}"
  echo -e "\tConnector configuration saved Successfully. \n\tDetails: ${vault_output}"
}


create_connector() {
  debug_msg "CREATE_CONNECTOR"          ##<-- debug MSG 9

  # Create user
  get_kafka_configs

  debug_cmd "echo" "---------DEBUG MSG---------"
  debug_cmd "echo" "check_connect      = $check_connect"
  debug_cmd "echo" "connect_auth       = $connect_auth"
  debug_cmd "echo" "connector_name     = $connector_name"
  debug_cmd "echo" "check_vault_access = $check_vault_access"

  if check_connect; then
    if check_connector; then
      echo -e "\tConnector already exists. Skipping creation.."
    else
      echo -e "\tConnector was not found. Creating.."
      if check_vault_access; then
        set_default_params
        if [[ ${connect_auth} != "" ]]; then
          secure_connector_config
          update_secure_file
        else
          secured_connector_config=$(cat ${connector_config})
        fi
        save_connector_config

	debug_cmd "echo" "request POST (data : secured_connector_config) secured_connector_config $kafka_connect_url"
        kafka_configs_out=$(curl -s ${connect_auth} -X POST -H "Content-Type: application/json" --data "${secured_connector_config}" ${kafka_connect_url})

        if [[ $? == 0 ]]; then
          if [[ $(echo ${kafka_configs_out} | jq -r '.error_code') == "null" ]]; then
            echo -e "\nConnector ${connector_name} created successfully!"
          else
            echo -e "\nError occured during connector creation!"
            echo -e "\n\t${kafka_configs_out}"
            exit -31
          fi
        else
          echo -e "\n\tError occured during connector creation!"
          exit -21
        fi
      fi
    fi
  else
    echo -e "\n\tFatal: No available connect node detected!"
    exit -11
  fi
}

# -------------------------------------
# Main section:
# -------------------------------------

# Parsing input parameters
while getopts ":c:t:e:" opt; do
  case "${opt}" in
  c) connector_config=${OPTARG};;
  t) project=${OPTARG};;
  e) env=${OPTARG};;
  *) usage;;
  esac
done
shift $((OPTIND - 1))

echo "------vault-envs-----"
echo "$VAULT_ADDR $VAULT_ENGINE  $VAULT_PATH"
#echo "PRIVATE_KEY = $PRIVATE_KEY"   <-- remove agter debug

check_params
create_connector
