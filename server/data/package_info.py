from typing import Any, Dict, Optional

from .constraint import Constraint
from .package import Package
from .package_name import PackageName
from .version import Version


class PackageInfo(object):
    def __init__(self, username: str, package: str, version: Version) -> None:
        self.username = username
        self.package = package
        self.version = version
        self.elm_constraint: Optional[Constraint] = None

    def __str__(self) -> str:
        return self.username + '/' + self.package + '@' + str(self.version)

    def __repr__(self) -> str:
        return '<PackageInfo ' + self.__str__() + '>'

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, PackageInfo):
            return False
        return self.username == other.username and \
            self.package == other.package and \
            self.version == other.version

    def __neq__(self, other: object) -> bool:
        return not self.__eq__(other)

    def __hash__(self) -> int:
        return hash(self.__str__())

    def s3_package_key(self) -> str:
        return 'package-artifacts/' + self.username + '/' + self.package + '/' + str(self.version) + '/elm-package.json'

    def s3_source_key(self) -> str:
        return 'package-artifacts/' + self.username + '/' + self.package + '/' + str(self.version) + '/source.json'

    def s3_artifacts_key(self, version: Version) -> str:
        return 'package-artifacts/' + self.username + '/' + self.package + '/' + str(self.version) + '/artifacts/' + str(version) + '.json'

    def set_elm_constraint(self, constraint: Optional[Constraint]) -> None:
        self.elm_constraint = constraint

    def to_json(self) -> object:
        return {
            'username': self.username,
            'package': self.package,
            'version': self.version.to_json(),
            'elmVersion': self.elm_constraint.to_json() if self.elm_constraint is not None else None
        }

    def to_package(self) -> Package:
        return Package(PackageName(self.username, self.package), self.version)

    @staticmethod
    def from_json(data: Dict[str, Any]) -> Optional['PackageInfo']:
        version = Version.from_string(data['version'])
        if version is None:
            return None

        package = PackageInfo(data['username'], data['package'], version)
        if 'minElmVersion' in data and 'maxElmVersion' in data:
            package.set_elm_constraint(
                Constraint.from_ints(data['minElmVersion'], data[
                    'maxElmVersion']))
        elif 'elmVersion' in data:
            package.set_elm_constraint(
                Constraint.from_json(data['elmVersion']))
        return package
