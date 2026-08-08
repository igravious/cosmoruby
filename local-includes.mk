# Local project-specific BUILD.mk includes
# This file is not committed to the repository
# Add it to .git/info/exclude

# Use toolchain objcopy (resolves to correct arch via $(OBJCOPY) variable)
# Write to temp file then mv to handle "Text file busy" on running executables
ifneq ($(ARCH), aarch64)
MAKE_OBJCOPY = $(COMPILE) -AOBJCOPY -T$@ $(OBJCOPY) -S -O binary $< $@.tmp && mv -f $@.tmp $@ && $(MAKE_ZIPCOPY)
else
MAKE_OBJCOPY = $(COMPILE) -AOBJCOPY -T$@ $(OBJCOPY) -S $< $@.tmp && mv -f $@.tmp $@ && $(MAKE_ZIPCOPY)
endif

# Mexican Toaster / Ruby development
# cosmo_plugin must load before ruby — ruby.compile.mk uses := (immediate
# expansion) for DEPS/pkg and THIRD_PARTY_COSMO_PLUGIN is in DIRECTDEPS.
# tool/build/lib must load before ruby — rubyobj needs TOOL_BUILD_LIB (elfwriter).
# This file has an include guard, so it's safe to load here and again from Makefile.
include tool/build/lib/BUILD.mk
include third_party/cosmo_plugin/BUILD.mk
include test/third_party/cosmo_plugin/BUILD.mk
include third_party/libyaml/BUILD.mk
include third_party/tomlc99/BUILD.mk
include third_party/ruby/BUILD.mk
include third_party/mexican_toaster/BUILD.mk
include third_party/build/mtdeps/BUILD.mk
include examples/rubyapps/BUILD.mk

# Require bootstrap mtdeps for dependency generation.
# Exception: when MKDEPS is passed on the command line (as done by
# cosmo_configure.sh --bootstrap with the mkdeps stub), skip the check so the
# bootstrap build that produces build/bootstrap/mtdeps can actually run.
ifeq ($(wildcard build/bootstrap/mtdeps),)
ifneq ($(origin MKDEPS),command line)
$(error Missing build/bootstrap/mtdeps. Run third_party/ruby/cosmo_configure.sh --bootstrap)
endif
else
MKDEPS := build/bootstrap/mtdeps -P ruby_shims/
endif
# Note: bootstrap binaries are built from third_party/build/mtdeps/ sources
# and copied to build/bootstrap/ by cosmo_configure.sh --bootstrap

# Core Makefile computes SRCS/HDRS/INCS/BINS before loading this file, so
# append the local packages to those aggregates here.
LOCAL_PKGS :=							\
	THIRD_PARTY_COSMO_PLUGIN				\
	TEST_THIRD_PARTY_COSMO_PLUGIN				\
	THIRD_PARTY_LIBYAML					\
	THIRD_PARTY_TOMLC99					\
	THIRD_PARTY_RUBY					\
	THIRD_PARTY_MEXICAN_TOASTER				\
	THIRD_PARTY_BUILD_MTDEPS				\
	EXAMPLES_RUBYAPPS

OBJS   += $(foreach x,$(LOCAL_PKGS),$($(x)_OBJS))
SRCS   += $(foreach x,$(LOCAL_PKGS),$($(x)_SRCS))
HDRS   += $(foreach x,$(LOCAL_PKGS),$($(x)_HDRS))
INCS   += $(foreach x,$(LOCAL_PKGS),$($(x)_INCS))
BINS   += $(foreach x,$(LOCAL_PKGS),$($(x)_BINS))
TESTS  += $(foreach x,$(LOCAL_PKGS),$($(x)_TESTS))
CHECKS += $(foreach x,$(LOCAL_PKGS),$($(x)_CHECKS))
