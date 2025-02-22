#!/bin/bash -e

solver="${1}"
heffte_build_type="${2}"

#inititialize submodules if they aren't downloaded
[ -d "${libdir}/Elements/elements" ] && echo "Elements submodule exists"
[ -d "${libdir}/Elements/matar/src" ] && echo "matar submodule exists"


if { [ ! -d "${ELEMENTS_SOURCE_DIR}/elements" ] || [ ! -d "${ELEMENTS_SOURCE_DIR}/matar/src" ] ;}
then
    echo "Missing submodules, downloading them...."
    git submodule update --init --recursive
fi

if [ ! -d "${TRILINOS_INSTALL_DIR}/lib" ]; then
    Trilinos_DIR=${TRILINOS_INSTALL_DIR}/lib64/cmake/Trilinos
else
    Trilinos_DIR=${TRILINOS_INSTALL_DIR}/lib/cmake/Trilinos
fi

# Install Elements
if [ ! -d "${ELEMENTS_INSTALL_DIR}/lib" ]; then
    echo "Installing Elements..."
    cmake -D CMAKE_INSTALL_PREFIX="$ELEMENTS_INSTALL_DIR" -D Trilinos_DIR="${Trilinos_DIR}" -D Matar_ENABLE_KOKKOS=ON -D Matar_KOKKOS_PACKAGE=Trilinos -B "${ELEMENTS_BUILD_DIR}" -S "${ELEMENTS_SOURCE_DIR}"
    make -C "${ELEMENTS_BUILD_DIR}" -j${FIERRO_BUILD_CORES}
    make -C "${ELEMENTS_BUILD_DIR}" install
fi

# Removing stale build directory
if [ -d "${FIERRO_BUILD_DIR}" ]; then
    if make -C ${FIERRO_BUILD_DIR} distclean; then
        echo "";
    else
        echo "distclean failed. Removing build directory."
        rm -r ${FIERRO_BUILD_DIR}
    fi
else
    mkdir -p ${FIERRO_BUILD_DIR}
fi

# Configure EVPFFT using CMake
cmake_options=(
    -D CMAKE_PREFIX_PATH="$ELEMENTS_INSTALL_DIR"
    -D Trilinos_DIR="$Trilinos_DIR"
)

if [ "$solver" = "all" ]; then
    cmake_options+=(
        -D BUILD_PARALLEL_EXPLICIT_SOLVER=ON
        -D BUILD_IMPLICIT_SOLVER=ON
    )
elif [ "$solver" = "implicit" ]; then
    cmake_options+=(
        -D BUILD_PARALLEL_EXPLICIT_SOLVER=OFF
        -D BUILD_IMPLICIT_SOLVER=ON
    )
elif [ "$solver" = "explicit-evpfft" ]; then
    cmake_options+=(
        -D BUILD_PARALLEL_EXPLICIT_SOLVER=ON
        -D BUILD_IMPLICIT_SOLVER=OFF
        -D BUILD_EVPFFT_FIERRO=ON
        -D CMAKE_PREFIX_PATH="$HEFFTE_INSTALL_DIR;$HDF5_INSTALL_DIR;$ELEMENTS_INSTALL_DIR"
    )
    if [ "$heffte_build_type" = "cufft" ]; then
        cmake_options+=(
            -D USE_CUFFT=ON
        )   
    elif [ "$heffte_build_type" = "rocfft" ]; then
        cmake_options+=(
            -D USE_ROCFFT=ON
        )   
    else
        cmake_options+=(
            -D USE_FFTW=ON
        )
    fi
elif [ "$solver" = "explicit-evp" ]; then
    cmake_options+=(
        -D BUILD_PARALLEL_EXPLICIT_SOLVER=ON
        -D BUILD_IMPLICIT_SOLVER=OFF
        -D BUILD_EVP_FIERRO=ON
    )
else
    cmake_options+=(
        -D BUILD_PARALLEL_EXPLICIT_SOLVER=ON
        -D BUILD_IMPLICIT_SOLVER=OFF
    )
fi

# Print CMake options for reference
echo "CMake Options: ${cmake_options[@]}"

# Configure FIERRO
cmake "${cmake_options[@]}" -B "${FIERRO_BUILD_DIR}" -S "${FIERRO_BASE_DIR}"

# Build FIERRO
make -C "${FIERRO_BUILD_DIR}" -j${FIERRO_BUILD_CORES}

cd $basedir
