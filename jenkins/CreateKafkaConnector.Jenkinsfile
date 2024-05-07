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
                                                "return['DataPlatform','KFK4U','MDM','Presale','StockRepository','Fulfillmеnt']"
                                        ]
                                    ]
                                ],
                                [$class: 'CascadeChoiceParameter',
                                    choiceType: 'PT_SINGLE_SELECT',
                                    description: 'Select the Environment from the Dropdown List',
                                    name: 'environment',
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
						'''
                                            ]
                                    ]
                                ],
                                text(name: 'config',  description: 'Paste connector json config file with password and db username in plain text')
                            ])
                        ])
                    }
                }
            }

            stage('Create connector') {
                steps {
                    dir("kafka_automation/scripts/")
                    {
            //<---- start script ----
                    script {
		    currentBuild.description = 'CLUSTER = ' + cluster + '. ENV = ' + environment
		    //def descr = 'cluster=' + cluster + 'environ=' + environment
		    echo "set currentBuild.description = ${currentBuild.description}"
		    
		    writeFile(file: "/tmp/${environment}_${cluster}_connector.json", text: params.config)
                    String endpoint = vault.url + '/v1/' + vault.namespace

		    withCredentials([usernamePassword(credentialsId: vault.approle_cred, usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                      auth_json = readJSON text: (sh(returnStdout: true, script: "curl --request POST --data \'{\"role_id\":\"$USERNAME\",\"secret_id\":\"$PASSWORD\"}\' ${vault.url}/v1/${vault.namespace}/auth/approle/login").trim())
                      vault.token = "${auth_json.auth.client_token.toString()}"


            //<---- get ssh from Vault with cluster params ----
		    withVault([configuration: vault_config, vaultSecrets: [
                        [ path: "/Kafka/kafka_connect/root",
                          engineVersion: 2,
                          secretValues: [[ envVar: 'PRIVATE_KEY', vaultKey: "${environment}" ]]
                    //    [ path: "/Kafka/kafka_connect_ssh/${environment}",
                    //      engineVersion: 2,
                    //      secretValues: [[ envVar: 'PRIVATE_KEY', vaultKey: "${cluster}" ]]
                        ]
	            ]]) {
		    	//echo "SSH_KEY=${env.PRIVATE_KEY}"
		    

            //<---- start withenv ----

                      withEnv([
                           "VAULT_ADDR=$vault.url", "VAULT_TOKEN=$vault.token",
                           "VAULT_ENGINE=$vault.engine", "VAULT_PATH=$vault.engine_path",
                           "VAULT_URL=$endpoint", "DEBUG=$debug.mode", "LINE=$debug.line",
                      ]) {
		      //<---- debug msg ----
		      //sh "pwd; ls; ls /tmp"
		      
                      sh """
                        ./create_connector.sh -t \$cluster -e \$environment -c /tmp/\${environment}_\${cluster}_connector.json
                        """
                      }
            //<---- end withenv ----
	             }
            //<---- end get ssh ----
                    }}
            //<---- end script ----
                    }
            //<---- end dir ----
	            cleanWs()		//<-- Clean workspace
                }
            }
    }
}
