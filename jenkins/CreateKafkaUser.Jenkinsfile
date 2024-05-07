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


node ('lmru-dockerhost') {		//<-- changed. old was: node('dockerhost')
          stage('Parameters'){
	      checkout scm
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
                          string(name: 'username', description: 'Enter Username'),
                          [$class: 'ChoiceParameter',
                              choiceType: 'PT_SINGLE_SELECT',
                              description: 'Select the role for the user (permissions)',
                              filterLength: 1,
                              filterable: false,
                              name: 'role',
                              script: [
                                  $class: 'GroovyScript',
                                  fallbackScript: [
                                      classpath: [],
                                      sandbox: true,
                                      script:
                                          "return['Could not get The roles']"
                                  ],
                                  script: [
                                      classpath: [],
                                      sandbox: true,
                                      script:
                                          "return['read_only','write_only','all']"
                                  ]
                              ]
                          ],
                          choice(name: 'create_user', choices: ['yes','no'], description: 'Whether to create a new user, if you want to assign permissions to an existant user choose no'),
                          string(name: 'topic_name', description: 'Enter topic name that the user will be granted acceess to'),
                          choice(name: 'pattern_type', choices: ['literal','prefixed'], description: 'Choose literal to match exact topics name, or prefixed for simmilar-named multiple topics'),
                          string(name: 'group_name', description: 'Enter consumer group name that the user will be granted acceess to')
                      ])
                  ])
          }
      }

            //<---- check IP node jenkins
                    def nodeip = sh (script: 'dig +short myip.opendns.com @resolver1.opendns.com', returnStdout: true).trim()
            //<---- start get token ----
		    currentBuild.description = 'CLUSTER = ' + params.cluster + '. ENV = ' + params.env + '. IP = ' + nodeip
		    String endpoint = vault.url + '/v1/' + vault.namespace

		    withCredentials([usernamePassword(credentialsId: vault.approle_cred, usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                      auth_json = readJSON text: (sh(returnStdout: true, script: "curl --request POST --data \'{\"role_id\":\"$USERNAME\",\"secret_id\":\"$PASSWORD\"}\' ${vault.url}/v1/${vault.namespace}/auth/approle/login").trim())
                      vault.token = "${auth_json.auth.client_token.toString()}"
		    }
            //<---- start withenv ----
	              echo "vault.token = $vault.token"
                      withEnv([
		           "VAULT_ADDR=$vault.url", "VAULT_TOKEN=$vault.token",
		           "VAULT_ENGINE=$vault.engine", "VAULT_PATH=$vault.engine_path",
			   "VAULT_URL=$endpoint", "DEBUG=$debug.mode", "LINE=$debug.line",
		      ]) {

            dir("kafka_automation/scripts/") {

            //<---- #1. create user ----
            stage('Create user') {
	    if(params.username != '') { if(params.create_user == 'yes') {
	        sh """./create_user.sh -n \$username -t \$cluster -e \$env"""
            }}}


            //<---- #2. permissions ----
            stage('Assign permissions') {
	    if(params.topic_name != '') { 
		      def permissions = 'rwdkv'
		      if(      params.role == 'read_only' ) { permissions = 'rd' }
		      else if (params.role == 'write_only') { permissions = 'wd' }
	       
		      sh "./assign_acl.sh -u \$username -t \$cluster -e \$env -o topic -n \$topic_name -p \$pattern_type -${permissions}"
            }}


            //<---- #3. grants -----
            stage('Grant permissions to consumer group') {
	    if(params.group_name != '') {
                      sh """./assign_acl.sh -u \$username -t \$cluster -e \$env -o group -n \$group_name -p prefixed -rd"""
	    }}

            }
            //<---- end dir ----
                      }
            //<---- end withenv ----
                      }
            //<---- end get token ----
