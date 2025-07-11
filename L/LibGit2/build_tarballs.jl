using BinaryBuilder, Pkg
using BinaryBuilderBase: sanitize, get_addable_spec

name = "LibGit2"
version = v"1.9.1"

# Collection of sources required to build libgit2
sources = [
    GitSource("https://github.com/libgit2/libgit2.git", "0060d9cf5666f015b1067129bd874c6cc4c9c7ac")
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/libgit2*

BUILD_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="${prefix}"
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TARGET_TOOLCHAIN}"
    -DBUILD_CLI=OFF
    -DBUILD_TESTS=OFF
    -DUSE_BUNDLED_ZLIB=OFF
    -DUSE_SSH=ON
    -DUSE_THREADS=ON
    -DREGEX_BACKEND=pcre2
)

if [[ ${bb_full_target} == *-sanitize+memory* ]]; then
    # Install msan runtime (for clang)
    cp -rL ${libdir}/linux/* /opt/x86_64-linux-musl/lib/clang/*/lib/linux/
fi

if [[ ${target} == *-mingw* ]]; then
    # Special Windows flags
    BUILD_FLAGS+=(-DWIN32=ON -DMINGW=ON)
    if [[ ${target} == i686-* ]]; then
        BUILD_FLAGS+=(-DCMAKE_C_FLAGS="-mincoming-stack-boundary=2")
    fi

    # For some reason, CMake fails to find libssh2 using pkg-config.
    BUILD_FLAGS+=(-Dssh2_RESOLVED=${bindir}/libssh2.dll)
elif [[ ${target} == *linux* ]] || [[ ${target} == *freebsd* ]] || [[ ${target} == *openbsd* ]]; then
    # If we're on Linux or FreeBSD, explicitly ask for OpenSSL
    BUILD_FLAGS+=(-DUSE_HTTPS=OpenSSL -DUSE_SHA1=CollisionDetection -DCMAKE_INSTALL_RPATH="\$ORIGIN")
fi

cmake -B build "${BUILD_FLAGS[@]}"
cmake --build build --parallel ${nproc}
cmake --install build
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = supported_platforms()
push!(platforms, Platform("x86_64", "linux"; sanitize="memory"))

# The products that we will ensure are always built
products = [
    LibraryProduct("libgit2", :libgit2),
]

llvm_version = v"13.0.1"

# Dependencies that must be installed before this package can be built
dependencies = [
    Dependency("LibSSH2_jll"; compat="1.11.3"),
    Dependency("OpenSSL_jll"; compat="3.0.16", platforms=filter(p -> !(Sys.iswindows(p) || Sys.isapple(p)), platforms)),
    Dependency("PCRE2_jll"),
    Dependency("Zlib_jll"; compat="1.2.12"),
    BuildDependency(PackageSpec(name="LLVMCompilerRT_jll", uuid="4e17d02c-6bf5-513e-be62-445f41c75a11", version=llvm_version);
                    platforms=filter(p -> sanitize(p)=="memory", platforms)),
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat="1.9", preferred_llvm_version=llvm_version)
