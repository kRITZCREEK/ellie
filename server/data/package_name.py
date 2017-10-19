from typing import Any, Optional


class PackageName(object):
    def __init__(self, user: str, project: str) -> None:
        self.user = user
        self.project = project

    def __str__(self) -> str:
        return self.user + '/' + self.project

    def __repr__(self) -> str:
        return '<PackageName ' + self.__str__() + '>'

    def __hash__(self) -> int:
        return hash(self.__str__())

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, PackageName):
            return NotImplemented
        return self.user == other.user and self.project == other.project

    def to_json(self) -> object:
        return self.__str__()

    @staticmethod
    def from_json(data: Any) -> Optional['PackageName']:
        split = data.split('/')
        if len(split) != 2:
            return None

        return PackageName(split[0], split[1])
