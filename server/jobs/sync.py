import base64
import json
import multiprocessing
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
import zipfile
from datetime import datetime
from typing import (Any, Dict, Iterator, List, NamedTuple, Optional, Set,
                    SupportsInt, Tuple, TypeVar)

import boto3
import glob2
import requests
from joblib import Parallel, delayed

from .. import constants, repository
from ..data.constraint import Constraint
from ..data.package_info import PackageInfo
from ..data.version import Version

# CONSTANTS


MIN_REQUIRED_VERSION = Version(0, 18, 0)
NUM_CORES = multiprocessing.cpu_count()


# HELPERS


def _glob_all(paths: List[str]) -> List[str]:
    output: List[str] = []
    for path in paths:
        output = output + glob2.glob(path)
    return output


def _make_temp_directory() -> str:
    return tempfile.mkdtemp(prefix='ellie-package-temp-')


def _download_package_zip(base_dir: str, package: PackageInfo) -> None:
    url = 'http://github.com/' + package.username + '/' + package.package + '/archive/' + str(
        package.version) + '.zip'
    zip_path = os.path.join(base_dir, 'temp.zip')
    try:
        r = requests.get(url)
        with open(zip_path, "wb") as local_file:
            for chunk in r.iter_content(chunk_size=128):
                local_file.write(chunk)
    except Exception as e:
        print("HTTP Error:", e)


def _unzip_and_delete(base_dir: str) -> None:
    zip_path = os.path.join(base_dir, 'temp.zip')
    zip_ref = zipfile.ZipFile(zip_path, 'r')
    zip_ref.extractall(base_dir)
    zip_ref.close()
    os.remove(zip_path)


def _read_package_json(base_dir: str, package: PackageInfo) -> Any:
    package_json_path = os.path.join(
        base_dir, package.package + '-' + str(package.version),
        'elm-package.json')
    json_data = None
    with open(package_json_path, 'r') as file_data:
        json_data = json.loads(file_data.read())
    return json_data


def _read_source_files(base_dir: str, package: PackageInfo,
                       package_json: Any) -> Any:
    package_dir = os.path.join(base_dir,
                               package.package + '-' + str(package.version))
    nested_elm = [
        os.path.join(package_dir, a, '**/*.elm')
        for a in package_json['source-directories']
    ]
    nested_js = [
        os.path.join(package_dir, a, '**/*.js')
        for a in package_json['source-directories']
    ]

    filenames = _glob_all(nested_elm + nested_js)
    output = {}
    for filename in filenames:
        with open(filename, 'r') as file_data:
            output[filename.replace(package_dir + '/', '')] = file_data.read()
    return output


def _read_artifacts(base_dir: str, package: PackageInfo) -> Any:
    artifacts_base = os.path.join(base_dir,
                                  package.package + '-' + str(package.version),
                                  'elm-stuff/build-artifacts/0.18.0/elm-lang/',
                                  package.package,
                                  str(package.version))
    artifacts = [
        os.path.join(artifacts_base, '*.elmo'),
        os.path.join(artifacts_base, '*.elmi')
    ]

    filenames = _glob_all(artifacts)
    output = {}
    for filename in filenames:
        key = filename.replace(artifacts_base + '/', '')
        with open(filename, 'rb') as file_data:
            if filename.endswith('elmi'):
                output[key] = base64.b64encode(
                    file_data.read()).decode('utf-8')
            else:
                output[key] = file_data.read().decode('utf-8')

    return output


def _get_current_time() -> int:
    epoch = datetime.utcfromtimestamp(0)
    dt = datetime.utcnow()
    return int((dt - epoch).total_seconds() * 1000.0)


def _process_package(info: PackageInfo) -> Tuple[bool, PackageInfo]:
    try:
        base_dir = _make_temp_directory()
        _download_package_zip(base_dir, info)
        _unzip_and_delete(base_dir)
        package_json = _read_package_json(base_dir, info)
        constraint = Constraint.from_string(package_json['elm-version'])
        if constraint is None:
            shutil.rmtree(base_dir)
            return (False, info)

        if not constraint.is_satisfied(MIN_REQUIRED_VERSION):
            shutil.rmtree(base_dir)
            return (False, info)

        info.set_elm_constraint(constraint)

        artifacts = None
        if info.username == 'elm-lang':
            elm_path = os.path.realpath(
                os.path.dirname(os.path.realpath(__file__)) +
                '/../node_modules/elm/Elm-Platform/0.18.0/.cabal-sandbox/bin/elm-make')

            package_dir = os.path.join(
                base_dir, info.package + '-' + str(info.version))

            process_output = subprocess.run(
                [elm_path, '--yes'],
                cwd=package_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE)

            if process_output.returncode != 0:
                stderr_as_str = process_output.stderr.decode('utf-8')
                raise Exception(stderr_as_str)

            artifacts = _read_artifacts(base_dir, info)

        source_files = _read_source_files(base_dir, info, package_json)

        repository.save_package_info_data(
            info, source_files, package_json, artifacts)
        shutil.rmtree(base_dir)
        return (True, info)
    except:
        shutil.rmtree(base_dir)
        print(info)
        print(sys.exc_info())
        return (False, info)


# API


def run() -> None:
    print('sync_packages: downloading package data')

    packages = repository.get_all_package_infos()
    searchable = set(repository.get_searchable_package_infos())
    known_failures = set(repository.get_failed_package_infos())

    filtered_packages = [
        p for p in packages if p not in searchable and p not in known_failures]

    package_groups = [
        filtered_packages[x:x + NUM_CORES]
        for x in range(0, len(filtered_packages), NUM_CORES)
    ]

    counter = 0
    total = len(filtered_packages)
    failed = []
    for package_group in package_groups:
        results = Parallel(n_jobs=NUM_CORES)(delayed(_process_package)(i)
                                             for i in package_group)
        counter += NUM_CORES
        for (succeeded, package) in results:
            if succeeded:
                searchable.add(package)
            else:
                failed.append(package)

        print('sync_packages: ' + str((counter * 100) // total) + '%')

    repository.save_searchable_package_infos(list(searchable))
    repository.save_failed_package_infos(failed + list(known_failures))
    print('sync_packages: finished')


# CLI


if __name__ == "__main__":
    run()
