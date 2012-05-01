#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
set -x                          # Output commands
set -e                          # Abort on errors



################################################################################
# Build
################################################################################

echo "BEGIN MESSAGE"
echo "Building hwloc..."
echo "END MESSAGE"

# Set locations
THORN=hwloc
NAME=hwloc-1.4
SRCDIR=$(dirname $0)
BUILD_DIR=${SCRATCH_BUILD}/build/${THORN}
INSTALL_DIR=${SCRATCH_BUILD}/external/${THORN}
DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
HWLOC_DIR=${INSTALL_DIR}

(
    exec >&2                    # Redirect stdout to stderr
    set -x                      # Output commands
    set -e                      # Abort on errors
    cd ${SCRATCH_BUILD}
    if [ -e ${DONE_FILE} -a ${DONE_FILE} -nt ${SRCDIR}/dist/${NAME}.tar.gz \
                         -a ${DONE_FILE} -nt ${SRCDIR}/configure.sh ]
    then
        echo "hwloc: The enclosed hwloc library has already been built; doing nothing"
    else
        echo "hwloc: Building enclosed hwloc library"
        
        export LDFLAGS
        unset LIBS
        if echo '' ${ARFLAGS} | grep 64 > /dev/null 2>&1; then
            export OBJECT_MODE=64
        fi
        
        echo "hwloc: Preparing directory structure..."
        mkdir build external done 2> /dev/null || true
        rm -rf ${BUILD_DIR} ${INSTALL_DIR}
        mkdir ${BUILD_DIR} ${INSTALL_DIR}
        
        echo "hwloc: Unpacking archive..."
        pushd ${BUILD_DIR}
        ${TAR} xzf ${SRCDIR}/dist/${NAME}.tar.gz
        
        echo "hwloc: Configuring..."
        cd ${NAME}
        # Disable Cairo and XML explicitly, since configure may pick
        # it up if it is installed on the system, but our final link
        # line may not link against these libraries. (We could use our
        # own libxml2 library if we want.)
        ./configure --prefix=${HWLOC_DIR} --disable-cairo --disable-libxml2
        
        echo "hwloc: Building..."
        ${MAKE}
        
        echo "hwloc: Installing..."
        ${MAKE} install
        popd
        
        echo "hwloc: Cleaning up..."
        rm -rf ${BUILD_DIR}
        
        date > ${DONE_FILE}
        echo "hwloc: Done."
    fi
)

if (( $? )); then
    echo 'BEGIN ERROR'
    echo 'Error while building hwloc. Aborting.'
    echo 'END ERROR'
    exit 1
fi



#HWLOC_INC_DIRS='$(HWLOC_DIR)/include '"${BUILD_DIR}/${NAME}/include"
HWLOC_INC_DIRS='$(HWLOC_DIR)/include'
HWLOC_LIB_DIRS='$(HWLOC_DIR)/lib'
HWLOC_LIBS='hwloc'



################################################################################
# Configure Cactus
################################################################################

# Pass options to Cactus
echo "BEGIN MAKE_DEFINITION"
echo "HAVE_HWLOC     = 1"
echo "HWLOC_DIR      = ${HWLOC_DIR}"
echo "HWLOC_INC_DIRS = ${HWLOC_INC_DIRS}"
echo "HWLOC_LIB_DIRS = ${HWLOC_LIB_DIRS}"
echo "HWLOC_LIBS     = ${HWLOC_LIBS}"
echo "END MAKE_DEFINITION"

echo 'INCLUDE_DIRECTORY $(HWLOC_INC_DIRS)'
echo 'LIBRARY_DIRECTORY $(HWLOC_LIB_DIRS)'
echo 'LIBRARY           $(HWLOC_LIBS)'
