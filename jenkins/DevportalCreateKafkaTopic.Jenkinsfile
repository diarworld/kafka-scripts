pipeline {
    agent any
        stages {
            stage('Parameters'){
                steps {
                    script {
                    properties([
                            parameters([
                            string(name: 'callbackURL', description: 'Callback url for devportal'),
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
                                                "return['DataPlatform','KFK4U','MDM','Presale','StockRepository','Fulfillmеnt','BigfishWMS','WMSInbound']"
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
                                                else if (cluster.equals("BigfishWMS")){
                                                    return["prod", "preprod", "test"]
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
                                string(name: 'retention', description: 'Enter retention in ms that the topic will have, leave empty for cluster default value'),
                                string(name: 'username', description: 'Enter username which would be created with write permissions')
                            ])
                        ])
                    }
                }
            }
            stage('Send hook') {
                  steps {
                      dir("kafka_automation/scripts/")
                      {
                      sh """
                      curl -X POST -H "Content-Type: application/json" -H "Authorization: \$(cat /var/lib/jenkins/.devportal/token)" \$callbackURL -d '{"jobName" : "DevportalCreateKafkaTopic", "buildId" : "${env.BUILD_NUMBER}", "status" : "started"}'
                      """
                      }
                    }
                  }
          stage('Create topic') {
                steps {
                    dir("kafka_automation/scripts/")
                    {
                    sh """
                    script_params=''
                    [[ \$replication_factor != '' ]] && script_params="\${script_params} -r \$replication_factor"
                    [[ \$partitions_number != '' ]] && script_params="\${script_params} -p \$partitions_number"
			     	        [[ \$retention != '' ]] && script_params="\${script_params} -c retention.ms=\$retention"
                    [[ \$cleanup_policy != '' ]] && script_params="\${script_params} -c cleanup.policy=\$cleanup_policy"
			     	        ./create_topic.sh -t \$cluster -e \$env -n \$topic_name \${script_params}
                    [[ \$cleanup_policy != '' ]] && script_params="\${script_params} -c cleanup.policy=\$cleanup_policy"
                    """
                    }
                  }
                }
            stage('Create user & give write permissions') {
              when {
                not {
                      equals expected: '', actual: params.username
                    }
                   }
              steps {
                  dir("kafka_automation/scripts/")
                  {
                  sh """
                  ./create_user.sh -n \$username -t \$cluster -e \$env
                  ./assign_acl.sh -u \$username -t \$cluster -e \$env -o topic -n \$topic_name -p literal -wd
                  """
                  }
                }
              }
    }
    post {
      success {
                sh """
                curl -X POST -H "Content-Type: application/json" -H "Authorization: \$(cat /var/lib/jenkins/.devportal/token)" \$callbackURL -d '{"jobName" : "DevportalCreateKafkaTopic", "buildId" : "${env.BUILD_NUMBER}", "status" : "success"}'
                """
              }
      failure {
                sh """
                curl -X POST -H "Content-Type: application/json" -H "Authorization: \$(cat /var/lib/jenkins/.devportal/token)" \$callbackURL -d '{"jobName" : "DevportalCreateKafkaTopic", "buildId" : "${env.BUILD_NUMBER}", "status" : "fail"}'
                """
              }
          }
}
