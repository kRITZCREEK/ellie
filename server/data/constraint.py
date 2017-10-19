from typing import Optional

from .version import Version


class Constraint(object):
    def __init__(self,
                 lower: Version,
                 lower_op: str,
                 upper_op: str,
                 upper: Version) -> None:
        self.lower = lower
        self.lower_op = lower_op
        self.upper_op = upper_op
        self.upper = upper

    def __str__(self) -> str:
        return str(self.lower
                   ) + ' ' + self.lower_op + ' v ' + self.upper_op + ' ' + str(
                       self.upper)

    def __repr__(self) -> str:
        return '<Constraint ' + self.__str__() + '>'

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Constraint):
            return False
        return self.min_version() == other.min_version() and self.max_version(
        ) == other.max_version()

    def is_satisfied(self, version: Version) -> bool:
        return self.min_version() <= version < self.max_version()

    def min_version(self) -> Version:
        if self.lower_op == '<':
            return self.lower.next_patch()
        return self.lower

    def max_version(self) -> Version:
        if self.upper_op == '<':
            return self.upper
        return self.upper.next_patch()

    @staticmethod
    def from_ints(left: int, right: int) -> 'Constraint':
        return Constraint(
            Version.from_int(left), '<=', '<', Version.from_int(right))

    @staticmethod
    def from_string(input: str) -> Optional['Constraint']:
        split = input.split('v')
        trimmed = list(map(lambda x: x.strip(' '), split))
        left_stuff = trimmed[0]
        right_stuff = trimmed[1]

        if left_stuff is None or right_stuff is None:
            return None

        left_op = '<=' if left_stuff.endswith('<=') else '<'
        left_version = Version.from_string(left_stuff.rstrip(left_op + ' '))
        right_op = '<=' if right_stuff.startswith('<=') else '<'
        right_version = Version.from_string(right_stuff.lstrip(right_op + ' '))

        if left_version is None or right_version is None:
            return None

        return Constraint(left_version, left_op, right_op, right_version)

    @staticmethod
    def from_json(input: object) -> Optional['Constraint']:
        if not isinstance(input, str):
            return None
        return Constraint.from_string(input)

    def to_json(self) -> object:
        return self.__str__()
