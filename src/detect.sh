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
    
    # Check whether pkg-config works
    export PKG_CONFIG_PATH=pkgconfig:${PCIUTILS_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}
    if pkg-config hwloc; then
        # Check that version is sufficient
        # we negate the return code since in perl true == 1 but for the shell true == 0
        if pkg-config --modversion hwloc | 
          perl -ne 'm/^0*(\d+)[.]0*(\d+)/; exit !($1>1 or $1==1 and $2>=6)' ; then 
            inc_dirs="$(pkg-config hwloc --static --cflags 2>/dev/null || pkg-config hwloc --cflags)"
            lib_dirs="$(pkg-config hwloc --static --libs 2>/dev/null || pkg-config hwloc --libs)"
            libs="$(pkg-config hwloc --static --libs 2>/dev/null || pkg-config hwloc --libs)"
            # Translate option flags into Cactus options:
            # - for INC_DIRS, remove -I prefix from flags
            # - for LIB_DIRS, remove all -l flags, and remove -L prefix from flags
            # - for LIBS, keep only -l flags, and remove -l prefix from flags
            HWLOC_INC_DIRS="$(echo '' $(for flag in $inc_dirs; do echo '' $flag; done | sed -e 's/^ -I//'))"
            HWLOC_LIB_DIRS="$(echo '' $(for flag in $lib_dirs; do echo '' $flag; done | grep -v '^ -l' | sed -e 's/^ -L//'))"
            HWLOC_LIBS="$(echo '' $(for flag in $libs; do echo '' $flag; done | grep '^ -l' | sed -e 's/^ -l//'))"
            HWLOC_DIR="$(echo ${HWLOC_INC_DIRS} NO_BUILD | sed 's!/[^/]* .*!!')"
            HWLOC_VERSION_PKGCONFIG=$(pkg-config --modversion hwloc)
        else
            echo "BEGIN MESSAGE"
            echo "hwloc in ${HWLOC_DIR} too old (require at least version 1.6)"
            echo "END MESSAGE"    
        fi
    else
      echo "BEGIN MESSAGE"
      echo "pkg-config not found; attempting to use reasonable defaults"
      echo "END MESSAGE"
        
      DIRS="/usr /usr/local /usr/local/packages /usr/local/apps /opt/local ${HOME} c:/packages"
      for dir in $DIRS; do
          # libraries might have different file extensions
          for libext in a dll dll.a so dylib lib so; do
              # libraries can be in /lib or /lib64 (or libx32?)
              for libdir in lib64 lib/x86_64-linux-gnu lib lib/i386-linux-gnu; do
                  FILES="include/hwloc.h $libdir/libhwloc.$libext"
                  # assume this is the one and check all needed files
                  HWLOC_DIR="$dir"
                  HWLOC_LIB_DIRS="$dir/$libdir"
                  HWLOC_INC_DIRS="$dir/include"
                  for file in $FILES; do
                      # discard this directory if one file was not found
                      if [ ! -r "$dir/$file" ]; then
                          unset HWLOC_DIR
                          unset HWLOC_LIB_DIRS
                          unset HWLOC_INC_DIRS
                          break
                      fi
                  done
                  # Check that version is sufficient
                  if [ -r ${HWLOC_INC_DIRS}/hwloc.h ] &&
                    perl -ne 'exit !($1 lt "0x00010600") if m/^#define HWLOC_API_VERSION (.*)/' \
                      ${HWLOC_INC_DIRS}/hwloc.h ; then
                      echo "BEGIN MESSAGE"
                      echo "hwloc in ${HWLOC_DIR} too old (require at least version 1.6)"
                      echo "END MESSAGE"
                      unset HWLOC_DIR
                      unset HWLOC_LIB_DIRS
                      unset HWLOC_INC_DIRS
                  fi
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
          # don't look further if all files have been found
          if [ -n "$HWLOC_DIR" ]; then
              break
          fi
      done
    fi
    
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

THORN=hwloc

################################################################################
# Build
################################################################################

if [ -z "${HWLOC_DIR}"                                                  \
     -o "$(echo "${HWLOC_DIR}" | tr '[a-z]' '[A-Z]')" = 'BUILD' ]
then
    echo "BEGIN MESSAGE"
    echo "Using bundled hwloc..."
    echo "END MESSAGE"
    
    # Check for required tools. Do this here so that we don't require
    # them when using the system library.
    if [ "x$TAR" = x ] ; then
        echo 'BEGIN ERROR'
        echo 'Could not find tar command.'
        echo 'Please make sure that the (GNU) tar command is present,'
        echo 'and that the TAR variable is set to its location.'
        echo 'END ERROR'
        exit 1
    fi
    if [ "x$PATCH" = x ] ; then
        echo 'BEGIN ERROR'
        echo 'Could not find patch command.'
        echo 'Please make sure that the patch command is present,'
        echo 'and that the PATCH variable is set to its location.'
        echo 'END ERROR'
        exit 1
    fi

    # Set locations
    NAME=hwloc-2.0.4
    SRCDIR="$(dirname $0)"
    BUILD_DIR=${SCRATCH_BUILD}/build/${THORN}
    if [ -z "${HWLOC_INSTALL_DIR}" ]; then
        INSTALL_DIR=${SCRATCH_BUILD}/external/${THORN}
    else
        echo "BEGIN MESSAGE"
        echo "Installing hwloc into ${HWLOC_INSTALL_DIR}"
        echo "END MESSAGE"
        INSTALL_DIR=${HWLOC_INSTALL_DIR}
    fi
    HWLOC_BUILD=1
    HWLOC_DIR=${INSTALL_DIR}
    HWLOC_INC_DIRS="${HWLOC_DIR}/include"
    HWLOC_LIB_DIRS="${HWLOC_DIR}/lib"
    HWLOC_LIBS='hwloc'
    HWLOC_VERSION_BUILD=${NAME#*-}
else
    HWLOC_BUILD=
    DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
    if [ ! -e ${DONE_FILE} ]; then
        mkdir ${SCRATCH_BUILD}/done 2> /dev/null || true
        date > ${DONE_FILE}
    fi
    
    if [ "${HWLOC_DIR}" != 'NO_BUILD' ]; then
        : ${HWLOC_INC_DIRS="${HWLOC_DIR}/include"}
        : ${HWLOC_LIB_DIRS="${HWLOC_DIR}/lib"}
    fi
    : ${HWLOC_LIBS='hwloc'}

    if [ "${HWLOC_DIR}" = 'NO_BUILD' ]; then
      HWLOC_INFO_EXE=hwloc-info
    else
      HWLOC_INFO_EXE="${HWLOC_DIR}/bin/hwloc-info"
    fi
    if $HWLOC_INFO_EXE --version &>/dev/null ; then
      HWLOC_VERSION_HWLOCINFO="$($HWLOC_INFO_EXE --version 2>/dev/null | perl -ne 'm/(.*) (.*)/;print $2')"
    fi

    # Add libnuma manually, if necessary
    for hwloc_lib_dir in ${HWLOC_LIB_DIRS} ; do
        if grep -q '[-]lnuma' ${hwloc_lib_dir}/libhwloc.la 2>/dev/null; then
            if ! echo '' ${HWLOC_LIBS} '' | grep -q ' numa '; then
                HWLOC_LIBS="${HWLOC_LIBS} numa"
            fi
        fi
    done
fi


################################################################################
# Configure Cactus
################################################################################

# Pass configuration options to build script
echo "BEGIN MAKE_DEFINITION"
echo "HWLOC_BUILD       = ${HWLOC_BUILD}"
echo "HWLOC_INSTALL_DIR = ${HWLOC_INSTALL_DIR}"
echo "END MAKE_DEFINITION"

HWLOC_INC_DIRS="$(${CCTK_HOME}/lib/sbin/strip-incdirs.sh ${HWLOC_INC_DIRS})"
HWLOC_LIB_DIRS="$(${CCTK_HOME}/lib/sbin/strip-libdirs.sh ${HWLOC_LIB_DIRS})"
HWLOC_LIBS="${HWLOC_LIBS} ${HWLOC_EXTRA_LIBS}"

# Pass options to Cactus
echo "BEGIN MAKE_DEFINITION"
echo "HWLOC_DIR      = ${HWLOC_DIR}"
echo "HWLOC_INC_DIRS = ${HWLOC_INC_DIRS}"
echo "HWLOC_LIB_DIRS = ${HWLOC_LIB_DIRS}"
echo "HWLOC_LIBS     = ${HWLOC_LIBS}"
echo "END MAKE_DEFINITION"

# Pass version information to Cactus in case it is not included in hwloc.h (for
# versions less than 2.1)
echo "BEGIN MAKE_DEFINITION"
echo "HWLOC_VERSION_PKGCONFIG = ${HWLOC_VERSION_PKGCONFIG}"
echo "HWLOC_VERSION_HWLOCINFO = ${HWLOC_VERSION_HWLOCINFO}"
echo "HWLOC_VERSION_BUILD = ${HWLOC_VERSION_BUILD}"
echo "END MAKE_DEFINITION"

echo 'INCLUDE_DIRECTORY $(HWLOC_INC_DIRS)'
echo 'LIBRARY_DIRECTORY $(HWLOC_LIB_DIRS)'
echo 'LIBRARY           $(HWLOC_LIBS)'
