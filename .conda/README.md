# Building Anaconda Packages
This folder holds some recipies and shared scripts for building several anaconda packages. The end goal is to distribute EVPFFT and Fierro for several CPU architecture, OS and GPU combinations.

## Primer on Anaconda

### Anaconda Environments
Anaconda primarily functions by creating an environment that mirrors your OS's system folder structure inside a user owned folder. If you are on linux-64 and have a root folder stucture that looks like:

```
/bin
/lib
/include
/etc
/var
/cmake
...
```
Then when you make an Anaconda environment, it will have a similar structure:
```
~/anaconda3/envs/MyEnv/bin
~/anaconda3/envs/MyEnv/lib
~/anaconda3/envs/MyEnv/include
~/anaconda3/envs/MyEnv/etc
~/anaconda3/envs/MyEnv/var
~/anaconda3/envs/MyEnv/cmake
...
```

Then, when you activate an Anaconda environment, it will set several environment variables that means that your terminal and tools launched from your terminal will look in the Anaconda environment folders first to find things.

### Packages
Anaconda is a "package" manager that hooks into a couple of opensource package distribution streams. A "package" in Anaconda is a collection of files, with relative file structure, and some metadata. The metadata primarily covers two things:
1. What the version, build number, and name of the of the package is.
2. What *other* packages this one depends on (i.e. is required to be installed in the system for this package to function as expected)

The packages built and used in this repository come in 2 flavors: native, and system agnostic (re: "noarch"). 

#### Native Packages
The native packages in this repo are all C++/C/Fortran packages that are compiled and managed by CMake. These are installed into a system via "install" targets generated by the CMake commands and running `make install`. This generally means that the relative folder structure of the package consists of a `/bin`, `/lib[64]`[^1] and `/include` folders. The `/include` folder contains all of the header files for C/C++, while the `/lib` and `/bin` folders contain architecture/OS specific libraries and executable binaries, respectively.

[^1]: Whether the folder is called "lib" or "lib64" is usually a choice made by the compiler used.

#### Noarch Packages
While it is possible to have hardware agnostic packages that *aren't* python based, ours are. These packages consist of python modules that are installed under `/lib/python$VERSION/site-packages/`. Anaconda has special handling for *noarach* python packages and will install the python module into the currently active python folder without you having to specify the version.

### Distribution Streams
These packages are almost always obtained through an anaconda *channel*. A *channel* is a web hosted repository of packages. There are 3 main channels/types of channels:
1. defaults -- The default channel included with Anaconda
2. conda-forge -- A community led, opensource channel containing more niche packages
3. user channels -- Each user with an account on Anaconda.org has their own public channel

When you run `conda install X` anaconda will look at the configured channels for `X` and its dependencies. You can change the configured channels by editing your `~/condarc.yaml` file or by appending `... -c <channel-name>` to your install command. 

### Anaconda Build System
Anaconda also has a build system, with conda-build, for creating the target packages. conda-build takes a *recipe* (instructions on what the package is and how to build it) and creates a package. This package can then be uploaded to a channel.

The build recipe for a package is a folder that usually contains the following:
```
/build.sh  -- Bash script to build and install your package into your local system
/bld.bat   -- If building on Windows systems
/LICENSE
/meta.yaml -- Metadata about the package
/conda_build_config.yaml -- Metadata for conda-build
```

When conda-build goes to build your package, it will create two temporary environments in which to compile/install your code - a *build* and *host* environment. These will exist under `~/anaconda3/conda-bld/` and can be deleted with `conda build purge`. The *build* environment contains the compilers and build tools that need to run on the build system. The *host* environment, on the other hand, contains the packages that your program can link against. This distinction exists to support cross-compiling, where the *host* system contains binaries that are uninterpretable by the *build* system. 

If the `build.sh` script runs successfully, your program should be installed into the *host* environment. Anaconda then looks at this environment to see what changed, and collects the new build artifacts that you generated to put into a package.

## Our Packages
When creating these recipes for our packages, a few things needed to be solved beyond the most basic Anaconda packages:
1. Compiling and installing C++
2. Building native packages for several OS + CPU architecture combinations
3. Cross compiling on both MacOS-arm64 and Linux-64 systems for other CPU architectures
4. Compiling for different GPU hardware
5. Distributing native hardware Python extensions

### Compiling C++ Packages
To make valid C++ packages all that is necessary is to define an appropriate CMake *install* target, such that `make install` will relocate the correct files/binaries. Most robust CMake projects support this already and there are plenty of example of doing this. However, we need to change our typical `cmake` command to include the following additional arguments: `-DCMAKE_INSTALL_PREFIX=$PREFIX $CMAKE_ARGS`. When using conda-bld, the `$PREFIX` variable tells you where Anaconda wants you to install your package. Similarly, the `$CMAKE_ARGS` variable contains several arguments that point CMake to the correct[^2] versions of several compiler related binaries.

The only thing left to consider is linking. To make a valid package, all of the libraries that your project links to must be included in the *host* system, and be located exactly where you project expects. This means either the dependencies are all Anaconda packages themselves, or in a very narrow set of circumstances some system libraries can reliably be found in the host system.

For this repo, we had to create a couple of dependency packages for distribution: Heffte, Trilinos, Elements. 

[^2]: The correct ones may not be the ones you expect if you are cross compiling.

### Cross Compiling
Anaconda has robust support for cross compiling within an operating system. It has two tools that are essentially to successfully cross-compiling: the build matrix and compiler packages. The build matrix is a combination of variants listed in the `conda_build_config.yaml` file. This file contains a list of arbitrary keys that map to lists and instructs conda-build to run multiple times with different configurations. In the case of *our* build config file (`build_variants.yaml`), it looks the following on linux:
```yaml
c_compiler:
  - gcc
cxx_compiler:
  - gxx
target_platform:
  - linux-64
  - linux-aarch64 
  - linux-ppc64le
```

When `conda-build` is run and given this config file, it will take the cartesian product of each list of options and run conda-build for each one. In this case, it will run with the following configurations:
```yaml
{ c_compiler: gcc, cxx_compiler: gxx, target_platform: linux-64 }
{ c_compiler: gcc, cxx_compiler: gxx, target_platform: linux-aarch64 }
{ c_compiler: gcc, cxx_compiler: gxx, target_platform: linux-ppc64le }
```

In general, the keys can be anything you want. However, these three keys happen to be recognized by anaconda functionality. In our C++ package meta.yaml files, we have the following specified as a *build* dependency: `{{ compiler('cxx') }}`. This is a special template variable that gets compiled into the package name: `$cxx_compiler _ $target_platform`. Additionally, there are several packages on the Anaconda defaults channel named things like `gxx_linux-64` or `gxx_linux-aarch64`. These packages contain gxx, AR, ld, CPPFILT, and other compiler tools that go into cross compiling from your current linux system to the `target_platform`. These compiler packages are what allow us to create binaries that contain other machine instructions other than what our machine can interpret. 

Note: It is possible to cross compile across operating systems, but it is typically more work than its worth and can occasionally require a system with the target OS on hand anyway.

#### Architecture flags
Anaconda injects a few optimization flags into CXXFLAGS. Additionally, some of our packages contain compiler flags that instructs the compiler to apply vectorization optimizations. To ensure our builds are as portable as possible, we have a script for patching those flags to ensure that we are creating binaries with valid machine instructions for all kinds of CPU hardware. This is located under `/.conda/patch_conda_cxxflags.sh` and exports the variables: `PATCHED_CXXFLAGS` and `VECTOR_ARCH_FLAGS`. 


#### Exit Codes
CMake supports running test code to see if the compilation of dependent modules completed successfully. However, if we are cross compiling, it is impossible for us to execute the compiled code. As a result, it will always fail. To circumvent this, we override the results of those tests with valid exit codes. This can be seen in the Trilinos CPU and CUDA packages -- 
```
cmake ...
      ...
      -D HAVE_TEUCHOS_LAPACKLARND=0 \
      -D HAVE_TEUCHOS_BLASFLOAT=0 \
      -D HAVE_GCC_ABI_DEMANGLE=0 \
      -D KOKKOSKERNELS_TPL_BLAS_RETURN_COMPLEX_EXITCODE=0 \
      -D KK_BLAS_RESULT_AS_POINTER_ARG_EXITCODE=0 \
```
Here, we hardcode the exit codes of those test scripts to be 0 (valid), which allows the build to continue.

### Building for different OSs
We need to build these packages for both Linux and MacOS. However, we don't always have reliable access to both kinds of machines. To make these builds, we rely on CI/CD tools via Github Actions to run our builds on both Linux and MacOS systems. For more details, checkout the `.github` folder. 

### Compiling for GPU Hardware
Anaconda is able to detect the presence of GPU hardware through virtual packages. These are small system packages that can run some code to determine if the necessary hardware + drivers are installed. In the case of NVIDIA, the package is called `__cuda` and will be present in your system if you have the capability of running CUDA code. This package is actually what Kokkos uses to key off of to determine what version of Kokkos to install. However, we have opted instead to have separate packages with the "-cuda" or "-hip" suffix depending on how it was compiled.

In the case of CUDA, we get our package dependencies from the [nvidia](https://anaconda.org/nvidia/repo) anaconda channel. Here we need two kinds of packages, the NVCC compiler tools found in the cuda-toolkit package as well as the runtime dependencies like `libcufft-dev` or `libcublas-dev`. The `cuda-toolkit` package goes into the *build* dependencies while the runtime libraries go into the *host* dependencies.

#### Cross Compiling CUDA
When compiling CUDA kernels with `nvcc`, the default behavior is to search your local system for CUDA supported hardware and compile for that hardware target. However, in our cases, we typically want to compile either from a machine that doesn't have a CUDA GPU at all, or for a more general audience of machines. This is done by asking `nvcc` to generate code that is compatible with a relatively general set of CUDA GPUs. To control this, we have `gencode`, and `arch` compiler flags[^3]. For our purposes, we target "sm_50" (Maxwell), because Kokkos can only compile for a single architecture target at once[^4]. The `arch` flag controls which hardware target the PTX code is compiled for natively, while the `gencode` flag controls which targets PTX code is generated for. If you don't compile the PTX for a target GPU, but did generate the PTX for it, the code will be JIT'ed at runtime, incurring a ~small performance cost. 

[^3]: More information can be found [here](https://stackoverflow.com/questions/35656294/cuda-how-to-use-arch-and-code-and-sm-vs-compute).
[^4]: For more details on compute compatibility, see [this post](https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/).

#### Trilinos/Kokkos CUDA
When compiling Kokkos with a CUDA backend (and by extension Trilinos), a compiler wrapper...wrapper is provided (`nvcc_wrapper`). All this does is change some compiler flags from ones that are not supported by `nvcc` to ones that are. The important thing here is that we set the correct variables to specify the internal compilers for each wrapper we use. In the case of Trilinos, we need to use 3 compiler wrappers: MPI, nvcc_wrapper, and nvcc. To ensure that these wrappers end up wrapping the right compilers, we set `OMPI_CXX=nvcc_wrapper` so that `mpicxx` calls `nvcc_wrapper`. `nvcc_wrapper` already calls `nvcc`, but we need to set `NVCC_WRAPPER_DEFAULT_COMPILER=$GXX` so `nvcc_wrapper` gives `nvcc` the right compiler and `nvcc` ultimately calls `$GXX`, which is set by Anaconda to the appropriate build compiler/cross compiler. To get Kokkos to set the right `arch` flag, we use the CMake variable `Kokkos_ARCH_MAXWELL50=ON`.

### Native Python Extensions
Lastly, we need to compile C++ into Python extensions to offer a python interface to some of our C++ programs. For details on how that build works and an example, see `/python/Voxelizer`. But here we will just discuss the packaging considerations. These are python libraries, but unlike other python libraries, they contain native machine code and are potentially cross compiled. So instead of specifying `python` as a *host* dependency, we specify `python`, `pybind11` and a c++ compiler as build dependencies. 

We then use the locally install `pybind11` to build the python package. As a minor modification to our build script, `pip install .` would install the package into the *build* environment, so we use `pip install . --prefix=$PREFIX` to tell our local pip to install the pacakge into the *host* environment for Anaconda to pick it up. Additionally, since this method installs into a specific `/lib/python*.*/` folder, and the python ABI can change between each minor version, we have to build the native python package for all supported python minor versions separately. With our voxelizer, we are doing this by adding in more things to the conda build matrix. We additionally specify another conda_build_config.yaml file like this:
```yaml
python:
  - 3.8
  - 3.9
  - 3.10
  - 3.11
  - 3.12
```
This will tell conda-build to do all of the build configurations specified by our `build_variants.yaml` file for each of the python versions listed here. At the time of writing, this package is compiled 25 times, for MacOS (64 and arm64), Linux (64, arm64, powerpc) and for each python version listed here. All of these packages are then hosted on Anaconda.org, and the user gets whichever one makes sense for their environemnt automatically. Lastly, we ensure that these python versions get used in our `meta.yaml` recipy file by specifying `python={{ python }}` for build, host and runtime dependencies.


### Metapackages
Metapackages are packages that contain no installable content or build instructions, but only contain metadata. The can range from completely useless to useful shortcuts for pulling in a number of packages, or complicated/specific package dependencies. We use metapackages to make it easy to set up the development environments for Fierro and EVPFFT. Our dev packages (Fierro-dev, EVPFFT-dev) only contain runtime dependencies, and are created so you can run something like:
```
conda create -n fierro-dev fierro-dev -c kwelsh-lanl -c conda-forge
conda activate fierro-dev
```
And then you have all of the dependencies necessary to successfully build Fierro from source.

These packages are `noarch: generic` packages, because they don't contain any architecture/OS specific build artifacts themselves. Whether or not you can install them on your system depends solely on the dependencies being available.


## Debugging Tips
Anaconda packages are great when they work, but debugging them can be a pain, since it takes so long (relatively) to initailize the build environment. If you find yourself having to debug a conda package, don't waste time and follow these tips:


### Inspect the build/host environments.
The intermediate build environments created can be found under `~/anaconda3/conda-bld/`. These are cleaned up if the build is successful, but are left for inspecting if it fails. Your intermediate environemnts might look something like `~/mambaforge/conda-bld/fierro-cpu_1702931506301`, and ones that are still around can be uncovered by running `conda env list`:
```
# conda environments:
#
                         ~/anaconda3
base                  *  ~/mambaforge
                         ~/mambaforge/conda-bld/cross-apple-test_1699913171912/_build_env
                         ~/mambaforge/conda-bld/fierro-cpu_1702931083445/_build_env
                         ~/mambaforge/conda-bld/fierro-cpu_1702931506301/_build_env
                         ~/mambaforge/conda-bld/fierro-evpfft_1700005728459/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702567877996/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702568248715/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702569485778/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702571726755/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702572653009/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702573356532/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702581207071/_build_env
                         ~/mambaforge/conda-bld/fierro-heffte-cuda_1702582399999/_build_env
                         ~/mambaforge/conda-bld/fierro-voxelizer-py_1700001705130/_build_env
                         ~/mambaforge/conda-bld/fierro-voxelizer-py_1700003960166/_build_env
                         ~/mambaforge/conda-bld/fierro-voxelizer-py_1700006765747/_build_env
EVPFFT_MATAR             ~/mambaforge/envs/EVPFFT_MATAR
...                      ...

```

Under that build folder you will find 3 relevant things:
1. `_build_env` -- The environment where your "build" dependencies get installed (aka `$BUILD_PREFIX`)
2. `_h_env_placehold_placehold_placehold_placehold_placehold...` -- The environment where your "host" dependencies get installed, and where you install your package (aka `$PREFIX`).
3. `work` -- Where your source files are placed + where `conda_build.sh` (the exact script that is run) can be found.

You can activate each of these environments or just inspect the installed packages with `conda list -p <path>`.

### Modify and rebuild under `work`
If you think you identified the issue, don't go back and try the package build again. First modify the intermediate build files and try the rebuild from there. If you think you are missing a host dependency, for example, run `conda install <package> -p <path-to-host-env>` and rerun `work/conda_build.sh` to see if that fixes it. If you think you need to modify the build script, just change `conda_build.sh` and rerun. Once the package builds successfully, make sure to make you changes to the original `meta.yaml` and/or `build.sh` files and then try the package build again.

### Targetting Cross Compiling
If you are having issues with the cross-compiling build targets, you can speicfically target just those by adding `--variants "{ target_platform: linux-aarch64 }"`. If you are using the `.conda/build_variants.yaml` file, you will need to comment out the variants you don't want to test.