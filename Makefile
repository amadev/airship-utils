# Copyright 2018 The Openstack-Helm Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

IMAGE_PREFIX               ?= airshipit
IMAGE_TAG                  ?= untagged
IMAGE_NAME                 := mini-mirror
COMMIT                     ?= commit-id

DOCKER_REGISTRY            ?= quay.io
PUSH_IMAGE                 ?= false

HELM                       := helm

PROXY                      ?= http://proxy.foo.com:8000
NO_PROXY                   ?= localhost,127.0.0.1,.svc.cluster.local
USE_PROXY                  ?= false

UBUNTU_BASE_IMAGE          ?= ubuntu:16.04

IMAGE:=${DOCKER_REGISTRY}/${IMAGE_PREFIX}/$(IMAGE_NAME):${IMAGE_TAG}

CHART                       := charts/mini-mirror

.PHONY: validate
validate: lint test

.PHONY: test
test: test-containers test-charts

.PHONY: test-containers
test-containers: clean build
	docker run -d \
		--publish 8080:80 \
		--volume $(shell pwd)/assets/nginx:/opt/nginx \
		--name aptly \
		${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}
	docker run --network host \
		--name target \
		--volume $(shell pwd)/tools:/opt \
		$(UBUNTU_BASE_IMAGE) /opt/install_packages.sh

.PHONY: test-charts
test-charts: charts helm-lint
	$(HELM) delete --purge mini-mirror || true
	$(HELM) install --debug -n mini-mirror mini-mirror-*.tgz

.PHONY: clean
clean:
	docker rm -f aptly || true
	docker rm -f target || true

.PHONY: lint
lint:
	shellcheck assets/*.sh
	docker run --rm -i hadolint/hadolint < Dockerfile

.PHONY: build
build:
ifeq ($(USE_PROXY), true)
	docker build --network host -t $(IMAGE) \
		--label "org.opencontainers.image.revision=$(COMMIT)" \
		--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
		--label "org.opencontainers.image.title=$(IMAGE_NAME)" \
		-f Dockerfile \
		--build-arg http_proxy=$(PROXY) \
		--build-arg https_proxy=$(PROXY) \
		--build-arg HTTP_PROXY=$(PROXY) \
		--build-arg HTTPS_PROXY=$(PROXY) \
		--build-arg no_proxy=$(NO_PROXY) \
		--build-arg NO_PROXY=$(NO_PROXY) .
else
	docker build --network host -t $(IMAGE) \
		--label "org.opencontainers.image.revision=$(COMMIT)" \
		--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
		--label "org.opencontainers.image.title=$(IMAGE_NAME)" \
		-f Dockerfile .
endif
ifeq ($(PUSH_IMAGE), true)
	docker push $(IMAGE)
endif

.PHONY: lint-install
lint-install:
	apt-get install -y shellcheck

.PHONY: helm-lint
helm-lint:
	$(HELM) lint $(CHART)

# Create tgz of the chart
.PHONY: charts
charts:
	rm -f mini-mirror-*.tgz
	$(HELM) dep up $(CHART)
	$(HELM) package $(CHART)

.PHONY: test-install
test-install:
	rm -rf build
	tools/helm_tk.sh $(HELM)
