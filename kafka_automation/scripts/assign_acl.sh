#!/bin/bash

# -------------------------------------
# Variables section:
# -------------------------------------

pattern="Configs for user-principal .* are SCRAM"
kafka_host="--allow-host '*'"
kafka_authorizer="--authorizer kafka.security.auth.SimpleAclAuthorizer --authorizer-properties"

KAFKA_BIN="kafka/bin"	#<-- < this-github-repo >/kafka_automation/scripts/[ kafka/bin ]
LINE=${LINE}-acl---     #<-- " ---------------------acl---"
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
  echo -e "\nUsage: $0 -u <usernames> -t <project> -e <environment> -o <object-type> []-n <object-names>] [-rwcda] [-h <host>] [-p <pattern-type>]\n" 1>&2
  echo -e "\t-o < object-type: topic | group | cluster >"
  echo -e "\t-p < pattern-type: prefixed | literal | match | any >"
  echo -e "\tPermissions keys:\n\t\t-r - Read\n\t\t-w <Write>\n\t\t-c <Create>\n\t\t-d <Describe>\n\t\t-a <Alter>\n\t\t-k <Delete>"
  exit 1
}


check_params() {
  # Check input parameters are correct
  if [ -z "${usernames}" ] || [ -z "${project}" ] || [ -z "${env}" ] || [ -z "${kafka_object_type}" ]; then usage; fi
  if [ -z ${kafka_object_names} ]; then kafka_object_names='*'; fi
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


check_kafka_directory() {
  debug_msg "CHECK_KAFKA_DIR"         ##<-- debug MSG 0

  kafka_dir_output=$(ls $KAFKA_BIN | grep sh | wc -l)
  if [[ $? != 0 ]]; then
     echo -e "\n\tNo executable .sh in $KAFKA_BIN!"
     exit
  else
    echo -e "\n\tKafka Command line in $KAFKA_BIN: FOUND success!"
  fi
}


check_zookeeper() {
  debug_msg "CHECK_ZOOKEEPER"         ##<-- debug MSG 1

  # Check for available zookeeper from configuration (in case of maintenance of some nodes)
  [[ ${zookeeper_auth_path} != "" ]] && client_configs create
  echo -e "Checking for 1st available zookeeper:\n"

#  for zookeeper_host in ${zookeeper_hosts}; do
#    zookeeper=${zookeeper_host}:${zookeeper_port}${zookeeper_tree}
#    debug_cmd "echo" "$KAFKA_BIN/kafka-configs.sh --zookeeper $zookeeper --describe --entity-name $usernames --entity-type users"
#    kafka_configs_out=$($KAFKA_BIN/kafka-configs.sh --zookeeper ${zookeeper} --describe --entity-name ${usernames} --entity-type users)
#
#    if [[ $? != 0 ]]; then
#      echo -e "\tError: zookeeper ${zookeeper} is not available!.\n"
#    else
#      echo -e "\tFound available zookeeper: ${zookeeper}\n"
#      return 0
#    fi
#  done
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
  debug_msg "GET_VAULT_TOKEN"         ##<-- debug MSG 2

  vault_token=$VAULT_TOKEN

  debug_cmd "echo" "$VAULT_ADDR"
  debug_cmd "echo" 'get vault_token from environment'
#  debug_cmd "echo" "$vault_token"
}


get_kafka_configs() {
  debug_msg "GET_KAFKA_CONFIGS"       ##<-- debug MSG 3

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
    debug_cmd "echo" "zookeeper_user= $zookeeper_user"
    zookeeper_password=$(echo -e ${vault_output} | jq -r --arg zookeeper_user "$zookeeper_user" '.data.data[$zookeeper_user]')
  fi

  vault_tree_path=$(echo -e ${env_config} | jq -r '.vault_tree_path')
  client_filename=$(dirname $0)/${project}_${env}_$(basename $0).properties
}


client_configs() {
  debug_msg "CLIENT_CONFIGS"          ##<-- debug MSG 4

  # Function is managing client configuration file
  # used to connect to sasl protected clusters
  case $1 in
  create)
    echo -e "Client {\norg.apache.zookeeper.server.auth.DigestLoginModule required\nusername=\"${zookeeper_user}\"\npassword=\"${zookeeper_password}\";\n};" > ${client_filename}
    export KAFKA_OPTS="-Djava.security.auth.login.config=${client_filename}"
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
  debug_cmd "echo" 'cat client_filename = ...'; fi
#  debug_cmd "cat" "$client_filename"; fi
}


check_user() {
  debug_msg "CHECK_USER"              ##<-- debug MSG 5

  # Check if user already exists or not
  echo -e "Checking if user exists:\n"
  debug_cmd "echo" "$KAFKA_BIN/kafka-configs.sh --zookeeper $zookeeper --describe --entity-name $username --entity-type users | egrep $pattern"
  $KAFKA_BIN/kafka-configs.sh --zookeeper ${zookeeper} --describe --entity-name ${username} --entity-type users | egrep "${pattern}" && return 0 || return 1

  if [[ $? != 0 ]]; then
    echo -e "\n\tError occured during user check!"
    exit -20
  else
    return 0
  fi
}


assign_acl() {
  debug_msg "ASSIGN_ACL"              ##<-- debug MSG 6

  get_kafka_configs

  debug_cmd "echo" "---------DEBUG MSG---------"
  debug_cmd "echo" "check_zookeeper = $check_zookeeper"
  debug_cmd "echo" "username        = $username"
  debug_cmd "echo" "check_user      = $check_user"

  if check_zookeeper; then
    for username in $(echo -e ${usernames} | tr ',' ' '); do
      if check_user; then
        echo -e "\n\tUser exists. Assigning ACL.."
        for kafka_object_name in $(echo -e ${kafka_object_names} | tr ',' ' '); do
          echo -e "$KAFKA_BIN/kafka-acls.sh ${kafka_authorizer} zookeeper.connect=${zookeeper} --add --allow-principal User:${username} ${allow_host} ${kafka_permissions} ${kafka_object_type} ${kafka_object_name} ${kafka_pattern_type}"
          $KAFKA_BIN/kafka-acls.sh ${kafka_authorizer} zookeeper.connect=${zookeeper} --add --allow-principal User:${username} ${allow_host} ${kafka_permissions} ${kafka_object_type} "${kafka_object_name}" ${kafka_pattern_type}
          if [[ $? == 0 ]]; then
            echo -e "\n\tACL for ${username} assigned successfully!"
          else
            echo -e "\n\tError occured during ACL assigning!"
            exit -21
          fi
        done
      else
        echo -e "\n\tUser doesn't exists. Skipping.."
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
while getopts ":t:e:u:h:o:n:p:rwckdav" opt; do
  case "${opt}" in
  u)  usernames=${OPTARG};;
  t)  project=${OPTARG};;
  e)  env=${OPTARG};;
  r)  kafka_permissions="${kafka_permissions} --operation Read";;
  w)  kafka_permissions="${kafka_permissions} --operation Write";;
  c)  kafka_permissions="${kafka_permissions} --operation Create";;
  k)  kafka_permissions="${kafka_permissions} --operation Delete";;
  v)  kafka_permissions="${kafka_permissions} --operation DescribeConfigs";;
  d)  kafka_permissions="${kafka_permissions} --operation Describe";;
  a)  kafka_permissions="${kafka_permissions} --operation Alter";;
  h)  allow_host="--allow-host '${OPTARG}'";;
  o) case "${OPTARG}" in 
	topic) kafka_object_type="--topic";;
    group)  kafka_object_type="--group";;
    cluster) kafka_object_type="--cluster";;
    *) usage;;
    esac
    ;;
  p) case "${OPTARG}" in
    prefixed) kafka_pattern_type="--resource-pattern-type prefixed";;
    literal) kafka_pattern_type="--resource-pattern-type literal";;
    match) kafka_pattern_type="--resource-pattern-type match";;
    any) kafka_pattern_type="--resource-pattern-type any";;
    *) usage;;
    esac
    ;;
  n) kafka_object_names="${OPTARG}";;
  *) usage;;
  esac
done
shift $((OPTIND - 1))


check_kafka_directory
check_params
assign_acl
