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

import hmac
from hashlib import sha1, sha256
import os

from google.cloud import secretmanager

PROJECT_NAME = os.environ.get("PROJECT_NAME")


class EventSource(object):
    """
    A source of event data being delivered to the webhook
    """

    def __init__(self, name, signature_header, verification_func):
        self.name = name
        self.signature = signature_header
        self.verification = verification_func


def github_verification(signature, body):
    """
    Verifies that the signature received from the github event is accurate
    """
    if not signature:
        raise Exception("Github signature is empty")

    expected_signature = "sha1="
    try:
        # Get secret from Cloud Secret Manager
        secret = get_secret(PROJECT_NAME, "event-handler", "latest")
        # Compute the hashed signature
        hashed = hmac.new(secret, body, sha1)
        expected_signature += hashed.hexdigest()

    except Exception as e:
        print(e)

    return hmac.compare_digest(signature, expected_signature)


def simple_token_verification(token, body):
    """
    Verifies that the token received from the event is accurate
    """
    if not token:
        raise Exception("Token is empty")
    secret = get_secret(PROJECT_NAME, "event-handler", "1")

    return secret.decode() == token


def sha256_signature_verification(signature, body):
    """
    Verifies the signature using sha256
    """

    if not signature:
        raise Exception("Signature is empty")

    try:
        # Get secret from Cloud Secret Manager
        secret = get_secret(PROJECT_NAME, "event-handler", "latest")
        # Compute the hashed signature
        hashed = hmac.new(secret, body, sha256)
        expected_signature = hashed.hexdigest()

    except Exception as e:
        print(e)

    return hmac.compare_digest(signature, expected_signature)


def get_secret(project_name, secret_name, version_num):
    """
    Returns secret payload from Cloud Secret Manager
    """
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = client.secret_version_path(
            project_name, secret_name, version_num
        )
        secret = client.access_secret_version(name)
        return secret.payload.data
    except Exception as e:
        print(e)


def get_source(headers):
    """
    Gets the source from the User-Agent header
    """
    if "X-Gitlab-Event" in headers:
        return "Gitlab"

    if "Ce-Type" in headers and "tekton" in headers["Ce-Type"]:
        return "Tekton"

    if "User-Agent" in headers:
        if "/" in headers["User-Agent"]:
            return headers["User-Agent"].split("/")[0]
        return headers["User-Agent"]

    return None


AUTHORIZED_SOURCES = {
    "GitHub-Hookshot": EventSource(
        "github", "X-Hub-Signature", github_verification
        ),
    "Gitlab": EventSource(
        "gitlab", "X-Gitlab-Token", simple_token_verification
        ),
    "Tekton": EventSource(
        "tekton", "tekton-secret", simple_token_verification
        ),
    "golang-incident-bot": EventSource(
        "incident-bot", "X-Incident-Signature", sha256_signature_verification
        ),
    "drone-deployment": EventSource(
        "drone-deployment", "X-Deployment-Signature", sha256_signature_verification
        )
}
