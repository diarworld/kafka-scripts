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
                                string(name: 'topic_name', description: 'Enter topic name for read access'),
                                string(name: 'username', description: 'Enter username which would be created with read permissions'),
                                string(name: 'group_name', description: 'Enter consumer group name')
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
                      curl -X POST -H "Content-Type: application/json" -H "Authorization: \$(cat /var/lib/jenkins/.devportal/token)" \$callbackURL -d '{"jobName" : "DevportalCreateKafkaReader", "buildId" : "${env.BUILD_NUMBER}", "status" : "started"}'
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
                  ./assign_acl.sh -u \$username -t \$cluster -e \$env -o topic -n \$topic_name -p literal -rd
                  ./assign_acl.sh -u \$username -t \$cluster -e \$env -o group -n \$group_name -p literal -rd
                  """
                  }
                }
              }
    }
    post {
      success {
                sh """
                curl -X POST -H "Content-Type: application/json" -H "Authorization: \$(cat /var/lib/jenkins/.devportal/token)" \$callbackURL -d '{"jobName" : "DevportalCreateKafkaReader", "buildId" : "${env.BUILD_NUMBER}", "status" : "success"}'
                """
              }
      failure {
                sh """
                curl -X POST -H "Content-Type: application/json" -H "Authorization: \$(cat /var/lib/jenkins/.devportal/token)" \$callbackURL -d '{"jobName" : "DevportalCreateKafkaReader", "buildId" : "${env.BUILD_NUMBER}", "status" : "fail"}'
                """
              }
          }
}
