#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

environment(){
	# If env.sh exists, use values in there
	DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	[[ -f "$DIR/env.sh" ]] && echo "Importing environment from $DIR/env.sh..." && . $DIR/env.sh

	if [[ ! ${FOURKEYS_PROJECT} ]]
	# If env.sh does not exist, use current active project
	then FOURKEYS_PROJECT=$(gcloud config get-value project)
	fi
}

project_prompt(){
	# Confirm project is the correct one to use for four-keys
	continue=1
	while [[ ${continue} -gt 0 ]]
	do

	# Prompt until project-id is correct
	read -p "Would you like to use ${FOURKEYS_PROJECT} to deploy a new Cloud Run worker? (y/n) :" yesno

	if [[ ${yesno} == "y" ]]
	then continue=0
	else read -p "Please input project_id: " projectid
	export FOURKEYS_PROJECT=${projectid}
	fi

	done
}

source_prompt(){
	# The user-agent value will be used as the pub/sub topic name.  Capitalization matters.
	read -p "What's the user-agent of your new source?  Eg GitHub-Hookshot:  " user_agent
	# Will be used to name the Cloud Run service. Should be lowercase.
	read -p "What is the nickname of your source?  Eg github (lowercase):  " nickname
}

build_deploy_cloud_run(){
	# Build and deploy by copying new_source_template
	echo "Creating ${nickname}-worker"
	cp -R $DIR/../bq_workers/new_source_template $DIR/../bq_workers/${nickname}_parser
	cd $DIR/../bq_workers/${nickname}_parser
	gcloud builds submit --substitutions _SOURCE=${nickname},_REGION=europe-west2 \
						 --project ${FOURKEYS_PROJECT} .
}

set_permissions(){
	gcloud iam service-accounts create cloud-run-pubsub-invoker \
       --display-name "Cloud Run Pub/Sub Invoker" --project ${FOURKEYS_PROJECT}
  	gcloud run  --platform managed services add-iam-policy-binding ${nickname}-worker \
	   --member="serviceAccount:cloud-run-pubsub-invoker@${FOURKEYS_PROJECT}.iam.gserviceaccount.com" \
	   --role=roles/run.invoker --project ${FOURKEYS_PROJECT}
}

setup_pubsub_topic_subscription(){
	# Get push endpoint for new service
	export PUSH_ENDPOINT_URL=$(gcloud run --platform managed \
	--region europe-west2 services describe ${nickname}-worker \
	--format="value(status.url)" --project ${FOURKEYS_PROJECT})

	# Create topic
	echo "Creating event handler Pub/Sub topic..."; set -x
	gcloud pubsub topics create ${user_agent} --project ${FOURKEYS_PROJECT}

	# configure the subscription push identity
	gcloud pubsub subscriptions create ${nickname}Subscription \
	--topic=${user_agent} \
	--push-endpoint=${PUSH_ENDPOINT_URL} \
	--push-auth-service-account=cloud-run-pubsub-invoker@${FOURKEYS_PROJECT}.iam.gserviceaccount.com \
	--project ${FOURKEYS_PROJECT}
	set +x; echo
}

environment
project_prompt
source_prompt
build_deploy_cloud_run
set_permissions
setup_pubsub_topic_subscription
