#!/bin/bash

# -------------------------------------
# Variables section:
# -------------------------------------

num='^[1-9][0-9]*$'

KAFKA_BIN="kafka/bin"	#<-- < this-github-repo >/kafka_automation/scripts/[ kafka/bin ]
LINE=${LINE}topic--     #<-- " --------------------topic--"
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
  echo "Usage: $0 -t <project> -e <environment> -n <kafka-topic-name> [-r <replication-factor>] [-p <partitions-number>] [-c <configuration-parameters>]" 1>&2
  exit 1
}


check_params() {
  # Check input parameters are correct
  if [ -z "${project}" ] || [ -z "${env}" ] || [ -z "${kafka_topic_names}" ]; then
    usage
  fi

  if ! [[ -z ${kafka_replication_factor} ]]; then
    if ! [[ ${kafka_replication_factor} =~ ${num} ]]; then
      echo "Error: replication-factor must be a positive number" >&2
      exit -10
    fi
  fi

  if ! [[ -z ${kafka_partitions} ]]; then
    if ! [[ ${kafka_partitions} =~ ${num} ]]; then
      echo "Error: kafka_partitions must be a positive number" >&2
      exit -10
    fi
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


get_vault_token() {
  debug_msg "GET_VAULT_TOKEN"       ##<-- debug MSG 0

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
  debug_msg "CHECK_KAFKA_DIR"         ##<-- debug MSG 1
  kafka_dir_output=$(ls $KAFKA_BIN | grep sh | wc -l)
  if [[ $? != 0 ]]; then
     echo -e "\n\tNo executable .sh in $KAFKA_BIN!"
     exit
  else
    echo -e "\n\tKafka Command line in $KAFKA_BIN: FOUND success!"
  fi
}


get_kafka_configs() {
  debug_msg "GET_KAFKA_CONFIGS"       ##<-- debug MSG 2
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

  broker_port=$(echo -e ${env_config} | jq -r '.broker_port')
  bootstrap=$(echo -e ${env_config} | jq -r --arg broker_port "$broker_port" '.broker_hosts | join(":"+$broker_port+",") + ":"+$broker_port')
  brokers_num=$(echo -e ${env_config} | jq -r '.broker_hosts | length')
  vault_tree_path=$(echo -e ${env_config} | jq -r '.vault_tree_path')

  debug_cmd "echo" "request GET $vault_url/$vault_engine/data/$vault_tree_path"

  vault_output=$(
    curl -s -H "X-Vault-Token: ${vault_token}" \
    --request GET \
    ${vault_url}/${vault_engine}/data/${vault_tree_path}
  )

  check_vault_output $? "${vault_output}"

  admin_password=$(echo -e "${vault_output}" | jq -r '.data.data.admin')
  client_filename=$(dirname $0)/${project}_${env}_$(basename $0).properties

  [[ ${broker_port} == "9093" || ${broker_port} == "9091" ]] && command_config="--command-config ${client_filename}"

}


client_configs() {
  debug_msg "CLIENT_CONFIGS"         ##<-- debug MSG 3

  # Function is managing client configuration file
  # used to connect to sasl protected clusters
  case $1 in
  create) echo -e "sasl.mechanism=SCRAM-SHA-256\nsecurity.protocol=SASL_PLAINTEXT\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"admin\" password=\"${admin_password}\";" > ${client_filename}
    ;;
  delete) rm -rf ${client_filename}
    ;;
  *)     echo "I don't know who are you!"
    ;;
  esac

  debug=$(ls $client_filename &>2); if [[ $? == 0 ]]; then
  debug_cmd "echo" 'cat client_filename = ...'; #fi
  debug_cmd "cat" "$client_filename"; fi
}


check_bootstrap() {
  debug_msg "CHECK_BOOTSTRAP"         ##<-- debug MSG 4

  # Check if kafka cluster is accessible
  client_configs create
  echo -e "Checking for kafka cluster availability:\n"

  debug_cmd "echo" "$KAFKA_BIN/kafka-configs.sh --bootstrap-server $bootstrap --describe --entity-type brokers $command_config 2>..."
  kafka_configs_out=$($KAFKA_BIN/kafka-configs.sh --bootstrap-server ${bootstrap} --describe --entity-type brokers ${command_config} 2> >(egrep -v "isn't a known config"))

  debug_cmd "echo" 'echo kafka_configs_out = '
  debug_cmd "echo" "$kafka_configs_out"

  if [[ $? != 0 ]]; then
    echo -e "\tError: Couldn't connect to kafka brokers!\n"
    return 1
  else
    echo -e "\tSuccess: Connected to kafka brokers!"
    return 0
  fi
}


set_default_params() {
  debug_msg "SET_DEFAULT_PARAMS"      ##<-- debug MSG 5

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
}


check_topic() {
  debug_msg "CHECK_TOPIC"            ##<-- debug MSG 6

  # Check if topic already exists or not
  echo -e "\nChecking if topic ${kafka_topic} exists:"
  kafka_topics_out=$(kafka-topics --list --bootstrap-server ${bootstrap} --topic ${kafka_topic} ${command_config} 2> >(egrep -v "isn't a known config"))

  debug_cmd "echo" "$KAFKA_BIN/kafka-topics.sh --list --bootstrap-server $bootstrap --topic $kafka_topic $command_config 2>..."
  kafka_topics_out=$($KAFKA_BIN/kafka-topics.sh --list --bootstrap-server ${bootstrap} --topic ${kafka_topic} ${command_config} 2> >(egrep -v "isn't a known config"))
  debug_cmd "echo" 'kafka_topics_out = '
  debug_cmd "echo" "$kafka_topics_out"

  if [[ $? != 0 ]]; then
    echo "kafka_topics_out returns: $?"
    echo -e "\n\tError occured during topic check!"
    exit -20
  else
    [[ ${kafka_topics_out} == ${kafka_topic} ]] && return 0 || return 1
  fi
}


create_topic() {
  debug_msg "CHECK_TOPIC"            ##<-- debug MSG 7

  # Create topic
  get_kafka_configs

  if check_bootstrap; then
    for kafka_topic in $(echo -e ${kafka_topic_names} | tr ',' ' '); do
      if check_topic; then
        echo -e "\nTopic already exists. Skipping creation.."
      else
        echo -e "\n\tTopic was not found. Creating..\n"
        set_default_params
        $KAFKA_BIN/kafka-topics.sh --create --bootstrap-server ${bootstrap} --replication-factor ${kafka_replication_factor} --partitions ${kafka_partitions} --topic ${kafka_topic} ${kafka_topic_config} ${command_config} 2> >(egrep -v "isn't a known config")
        if [[ $? != 0 ]]; then
          echo -e "\tError occured during topic creation!"
          exit -30
        fi
      fi
    done
    client_configs delete
  fi
}

# -------------------------------------
# Main section:
# -------------------------------------

# Parsing input parameters
while getopts ":t:e:u:n:c:r:p:" opt; do
  case "${opt}" in
  t) project=${OPTARG};;
  e) env=${OPTARG};;
  n) kafka_topic_names=${OPTARG};;
  c) kafka_topic_config="${kafka_topic_config} --config ${OPTARG}";;
  r) kafka_replication_factor=${OPTARG};;
  p) kafka_partitions=${OPTARG};;
  *) usage;;
  esac
done
shift $((OPTIND - 1))


echo "------vault-envs-----"
echo "$VAULT_ADDR $VAULT_ENGINE  $VAULT_PATH"
check_kafka_directory
check_params
create_topic
