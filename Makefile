-include Makefile.local

CURRENT_DIR = $(shell pwd)
BUILD_DIR = $(CURRENT_DIR)/build
VENDOR_DIR = $(CURRENT_DIR)/vendor

CC_BUILD_DIR = $(BUILD_DIR)/CodeChecker
CC_BUILD_WEB_DIR = $(CC_BUILD_DIR)/www
CC_BUILD_PLUGIN_DIR = $(CC_BUILD_DIR)/plugin
CC_BUILD_SCRIPTS_DIR = $(CC_BUILD_WEB_DIR)/scripts
CC_BUILD_DOCS_DIR = $(CC_BUILD_WEB_DIR)/docs
CC_BUILD_WEB_PLUGINS_DIR = $(CC_BUILD_SCRIPTS_DIR)/plugins
CC_BUILD_API_DIR = $(CC_BUILD_SCRIPTS_DIR)/codechecker-api
CC_BUILD_LIB_DIR = $(CC_BUILD_DIR)/lib/python2.7
CC_BUILD_GEN_DIR = $(CC_BUILD_LIB_DIR)/gencodechecker

# Root of the repository.
ROOT = $(CURRENT_DIR)

ACTIVATE_RUNTIME_VENV ?= . venv/bin/activate
ACTIVATE_DEV_VENV ?= . venv_dev/bin/activate

VENV_REQ_FILE ?= requirements_py/requirements.txt
VENV_DEV_REQ_FILE ?= requirements_py/dev/requirements.txt

OSX_VENV_REQ_FILE ?= requirements_py/osx/requirements.txt

default: package

# Test running related targets.
include tests/Makefile

gen-docs: build_dir
	doxygen ./Doxyfile.in && \
	cp -a ./gen-docs $(BUILD_DIR)/gen-docs

thrift: build_dir

	if [ -d "$(BUILD_DIR)/thrift" ]; then rm -rf $(BUILD_DIR)/thrift; fi

	mkdir $(BUILD_DIR)/thrift

	BUILD_DIR=$(BUILD_DIR) $(MAKE) -C api/

userguide: build_dir
	$(MAKE) -C www/userguide

package: clean_package build_dir gen-docs thrift userguide build_plist_to_html build_tu_collector build_vendor
	# Create directory structure.
	mkdir -p $(CC_BUILD_DIR)/bin && \
	mkdir -p $(CC_BUILD_LIB_DIR) && \
	mkdir -p $(CC_BUILD_PLUGIN_DIR)

	# Copy plist-to-html files.
	cp -r $(ROOT)/vendor/plist_to_html/plist_to_html $(CC_BUILD_LIB_DIR) && \
	cp -r $(ROOT)/vendor/plist_to_html/build $(CC_BUILD_DIR)/plist_to_html && \
	ln -s $(CC_BUILD_DIR)/plist_to_html/bin/plist-to-html $(CC_BUILD_DIR)/bin/plist-to-html

	# Copy tu_collector files.
	cp -r $(ROOT)/vendor/tu_collector/tu_collector $(CC_BUILD_LIB_DIR) && \
	cp -r $(ROOT)/vendor/tu_collector/build $(CC_BUILD_DIR)/tu_collector && \
	ln -s $(CC_BUILD_DIR)/tu_collector/bin/tu-collector $(CC_BUILD_DIR)/bin/tu-collector

	# Copy generated thrift files.
	mkdir -p $(CC_BUILD_GEN_DIR) && \
	mkdir -p $(CC_BUILD_API_DIR) && \
	cp -r $(BUILD_DIR)/thrift/v*/gen-py/* $(CC_BUILD_GEN_DIR) && \
	cp -r $(BUILD_DIR)/thrift/v*/gen-js/* $(CC_BUILD_API_DIR)

	# Copy libraries.
	cp -r $(ROOT)/libcodechecker $(CC_BUILD_LIB_DIR)

	# Copy documentation files.
	mkdir -p $(CC_BUILD_DOCS_DIR) && \
	mkdir -p $(CC_BUILD_DOCS_DIR)/checker_md_docs && \
	cp -r $(BUILD_DIR)/gen-docs/html/* $(CC_BUILD_DOCS_DIR) && \
	cp -r $(ROOT)/docs/checker_docs/* $(CC_BUILD_DOCS_DIR)/checker_md_docs/

	# Copy config files and extend 'version.json' file with git information.
	cp -r $(ROOT)/config $(CC_BUILD_DIR) && \
	./scripts/build/extend_version_file.py -r $(ROOT) -b $(BUILD_DIR) && \
	mkdir -p $(CC_BUILD_DIR)/cc_bin && \
	./scripts/build/create_commands.py -b $(BUILD_DIR) $(ROOT)/bin

	# Copy web client files.
	mkdir -p $(CC_BUILD_WEB_DIR) && \
	cp -r $(ROOT)/www/* $(CC_BUILD_WEB_DIR) && \
	mv $(CC_BUILD_WEB_DIR)/userguide/images/* $(CC_BUILD_WEB_DIR)/images && \
	rm -rf $(CC_BUILD_WEB_DIR)/userguide/images

	# Rename gen-docs to doc.
	mv $(CC_BUILD_WEB_DIR)/userguide/gen-docs $(CC_BUILD_WEB_DIR)/userguide/doc

	# Copy database migration files.
	cp -r $(ROOT)/config_db_migrate $(CC_BUILD_LIB_DIR)/config_migrate && \
	cp -r $(ROOT)/db_migrate $(CC_BUILD_LIB_DIR)/run_migrate

	# Copy license file.
	cp $(ROOT)/LICENSE.TXT $(CC_BUILD_DIR)

package_ld_logger:
	mkdir -p $(CC_BUILD_DIR)/ld_logger && \
	mkdir -p $(CC_BUILD_DIR)/bin && \
	cp -r vendor/build-logger/build/* $(CC_BUILD_DIR)/ld_logger && \
	ln -s $(CC_BUILD_DIR)/ld_logger/bin/ldlogger $(CC_BUILD_DIR)/bin/ldlogger

build_ld_logger:
	$(MAKE) -C vendor/build-logger -f Makefile.manual 2> /dev/null

build_ld_logger_x86:
	$(MAKE) -C vendor/build-logger -f Makefile.manual pack32bit 2> /dev/null

build_ld_logger_x64:
	$(MAKE) -C vendor/build-logger -f Makefile.manual pack64bit 2> /dev/null

# NOTE: extra spaces are allowed and ignored at the beginning of the
# conditional directive line, but a tab is not allowed.
ifeq ($(OS),Windows_NT)
  $(info Skipping ld logger from package)
else
  UNAME_S ?= $(shell uname -s)
  ifeq ($(UNAME_S),Linux)
    UNAME_P ?= $(shell uname -p)
    ifeq ($(UNAME_P),x86_64)
      package_ld_logger: build_ld_logger_x64
      package: package_ld_logger
    else ifneq ($(filter %86,$(UNAME_P)),)
      package_ld_logger: build_ld_logger_x86
      package: package_ld_logger
    else
      package_ld_logger: build_ld_logger
      package: package_ld_logger
    endif
  else ifeq ($(UNAME_S),Darwin)
    ifeq (, $(shell which intercept-build))
      $(error "No intercept-build (scan-build-py) in $(PATH).")
    endif
  endif
endif

build_vendor:
	$(MAKE) -C $(VENDOR_DIR) build BUILD_DIR=$(CC_BUILD_WEB_PLUGINS_DIR)

build_dir:
	mkdir -p $(BUILD_DIR)

build_plist_to_html:
	$(MAKE) -C vendor/plist_to_html

build_tu_collector:
	$(MAKE) -C vendor/tu_collector

venv:
	# Create a virtual environment which can be used to run the build package.
	virtualenv -p python2 venv && \
		$(ACTIVATE_RUNTIME_VENV) && pip install -r $(VENV_REQ_FILE)

venv_osx:
	# Create a virtual environment which can be used to run the build package.
	virtualenv -p python2 venv && \
		$(ACTIVATE_RUNTIME_VENV) && pip install -r $(OSX_VENV_REQ_FILE)

clean_venv:
	rm -rf venv

venv_dev:
	# Create a virtual environment for development.
	virtualenv -p python2 venv_dev && \
		$(ACTIVATE_DEV_VENV) && pip install -r $(VENV_DEV_REQ_FILE) && \
		pip install -r requirements_py/test/requirements.txt

clean_venv_dev:
	rm -rf venv_dev

clean: clean_package clean_vendor

clean_package: clean_userguide clean_plist_to_html clean_tu_collector
	rm -rf $(BUILD_DIR)
	rm -rf gen-docs
	find . -name "*.pyc" -delete

clean_vendor:
	$(MAKE) -C $(VENDOR_DIR) clean_vendor

clean_userguide:
	rm -rf www/userguide/gen-docs

clean_plist_to_html:
	rm -rf vendor/plist_to_html/build

clean_tu_collector:
	rm -rf vendor/tu_collector/build
