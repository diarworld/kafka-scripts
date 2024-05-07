vault = [
    url:          'https://vault.lmru.tech',
    cred_id:      'vault-approle',
    token:        '',
    approle_cred: 'vault-approle-jenkins',
    namespace:    'dataplatform',
    engine:       'Kafka',
    engine_path:  'EnvironmentMap'
]
vault_config = [
    vaultUrl: vault.url,
    vaultCredentialId: vault.cred_id,
    vaultNamespace: vault.namespace
]
debug = [
    mode: "on",	   //<-- mode: "" -means disable, mode: "any string" -means enable
    line: " -------------------"
]


pipeline {
    agent {
        node { label 'lmru-dockerhost' }
    }
        stages {
        stage('Parameters'){
            steps {
                script {
                properties([
                        parameters([
                            [$class: 'ChoiceParameter',
                                choiceType: 'PT_SINGLE_SELECT',
                                description: 'Select the Kafka cluster from the Dropdown List',
                                filterLength: 1,
                                filterable: false,
                                name: 'cluster',
                                script: [
                                    $class: 'GroovyScript',
                                    fallbackScript: [
                                        classpath: [],
                                        sandbox: true,
                                        script:
                                            "return['Could not get The projects']"
                                    ],
                                    script: [
                                        classpath: [],
                                        sandbox: true,
                                        script:
                                            "return['DataPlatform','KFK4U','MDM','Presale','StockRepository','Fulfillmеnt','RMSInboundLogistics','RMSValuableSalePrice','RMSMarketDevelopment','RMSPartnerEngagement','RMSFinance','RMSShared','RMSSearchEngine','RMSReplenishmentAndImport','WMSInbound']"
                                    ]
                                ]
                            ],
                            [$class: 'CascadeChoiceParameter',
                                choiceType: 'PT_SINGLE_SELECT',
                                description: 'Select the Environment from the Dropdown List',
                                name: 'env',
                                referencedParameters: 'cluster',
                                script:
                                    [$class: 'GroovyScript',
                                    fallbackScript: [
                                            classpath: [],
                                            sandbox: true,
                                            script: "return['Could not get Environment from cluster Param']"
                                            ],
                                    script: [
                                            classpath: [],
                                            sandbox: true,
                                            script: '''
                                            if (cluster.equals("DataPlatform")){
                                                return["prod", "test"]
                                            }
                                            else if(cluster.equals("KFK4U")){
                                                return["prod", "test"]
                                            }
                                            else if(cluster.equals("MDM")){
                                                return["prod", "preprod", "test"]
                                            }
                                            else if(cluster.equals("Presale")){
                                                return["prod", "preprod", "test"]
                                            }
                                            else if(cluster.equals("StockRepository")){
                                                return["prod", "preprod", "test"]
                                            }
                                            else if(cluster.equals("Fulfillmеnt")){
                                                return["prod", "preprod", "test"]
                                            }
                                            else if(cluster.equals("StockRepository")){
                                            return["prod", "preprod", "test"]
                                            }
                                            else if(cluster.equals("Fulfillmеnt")){
                                            return["prod", "preprod", "test"]
                                            }
                                            else if(cluster.equals("RMSValuableSalePrice")){
                                            return["prod", "test"]
                                            }
                                            else if(cluster.equals("RMSPartnerEngagement")){
                                            return["prod", "test"]
                                            }
                                            else if(cluster.equals("RMSFinance")){
                                            return["prod", "test"]
                                            }
                                            else if(cluster.equals("RMSShared")){
                                            return["test"]
                                            }
                                            else if(cluster.equals("RMSSearchEngine")){
                                            return["prod"]
                                            }
                                            else if(cluster.equals("RMSReplenishmentAndImport")){
                                            return["prod", "test"]
                                            }
                                            else if(cluster.equals("WMSInbound")){
                                            return["prod", "preprod","test"]
                                            }
                                           '''
                                        ]
                                ]
                            ],
                            string(name: 'topic_name', description: 'Enter topic name that will be created'),
                            choice(name: 'cleanup_policy', choices: ['delete','compact','delete,compact'], description: 'Choose topic cleanup policy'),
                            string(name: 'partitions_number', description: 'Leave blank for default or enter partitions number for the topic'),
                            string(name: 'replication_factor', description: 'Leave blank for default or enter replication factor for the topic'),
                            string(name: 'retention', description: 'Enter retention in ms that the topic will have, leave empty for cluster default value')
                        ])
                    ])
                }
            }
        }

            stage('Create topic') {
                steps {
                    dir("kafka_automation/scripts/")
                    {
            //<---- start script ----
                    script {
		    currentBuild.description = 'CLUSTER = ' + params.cluster + '. ENV = ' + params.env
		    //echo "set currentBuild.description = ${currentBuild.description}
		    
                    String endpoint = vault.url + '/v1/' + vault.namespace

		    withCredentials([usernamePassword(credentialsId: vault.approle_cred, usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                      auth_json = readJSON text: (sh(returnStdout: true, script: "curl --request POST --data \'{\"role_id\":\"$USERNAME\",\"secret_id\":\"$PASSWORD\"}\' ${vault.url}/v1/${vault.namespace}/auth/approle/login").trim())
                      vault.token = "${auth_json.auth.client_token.toString()}"

            //<---- start withenv ----

                      withEnv([
		           "VAULT_ADDR=$vault.url", "VAULT_TOKEN=$vault.token",
		           "VAULT_ENGINE=$vault.engine", "VAULT_PATH=$vault.engine_path",
			   "VAULT_URL=$endpoint", "DEBUG=$debug.mode", "LINE=$debug.line",
                      ]) {
                    sh """
                    script_params=''
                    [[ \$replication_factor != '' ]] && script_params="\${script_params} -r \$replication_factor"
                    [[ \$partitions_number != '' ]] && script_params="\${script_params} -p \$partitions_number"
		    [[ \$retention != '' ]] && script_params="\${script_params} -c retention.ms=\$retention"
                    [[ \$cleanup_policy != '' ]] && script_params="\${script_params} -c cleanup.policy=\$cleanup_policy"
		         ./create_topic.sh -t \$cluster -e \$env -n \$topic_name \${script_params}
                    """
                      }
            //<---- end withenv ----
                    }}
            //<---- end script ----
                 }

             }
        }
    }
}
