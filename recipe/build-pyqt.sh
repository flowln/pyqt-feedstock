set -exou

pushd pyqt
cp LICENSE ..

SIP_COMMAND="sip-build"
EXTRA_FLAGS=""

if [[ $(uname) == "Linux" ]]; then
    USED_BUILD_PREFIX=${BUILD_PREFIX:-${PREFIX}}
    echo USED_BUILD_PREFIX=${BUILD_PREFIX}

    ln -s ${GXX} g++ || true
    ln -s ${GCC} gcc || true
    ln -s ${USED_BUILD_PREFIX}/bin/${HOST}-gcc-ar gcc-ar || true

    export LD=${GXX}
    export CC=${GCC}
    export CXX=${GXX}
    export PKG_CONFIG_EXECUTABLE=$(basename $(which pkg-config))

    chmod +x g++ gcc gcc-ar
    export PATH=${PWD}:${PATH}

    SYSROOT_FLAGS="-L ${BUILD_PREFIX}/${HOST}/sysroot/usr/lib64 -L ${BUILD_PREFIX}/${HOST}/sysroot/usr/lib"
    export CFLAGS="$SYSROOT_FLAGS $CFLAGS"
    export CXXFLAGS="$SYSROOT_FLAGS $CXXFLAGS"
    export LDFLAGS="$SYSROOT_FLAGS $LDFLAGS"
fi

if [[ $(uname) == "Darwin" ]]; then
    # Use xcode-avoidance scripts
    export PATH=$PREFIX/bin/xc-avoidance:$PATH
fi

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; then
  SIP_COMMAND="$BUILD_PREFIX/bin/python -m sipbuild.tools.build"
  SITE_PKGS_PATH=$($PREFIX/bin/python -c 'import site;print(site.getsitepackages()[0])')
  EXTRA_FLAGS="--target-dir $SITE_PKGS_PATH"
fi

# Workaround for building QtDesigner plugin on Qt 5.15.x
read -r PYLIB_DIR PYLIB_LIB PYLIB_SHLIB <<< $(cat <<EOF | $PREFIX/bin/python

import sys
from glob import glob
from sysconfig import get_config_vars

py_major, py_minor, *_ = sys.version_info
ducfg = get_config_vars()

exec_prefix = ducfg['exec_prefix']
multiarch = ducfg.get('MULTIARCH', '')
libdir = ducfg['LIBDIR']

if glob('{}/lib/libpython{}.{}*'.format(exec_prefix, py_major, py_minor)):
    pylib_dir = exec_prefix + '/lib'
elif multiarch != '' and glob('{}/lib/{}/libpython{}.{}*'.format(exec_prefix, multiarch, py_major, py_minor)):
    pylib_dir = exec_prefix + '/lib/' + multiarch
elif glob('{}/libpython{}.{}*'.format(libdir, py_major, py_minor)):
    pylib_dir = libdir

abi = getattr(sys, 'abiflags', '')
pylib_lib = 'python{}.{}{}'.format(py_major, py_minor, abi)

pylib_shlib = ducfg.get('LDLIBRARY', '')

print(pylib_dir, pylib_lib, pylib_shlib)

EOF)

cat <<EOF >> pyproject.toml

[tool.sip.project]
py-pylib-dir = "$PYLIB_DIR"
py-pylib-lib = "$PYLIB_LIB"
py-pylib-shlib = "$PYLIB_SHLIB"

EOF

$SIP_COMMAND \
--verbose \
--confirm-license \
--no-make \
$EXTRA_FLAGS

pushd build

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; then
  # Make sure BUILD_PREFIX sip-distinfo is called instead of the HOST one
  cat Makefile | sed -r 's|\t(.*)sip-distinfo(.*)|\t'$BUILD_PREFIX/bin/python' -m sipbuild.distinfo.main \2|' > Makefile.temp
  rm Makefile
  mv Makefile.temp Makefile
fi

CPATH=$PREFIX/include make -j$CPU_COUNT
make install
