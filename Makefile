PARENT_PACKAGE := brymck
PROTOTOOL_IMAGE := brymck/prototool-java-typescript:1.8.1
DOCKER ?= docker
PROTOTOOL := $(DOCKER) run --name prototool --volumes-from configs -u $(shell id -u):$(shell id -g) $(PROTOTOOL_IMAGE) prototool

PACKAGES := $(patsubst $(PARENT_PACKAGE)/%,%,$(wildcard $(PARENT_PACKAGE)/*))
PROTOS := $(shell find . -name '*.proto')
LANGUAGES := go java node python

# Determine the base version from the most recent tag. If the current commit is a tag, then consider this a release. If
# it's a snapshot version (i.e. not a release), then count the number of commits since the last tag so we can derive
# unique release names for languages that expect that convention (e.g. Node.js).
LAST_TAG = $(shell git describe --exact-match HEAD 2>/dev/null)
ifeq ("$(LAST_TAG)","")
LAST_TAG = $(shell git describe --abbrev=0)
IS_RELEASE = false
else
IS_RELEASE = true
endif
COMMITS_SINCE_LAST_TAG = $(shell git rev-list $(LAST_TAG)..HEAD --count)
BASE_VERSION = $(subst v,,$(LAST_TAG))

all: dependencies generate package build

prototool: dependencies/descriptor_set.json dependencies/descriptor_set.pb generate-code

lint:
	$(PROTOTOOL) lint .

$(PARENT_PACKAGE):
	mkdir -p $@

$(PARENT_PACKAGE)/%.proto: | $(PARENT_PACKAGE)
	$(PROTOTOOL) create $@

#-----------------------------------------------------------------------------------------------------------------------
# Requirements
#-----------------------------------------------------------------------------------------------------------------------

venv/bin/activate:
	python -m venv venv

requirements.package.txt: venv/bin/activate
	source venv/bin/activate && pip freeze | xargs pip uninstall -y
	source venv/bin/activate && pip install Jinja2 && pip freeze > $@

requirements.build.txt: venv/bin/activate
	source venv/bin/activate && pip freeze | xargs pip uninstall -y
	source venv/bin/activate && pip install wheel && pip freeze --all | grep -v 'pip\|distribute\|setuptools' > $@

requirements.deploy.txt: venv/bin/activate
	source venv/bin/activate && pip freeze | xargs pip uninstall -y
	source venv/bin/activate && pip install twine && pip freeze > $@

requirements.txt: requirements.package.txt requirements.build.txt requirements.deploy.txt
	cat requirements.*.txt | sort -u > requirements.txt

#-----------------------------------------------------------------------------------------------------------------------
# Build dependency tree
#-----------------------------------------------------------------------------------------------------------------------

# Dependencies
dependencies: dependencies/.dirstamp

dependencies/.dirstamp: dependencies/descriptor_set.json dependencies/descriptor_set.pb dependencies/lists/.dirstamp
	touch $@

define set_up_volumes_for
	$(DOCKER) rm configs || true
	$(DOCKER) create -v /work --name configs alpine:3.4 /bin/true
	$(DOCKER) cp $(CURDIR)/. configs:/work
	$(DOCKER) rm $(1) || true
endef

dependencies/descriptor_set.json: $(PROTOS)
	mkdir -p $(dir $@)
	$(call set_up_volumes_for,prototool)
	$(PROTOTOOL) descriptor-set . --include-imports --json --output-path $@
	$(DOCKER) cp prototool:/work/$@ $@

dependencies/descriptor_set.pb: $(PROTOS)
	mkdir -p $(dir $@)
	$(call set_up_volumes_for,prototool)
	$(PROTOTOOL) descriptor-set . --include-imports --include-source-info --output-path $@
	$(DOCKER) cp prototool:/work/$@ $@

dependencies/lists/.dirstamp: $(PROTOS)
	python bin/dependencies.py
	touch $@

#-----------------------------------------------------------------------------------------------------------------------
# Generate first pass of compiled code with protoc
#-----------------------------------------------------------------------------------------------------------------------

generate: generate-code

# Prototool
gen/.dirstamp: $(PROTOS)
	mkdir -p $(dir $@)
	$(call set_up_volumes_for,prototool)
	$(PROTOTOOL) all .
	$(DOCKER) cp prototool:/work/$(dir $@)/. $(dir $@)
	touch $@
generate-code: gen/.dirstamp

#-----------------------------------------------------------------------------------------------------------------------
# Organize generated code into directories for each package and language
#-----------------------------------------------------------------------------------------------------------------------

# In this step, we organize the code generated by prototool into subdirectories in packages/<language>. We should not
# have any dependencies on Go, Java, etc. here. We should also be indifferent to the dependency tree.

package: package-go package-java package-node package-python

define copy_generated_code
	mkdir -p $(3)
	cp -r gen/$(1)/$(4)/$(PARENT_PACKAGE)/$(2)/. $(3)
endef

# Go
packages/go/%/go.mod: dependencies/.dirstamp gen/.dirstamp
	$(call copy_generated_code,go,$*,$(dir $@),)
# Replace the weird import in Go libraries with the path we want
	find $(dir $@) -name '*.go' -exec sed -i.bak 's#github.com/$(PARENT_PACKAGE)/genproto/gen/go/$(PARENT_PACKAGE)#github.com/$(PARENT_PACKAGE)/genproto#g' {} \;
	find $(dir $@) -name '*.bak' -delete
	python bin/templates.py $* go $(BASE_VERSION) $(COMMITS_SINCE_LAST_TAG) $(IS_RELEASE)
package-go: $(foreach package,$(PACKAGES),packages/go/$(package)/go.mod)

# Java
packages/java/%/pom.xml: dependencies/.dirstamp gen/.dirstamp
	$(call copy_generated_code,java,$*,$(dir $@)/src/main/java/com/github/$(PARENT_PACKAGE)/$*,com/github/)
	python bin/templates.py $* java $(BASE_VERSION) $(COMMITS_SINCE_LAST_TAG) $(IS_RELEASE)
package-java: $(foreach package,$(PACKAGES),packages/java/$(package)/pom.xml)

# Node
packages/node/%/package.json: dependencies/.dirstamp gen/.dirstamp
	$(call copy_generated_code,node,$*,$(dir $@),)
	python bin/templates.py $* node $(BASE_VERSION) $(COMMITS_SINCE_LAST_TAG) $(IS_RELEASE)
package-node: $(foreach package,$(PACKAGES),packages/node/$(package)/package.json)

# Python
packages/python/%/setup.py: dependencies/.dirstamp gen/.dirstamp
	$(call copy_generated_code,python,$*,$(dir $@)/$(PARENT_PACKAGE)/$*,)
# Create __init__.py so Python recognizes directory contents
	find $(dir $@)/$(PARENT_PACKAGE) -type d -exec touch {}/__init__.py \;
	python bin/templates.py $* python $(BASE_VERSION) $(COMMITS_SINCE_LAST_TAG) $(IS_RELEASE)
package-python: $(foreach package,$(PACKAGES),packages/python/$(package)/setup.py)

#-----------------------------------------------------------------------------------------------------------------------
# Validate builds for each package and populate lockfiles and checksums
#-----------------------------------------------------------------------------------------------------------------------

# Here, we build each codebase. The build process may generate files that we need, such as those containing package
# checksums. Note that we use the dependency information here to ensure that any libraries a given package depends on
# are built and, if needed, installed locally.

build: build-go build-java build-node build-python

build-go: # noop

packages/java/%/target/.dirstamp: packages/java/%/pom.xml
# Install local dependencies
	cat dependencies/lists/$*.txt | xargs -I {} $(MAKE) packages/java/{}/target/.dirstamp
# Build and publish to local Maven repository for dependent libraries
	(cd $(dir $<) && mvn install)
	touch $@
build-java: package-java $(foreach package,$(PACKAGES),packages/java/$(package)/target/.dirstamp)

packages/node/%/package-lock.json: packages/node/%/package.json
# Build local dependencies
	cat dependencies/lists/$*.txt | xargs -I {} $(MAKE) packages/node/{}/package-lock.json
# Link local dependencies
	cat dependencies/lists/$*.txt | xargs -I {} sh -c "cd $(dir $<) && npm link ../{} --quiet"
	(cd $(dir $<) && npm install --quiet --no-progress)
build-node: package-node $(foreach package,$(PACKAGES),packages/node/$(package)/package-lock.json)

packages/python/%/.dirstamp: packages/python/%/setup.py
	cat dependencies/lists/$*.txt | xargs -I {} $(MAKE) packages/python/{}/.dirstamp
# Create source and built distributions
	(cd $(dir $<) && pip install -q . && python setup.py -q sdist bdist_wheel)
	touch $@
build-python: package-python $(foreach package,$(PACKAGES),packages/python/$(package)/.dirstamp)

#-----------------------------------------------------------------------------------------------------------------------
# Deploy libraries
#-----------------------------------------------------------------------------------------------------------------------

deploy: deploy-go deploy-java deploy-node deploy-python

packages/go/%/.deployed.dirstamp: packages/go/%/go.sum
	(cd $(dir $@) && (cat VERSION | xargs -I {} jfrog rt go-publish go 'v{}'))
	touch $@
deploy-go: $(foreach package,$(PACKAGES),packages/go/$(package)/.deployed.dirstamp)

packages/java/%/.deployed.dirstamp: packages/java/%/target/.dirstamp
	(cd $(dir $@) && mvn --activate-profiles release deploy)
	touch $@
deploy-java: $(foreach package,$(PACKAGES),packages/java/$(package)/.deployed.dirstamp)

packages/node/%/.deployed.dirstamp: packages/node/%/package-lock.json
	(cd $(dir $@) && npm publish)
	touch $@
deploy-node: $(foreach package,$(PACKAGES),packages/node/$(package)/.deployed.dirstamp)

packages/python/%/.deployed.dirstamp: packages/python/%/.dirstamp
	(cd $(dir $@) && twine upload -r local dist/*)
	touch $@
deploy-python: $(foreach package,$(PACKAGES),packages/python/$(package)/.deployed.dirstamp)

#-----------------------------------------------------------------------------------------------------------------------
# Clean up
#-----------------------------------------------------------------------------------------------------------------------

clean:
	rm -rf dependencies gen packages venv

.PHONY: \
	all \
	prototool \
	version \
	lint \
	dependencies \
	generate \
	generate-code \
	package \
	$(foreach language,$(LANGUAGES),package-$(language)) \
	build \
	$(foreach language,$(LANGUAGES),build-$(language)) \
	deploy \
	$(foreach language,$(LANGUAGES),deploy-$(language)) \
	clean
