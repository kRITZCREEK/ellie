import base64
import json
import os
import re
from datetime import datetime, timedelta
from hashlib import sha256
from hmac import new as hmac
from typing import (Any, Dict, Iterator, List, NamedTuple, Optional, Pattern,
                    Set, Tuple, TypeVar)
from urllib.parse import quote, unquote

import boto3
import requests
import whoosh.analysis as analysis
import whoosh.fields as fields
import whoosh.index as index
import whoosh.qparser as qparser
from flask import request

from . import constants
from .data.package import Package
from .data.package_info import PackageInfo
from .data.package_name import PackageName
from .data.project_id import ProjectId
from .data.revision import Revision
from .data.revision_id import RevisionId
from .data.version import Version

# TYPE VARS


T = TypeVar('T')


# CONSTANTS

_REPLACE_RE: Pattern = re.compile('\=+$')
_s3 = boto3.resource('s3')
_s3_client = boto3.client('s3')
_s3_bucket = _s3.bucket(constants.S3_BUCKET)
_INFOS_PATH = 'package-artifacts/searchable.json'
_CACHE_TTL: timedelta = timedelta(minutes=15)

_all_elm_versions = [
    Version(0, 18, 0),
    Version(0, 17, 1),
    Version(0, 17, 0),
    Version(0, 16, 0),
    Version(0, 15, 0)
]

_searchable_elm_versions = [
    Version(0, 18, 0)
]

_index_dir = ".packages_index"

_analyzer = analysis.NgramWordAnalyzer(
    2,
    maxsize=None,
    tokenizer=analysis.RegexTokenizer(
        expression=re.compile("[/-]"), gaps=True)
)

_schema = fields.Schema(
    username=fields.TEXT(analyzer=_analyzer, phrase=False, field_boost=1.5),
    package=fields.TEXT(analyzer=_analyzer, phrase=False),
    full_name=fields.TEXT(analyzer=_analyzer, phrase=False),
    full_package=fields.STORED
)

_parser = qparser.MultifieldParser(["username", "package"], _schema)


# HELPERS


def _cat_optionals(data: Iterator[Optional[T]]) -> Iterator[T]:
    for x in data:
        if x is not None:
            yield x


def _parse_int(string: str) -> Optional[int]:
    try:
        return int(string)
    except:
        return None


def _build_cache(infos: List[PackageInfo]) -> Dict[PackageName, Dict[Version, List[Version]]]:
    data: Dict[PackageName, Dict[Version, List[Version]]] = {}
    for info in infos:
        if info.elm_constraint is None:
            continue
        key = PackageName(info.username, info.package)
        if key not in data:
            data[key] = {}
        for elm_version in _all_elm_versions:
            if info.elm_constraint.is_satisfied(elm_version):
                if elm_version not in data[key]:
                    data[key][elm_version] = []
                data[key][elm_version].append(info.version)
    return data


def _download_infos() -> List[PackageInfo]:
    body = _s3.Object(constants.S3_BUCKET, _INFOS_PATH).get()['Body']
    data = body.read()
    packages = list(
        _cat_optionals(PackageInfo.from_json(x) for x in json.loads(data)))
    body.close()
    return packages


def _build_index(packages: List[PackageInfo]) -> Dict[Version, Any]:
    indices: Dict[Version, Any] = {}
    for elm_version in _searchable_elm_versions:
        idx_path = _index_dir + "/" + str(elm_version)
        if not os.path.exists(idx_path):
            os.makedirs(idx_path)
        idx = index.create_in(idx_path, _schema)
        writer = idx.writer()

        latest_packages: Dict[PackageName, PackageInfo] = {}
        for package_info in packages:
            constraint = package_info.elm_constraint
            if constraint is not None and constraint.is_satisfied(elm_version):
                name = PackageName(package_info.username, package_info.package)
                current = latest_packages.get(name)
                if current is None or package_info.version > current.version:
                    latest_packages[name] = package_info

        for name, info in latest_packages.items():
            writer.add_document(
                username=info.username,
                package=info.package,
                full_name=str(name),
                full_package=Package(name, info.version)
            )

        writer.commit()
        indices[elm_version] = idx
    return indices


def _init_local_data() -> Tuple[Dict[PackageName, Dict[Version, List[Version]]], Dict[Version, Any]]:
    infos = _download_infos()
    return (_build_cache(infos), _build_index(infos))


def _refresh_local_data() -> None:
    global _tags_lookup
    global _search_index
    now = datetime.utcnow()
    if now - _last_updated > _CACHE_TTL:
        _last_updated = datetime.utcnow()
        (tags, index) = _init_local_data()
        _tags_lookup = tags
        _search_index = index


def _sign_cookie(value: str) -> str:
    mac = hmac(constants.COOKIE_SECRET, msg=None, digestmod=sha256)
    mac.update(value.encode('utf-8'))
    b64 = base64.b64encode(mac.digest())
    replaced = b64.decode('utf-8').rstrip('=')
    return quote('s:' + value + '.' + replaced, safe='')


def _unsign_cookie(value: str) -> Optional[str]:
    unsigned_value = unquote(value[0:value.rfind('.')]).replace('s:', '')
    to_match = _sign_cookie(unsigned_value)
    return unsigned_value if to_match == value else None


def _get_owned_project_ids() -> Set[ProjectId]:
    raw = request.cookies.get('ownedProjects')
    if raw is None:
        return set()

    unsigned = _unsign_cookie(raw)
    if unsigned is None:
        return set()

    try:
        return set(
            _cat_optionals(
                ProjectId.from_string(x) for x in json.loads(unsigned)))
    except:
        return set()


def _project_id_is_owned(project_id: ProjectId) -> bool:
    return project_id in _get_owned_project_ids()


def _parse_query(query_string: str) -> Any:
    if "/" in query_string:
        split = query_string.split("/")
        username = split[0]
        package = split[1]
        print(username)
        print(package)
        if username == "" and package != "":
            return _parser.parse("package:" + package)
        elif username != "" and package == "":
            return _parser.parse("username:" + username)
        return _parser.parse("package:" + package + " username:" + username)
    else:
        return _parser.parse(query_string)


# GLOBALS


_last_updated = datetime.utcnow()
(_tags_lookup, _search_index) = _init_local_data()


# API


def save_searchable_package_infos(infos: List[PackageInfo]) -> None:
    _s3_bucket.put_object(
        Key='package-artifacts/searchable.json',
        ACL='public-read',
        Body=json.dumps([x.to_json() for x in infos]).encode('utf-8'),
        ContentType='application/json')


def save_failed_package_infos(infos: List[PackageInfo]) -> None:
    _s3_bucket.put_object(
        Key='package-artifacts/known_failures.json',
        ACL='public-read',
        Body=json.dumps([x.to_json() for x in infos]).encode('utf-8'),
        ContentType='application/json')


def save_package_info_data(info: PackageInfo, sources: Any, elm_package: Any, artifacts: Optional[Any]) -> None:
    if artifacts is not None:
        _s3_bucket.put_object(
            Key=info.s3_artifacts_key(Version(0, 18, 0)),
            ACL='public-read',
            Body=json.dumps(artifacts).encode('utf-8'),
            ContentType='application/json')
    _s3_bucket.put_object(
        Key=info.s3_package_key(),
        ACL='public-read',
        Body=json.dumps(elm_package).encode('utf-8'),
        ContentType='application/json')
    _s3_bucket.put_object(
        Key=info.s3_source_key(),
        ACL='public-read',
        Body=json.dumps(sources).encode('utf-8'),
        ContentType='application/json')


def get_all_package_infos() -> List[PackageInfo]:
    body = requests.get("http://package.elm-lang.org/all-packages")
    data = body.json()
    body.close()
    output = []
    for entry in data:
        username = entry['name'].split('/')[0]
        package = entry['name'].split('/')[1]
        for version in entry['versions']:
            v = Version.from_string(version)
            if v is not None:
                output.append(PackageInfo(username, package, v))
    return output


def get_searchable_package_infos() -> List[PackageInfo]:
    return _download_infos()


def get_failed_package_infos() -> List[PackageInfo]:
    obj = _s3.Object(constants.S3_BUCKET,
                     'package-artifacts/known_failures.json')
    body = obj.get()['Body']
    data = body.read()
    packages = list(_cat_optionals(PackageInfo.from_json(x)
                                   for x in json.loads(data)))
    body.close()
    return packages


def get_versions_for_elm_version_and_package(elm_version: Version, name: PackageName) -> List[Version]:
    _refresh_local_data()
    if name not in _tags_lookup or elm_version not in _tags_lookup[name]:
        return []
    return _tags_lookup[name][elm_version]


def get_revision_upload_signature(project_id: ProjectId,
                                  revision_number: int) -> Any:
    data = _s3_client.generate_presigned_post(
        Bucket=constants.S3_BUCKET,
        Key='revisions/' + str(project_id) + '/' + str(revision_number) +
        '.json',
        Fields={'acl': 'public-read',
                'Content-Type': 'application/json'},
        Conditions=[{
            'acl': 'public-read'
        }, {
            'Content-Type': 'application/json'
        }])

    data['projectId'] = str(project_id)
    data['revisionNumber'] = revision_number
    return data


def revision_exists(id: RevisionId) -> bool:
    try:
        _s3_client.head_object(
            Bucket=constants.S3_BUCKET,
            Key='revisions/' + str(id.project_id) + '/' +
            str(id.revision_number) + '.json'
        )
        return True
    except:
        return False


def get_revision(id: RevisionId) -> Optional[Revision]:
    try:
        data = _s3_client.get_object(
            Bucket=constants.S3_BUCKET,
            Key='revisions/' + str(id.project_id) + '/' + str(
                id.revision_number) + '.json'
        )
        body = data['Body']
        json_data = json.loads(body.read())
        json_data['owned'] = _project_id_is_owned(id.project_id)
        revision = Revision.from_json(json_data)
        body.close()
        return revision
    except Exception as e:
        return None


def search(elm_version: Version, query_string: str) -> List[Package]:
    _refresh_local_data()
    idx = _search_index.get(elm_version)
    if idx is None:
        return []

    with idx.searcher() as searcher:
        results = searcher.search(_parse_query(query_string), limit=5)
        return [r.fields()['full_package'] for r in results]
