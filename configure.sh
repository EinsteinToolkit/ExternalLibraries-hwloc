#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
if [ "$(echo ${VERBOSE} | tr '[:upper:]' '[:lower:]')" = 'yes' ]; then
    set -x                      # Output commands
fi
set -e                          # Abort on errors


################################################################################
# Search
################################################################################

if [ -z "${HWLOC_DIR}" ]; then
    echo "BEGIN MESSAGE"
    echo "hwloc selected, but HWLOC_DIR not set. Checking some places..."
    echo "END MESSAGE"
    
    DIRS="/usr /usr/local /usr/local/packages /usr/local/apps /opt/local ${HOME} c:/packages"
    for dir in $DIRS; do
        # libraries might have different file extensions
        for libext in a so dylib; do
            # libraries can be in /lib or /lib64
            for libdir in lib64 lib/x86_64-linux-gnu lib lib/i386-linux-gnu; do
                FILES="include/hwloc.h $libdir/libhwloc.$libext"
                # assume this is the one and check all needed files
                HWLOC_DIR="$dir"
                for file in $FILES; do
                    # discard this directory if one file was not found
                    if [ ! -r "$dir/$file" ]; then
                        unset HWLOC_DIR
                        break
                    fi
                done
                # don't look further if all files have been found
                if [ -n "$HWLOC_DIR" ]; then
                    HWLOC_LIB_DIR="$HWLOC_DIR/$libdir"
                    break
                fi
            done
            # don't look further if all files have been found
            if [ -n "$HWLOC_DIR" ]; then
                break
            fi
        done
        # don't look further if all files have been found
        if [ -n "$HWLOC_DIR" ]; then
            break
        fi
    done
    
    if [ -z "$HWLOC_DIR" ]; then
        echo "BEGIN MESSAGE"
        echo "hwloc not found"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Found hwloc in ${HWLOC_DIR}"
        echo "END MESSAGE"
    fi
fi

################################################################################
# Build
################################################################################

if [ -z "${HWLOC_DIR}"                                                  \
     -o "$(echo "${HWLOC_DIR}" | tr '[a-z]' '[A-Z]')" = 'BUILD' ]
then
    echo "BEGIN MESSAGE"
    echo "Using bundled hwloc..."
    echo "END MESSAGE"
    
    # check for required tools. Do this here so that we don't require them when
    # using the system library
    if [ x$TAR = x ] ; then
      echo 'BEGIN ERROR'
      echo 'Could not find tar command. Please make sure that (gnu) tar is present'
      echo 'and that the TAR variable is set to its location.'
      echo 'END ERROR'
      exit 1
    fi
    if [ x$PATCH = x ] ; then
      echo 'BEGIN ERROR'
      echo 'Could not find patch command. Please make sure that (gnu) tar is present'
      echo 'and that the PATCH variable is set to its location.'
      echo 'END ERROR'
      exit 1
    fi

    # Set locations
    THORN=hwloc
    NAME=hwloc-1.7.2
    SRCDIR=$(dirname $0)
    BUILD_DIR=${SCRATCH_BUILD}/build/${THORN}
    if [ -z "${HWLOC_INSTALL_DIR}" ]; then
        INSTALL_DIR=${SCRATCH_BUILD}/external/${THORN}
    else
        echo "BEGIN MESSAGE"
        echo "Installing hwloc into ${HWLOC_INSTALL_DIR}"
        echo "END MESSAGE"
        INSTALL_DIR=${HWLOC_INSTALL_DIR}
    fi
    DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
    HWLOC_DIR=${INSTALL_DIR}
    HWLOC_LIB_DIR=${INSTALL_DIR}/lib
    
    if [ -e ${DONE_FILE} -a ${DONE_FILE} -nt ${SRCDIR}/dist/${NAME}.tar.gz \
                         -a ${DONE_FILE} -nt ${SRCDIR}/configure.sh ]
    then
        echo "BEGIN MESSAGE"
        echo "hwloc has already been built; doing nothing"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Building hwloc"
        echo "END MESSAGE"
        
        # Build in a subshell
        (
        exec >&2                    # Redirect stdout to stderr
        if [ "$(echo ${VERBOSE} | tr '[:upper:]' '[:lower:]')" = 'yes' ]; then
            set -x                  # Output commands
        fi
        set -e                      # Abort on errors
        cd ${SCRATCH_BUILD}
        
        # Set up environment
        export CPPFLAGS="${CPPFLAGS} $(echo $(for dir in ${SYS_INC_DIRS}; do echo '' -I${dir}; done))"
        export LDFLAGS
        unset CPP
        unset LIBS
        if echo '' ${ARFLAGS} | grep 64 > /dev/null 2>&1; then
            export OBJECT_MODE=64
        fi
        export HWLOC_PCIUTILS_CFLAGS="$(echo $(for dir in ${PCIUTILS_INC_DIRS} ${ZLIB_INC_DIRS}; do echo $dir; done | sed -e 's/^/-I/'))"
        export HWLOC_PCIUTILS_LIBS="$(echo $(for dir in ${PCIUTILS_LIB_DIRS} ${ZLIB_LIB_DIRS}; do echo $dir; done | sed -e 's/^/-L/') $(for dir in ${PCIUTILS_LIBS} ${ZLIB_LIBS}; do echo $dir; done | sed -e 's/^/-l/'))"
        echo "hwloc: Preparing directory structure..."
        mkdir build external done 2> /dev/null || true
        rm -rf ${BUILD_DIR} ${INSTALL_DIR}
        mkdir ${BUILD_DIR} ${INSTALL_DIR}

        echo "hwloc: Unpacking archive..."
        pushd ${BUILD_DIR}
        ${TAR?} xzf ${SRCDIR}/dist/${NAME}.tar.gz
        #${PATCH?} -p0 < ${SRCDIR}/dist/cray.1.7.patch
        #${PATCH?} -p0 < ${SRCDIR}/dist/cray.1.7.1.patch
        ${PATCH?} -p0 < ${SRCDIR}/dist/cray.1.7.2.patch
        
        echo "hwloc: Configuring..."
        cd ${NAME}
        # Provide a special option for Blue Gene/Q; this is a
        # cross-compile, so we can't easily detect this automatically
        if $(echo ${CC} | grep -q bgxlc); then
            bgq='--host=powerpc64-bgq-linux'
        else
            bgq=''
        fi
        # Disable Cairo and XML explicitly, since configure may pick
        # it up if it is installed on the system, but our final link
        # line may not link against these libraries. (We could use our
        # own libxml2 library if we want.)
        if test -n "${HAVE_PCIUTILS}"; then
            handle_pci='--enable-libpci'
        else
            handle_pci='--disable-pci'
        fi
        ## Disable pciaccess by forcing compiler errors
        #export HWLOC_PCIACCESS_CFLAGS=DISABLE-PCIACCESS
        #./configure --prefix=${HWLOC_DIR} ${bgq} ${handle_pci} --disable-cairo --disable-libxml2 --enable-shared=no --enable-static=yes
        ./configure --prefix=${HWLOC_DIR} ${bgq} ${handle_pci} --disable-cairo --disable-libxml2 --enable-shared=yes --enable-static=no
        
        echo "hwloc: Building..."
        ${MAKE}
        
        echo "hwloc: Installing..."
        ${MAKE} install
        popd
        
        echo "hwloc: Cleaning up..."
        rm -rf ${BUILD_DIR}
        
        date > ${DONE_FILE}
        echo "hwloc: Done."
        )
        
        if (( $? )); then
            echo 'BEGIN ERROR'
            echo 'Error while building hwloc. Aborting.'
            echo 'END ERROR'
            exit 1
        fi
    fi
    
fi


# Check that pkg-config works
export PKG_CONFIG_PATH=${HWLOC_LIB_DIR}/pkgconfig:${PCIUTILS_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}
if ! pkg-config hwloc; then
    echo "BEGIN MESSAGE"
    echo "pkg-config not found; attempting to use reasonable defaults"
    echo "END MESSAGE"

    HWLOC_INC_DIRS="${HWLOC_DIR}/include"
    HWLOC_LIB_DIRS="${HWLOC_LIB_DIR}"
    HWLOC_LIBS='hwloc'
else
    HWLOC_INC_DIRS="$(echo '' $(pkg-config hwloc --static --cflags 2>/dev/null || pkg-config hwloc --cflags) '' | sed -e 's+ -I/include + +g;s+ -I/usr/include + +g;s+ -I/usr/local/include + +g' | sed -e 's/ -I/ /g')"
    HWLOC_LIB_DIRS="$(echo '' $(pkg-config hwloc --static --libs 2>/dev/null || pkg-config hwloc --libs) '' | sed -e 's/ -l[^ ]*/ /g' | sed -e 's+ -L/lib + +g;s+ -L/lib64 + +g;s+ -L/usr/lib + +g;s+ -L/usr/lib64 + +g;s+ -L/usr/local/lib + +g;s+ -L/usr/local/lib64 + +g' | sed -e 's/ -L/ /g')"
    HWLOC_LIBS="$(echo '' $(pkg-config hwloc --static --libs 2>/dev/null || pkg-config hwloc --libs) '' | sed -e 's/ -[^l][^ ]*/ /g' | sed -e 's/ -l/ /g')"
fi

# Add libnuma manually, if necessary
if grep -q '[-]lnuma' ${HWLOC_LIB_DIR}/lib/libhwloc.la; then
    if ! echo '' ${HWLOC_LIBS} '' | grep -q ' numa '; then
        HWLOC_LIBS="${HWLOC_LIBS} numa"
    fi
fi



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
