from typing import Any, Optional

from .package_name import PackageName
from .version import Version


class Package(object):
    def __init__(self, name: PackageName, version: Version) -> None:
        self.name = name
        self.version = version

    def __repr__(self) -> str:
        return '<Package ' + self.name.user + '/' + \
            self.name.project + '@' + str(self.version) + '>'

    def to_json(self) -> object:
        return [self.name.to_json(), self.version.to_json()]

    @staticmethod
    def from_json(data: Any) -> Optional['Package']:
        name = PackageName.from_json(data[0])
        if name is None:
            return None

        version = Version.from_json(data[1])
        if version is None:
            return None

        return Package(name, version)
