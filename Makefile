.PHONY: build clean publish

ACL ?= 'private'
BUCKET ?=
PREFIX ?= quickstart-redhat-openshift
PROFILE ?= default
REGION ?= $(shell aws configure get region --profile $(PROFILE))
REPO_NAME ?= aws-ocp
VENV_NAME?=venv
VENV_ACTIVATE=. $(VENV_NAME)/bin/activate
PYTHON=${VENV_NAME}/bin/python3
PYTHON3 := $(shell python3 -V 2>&1)

region:
	@echo $(REGION)

help:
	@echo   "make test  : executes taskcat"

.ONESHELL:
test: lint build
	taskcat test run -n

lint:
	time taskcat lint

build_lambda:
	mkdir -p output/build/functions
	./build/lambda_package.sh

build: build_lambda
	cp -r functions/packages output/build/functions/
	cp -r scripts templates submodules output/build
	cp -r LICENSE.txt NOTICE.txt output/build
	if [ "$(VERSION)" != "" ] ; then \
      sed -i "s|Default: $(PREFIX)/|Default: $(PREFIX)-versions/$(VERSION)/|g" output/build/templates/*.yaml ; \
    fi
	cd output/build/ && zip -X -r ../release.zip .

publish:
	if [ "$(BUCKET)" == "" ] ; then \
      echo BUCKET must be specified to publish; exit 1; \
    fi
	if [ "$(REGION)" == "" ] ; then \
      echo REGION must be specified to publish; exit 1; \
    fi
	if [ $(shell echo $(VERSION) | grep -c dev) -eq 0 ] ; then \
		if [ "$(GH_RELEASE)" == "true" ] ; then \
			hub release create -m v$(VERSION) -a "output/release.zip#$(PREFIX)-s3-package-v$(VERSION).zip" v$(VERSION) ;\
		fi ; \
	fi
	if [ "$(VERSION)" == "" ] ; then \
	  cd output/build && ../../build/s3_sync.py $(BUCKET) $(REGION) $(PROFILE) $(PREFIX)/ ./ $(ACL) ; \
	else \
	  cd output/build && ../../build/s3_sync.py $(BUCKET) $(REGION) $(PROFILE) $(PREFIX)-versions/ ./ $(ACL) ; \
	fi

verify:
ifdef PYTHON3
	@echo "python3 Found, continuing."
else
	@echo "please install python3"
	exit 1
endif

venv:
	@make verify
	python3 -m venv $(VENV_NAME);

# Make sure to export all of the parameters found in LambdaStack resource in
# templates/aws-ocp-main.template.yaml as env variables
run_lambda_create_cf: venv
	${VENV_ACTIVATE} && \
	cd functions/source/OpenShift4Installation/ && \
	python-lambda-local -f lambda_handler lambda_function.py ../../tests/deploy_cf_env_variables.json -t 300

clean:
	rm -rf output/
	rm -rf taskcat_outputs
	rm -rf .taskcat
	rm -rf functions/packages
