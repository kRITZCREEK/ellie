from typing import Any, Optional, SupportsInt


class Version(SupportsInt):
    def __init__(self, major: int, minor: int, patch: int) -> None:
        self.major = major
        self.minor = minor
        self.patch = patch

    def __hash__(self) -> int:
        return hash(self.__int__())

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        return self.__int__() < int(other)

    def __le__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        return self.__int__() <= int(other)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        return self.__int__() == int(other)

    def __int__(self) -> int:
        return (self.major << 20) | (self.minor << 10) | self.patch

    def __str__(self) -> str:
        return str(self.major) + '.' + str(self.minor) + '.' + str(self.patch)

    def __repr__(self) -> str:
        return '<Version ' + self.__str__() + '>'

    def next_major(self) -> 'Version':
        return Version(self.major + 1, 0, 0)

    def next_patch(self) -> 'Version':
        return Version(self.major, self.minor, self.patch + 1)

    def to_json(self) -> object:
        return self.__str__()

    @staticmethod
    def from_int(value: int) -> 'Version':
        return Version(value >> 20, (value >> 10) & 0b1111111111,
                       value & 0b1111111111)

    @staticmethod
    def from_string(input: str) -> Optional['Version']:
        try:
            split = input.split('.')
            as_ints = list(map(int, split))
            all_worked = all(isinstance(x, int) for x in as_ints)
            if all_worked and len(as_ints) == 3:
                return Version(as_ints[0], as_ints[1], as_ints[2])
            return None
        except:
            return None

    @staticmethod
    def from_json(data: Any) -> Optional['Version']:
        return Version.from_string(data)
