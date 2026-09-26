"""Build the pinned offline inference executable with the Windows Android NDK."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile

REVISION = '79bfc1d43a2e1e790f455522e0b4edbef7e9d22c'
ARCHIVE_SHA256 = 'f62edc5d11a8b9d219efd4ba950ce9ab30197bc7ed2103941865b9acca34b8fd'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sdk',type=Path,required=True,help='Android SDK directory')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    cache=root/'.slm-build'
    cache.mkdir(exist_ok=True)
    archive=cache/'source.zip'
    if not archive.exists():
        urllib.request.urlretrieve(f'https://github.com/ggml-org/llama.cpp/archive/{REVISION}.zip',archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=ARCHIVE_SHA256:
        raise RuntimeError('Source archive checksum does not match the tested build')
    source=cache/f'llama.cpp-{REVISION}'
    if not source.exists():
        with zipfile.ZipFile(archive) as z:
            for item in z.infolist():
                if not (cache/item.filename).resolve().is_relative_to(cache.resolve()):
                    raise RuntimeError('Archive path escapes build directory')
            z.extractall(cache)
    ndk=args.sdk/'ndk/27.0.12077973'
    cmake=args.sdk/'cmake/3.22.1/bin/cmake.exe'
    make=ndk/'prebuilt/windows-x86_64/bin/make.exe'
    build=cache/'android-arm64'
    subprocess.run([str(cmake),'-S',str(source),'-B',str(build),'-G','MinGW Makefiles',
        f'-DCMAKE_MAKE_PROGRAM={make.as_posix()}',
        f'-DCMAKE_TOOLCHAIN_FILE={(ndk/"build/cmake/android.toolchain.cmake").as_posix()}',
        '-DANDROID_ABI=arm64-v8a','-DANDROID_PLATFORM=android-28','-DCMAKE_BUILD_TYPE=Release',
        '-DGGML_NATIVE=OFF','-DGGML_OPENMP=OFF','-DGGML_LLAMAFILE=OFF','-DLLAMA_OPENSSL=OFF',
        '-DBUILD_SHARED_LIBS=OFF','-DANDROID_STL=c++_static','-DLLAMA_BUILD_TESTS=OFF',
        '-DLLAMA_BUILD_EXAMPLES=OFF','-DLLAMA_BUILD_SERVER=OFF'],check=True)
    subprocess.run([str(cmake),'--build',str(build),'--target','llama-completion','-j','6'],check=True)
    target=root/'android/app/src/main/jniLibs/arm64-v8a/libgolf_slm.so'
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(build/'bin/llama-completion',target)
    for p in source.rglob('*'):
        if p.is_file() and ('LICENSE' in p.name.upper() or p.name.upper()=='COPYING'):
            destination=root/'android/app/src/main/assets/slm_licenses'/p.relative_to(source)
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(p,destination)
    print('Android offline executable ready:',target)

if __name__=='__main__':main()
