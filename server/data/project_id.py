import os
import time
from typing import Any, Optional, SupportsInt


def _timestamp() -> int:
    return int(time.time() * 1000)


_ALPHABET = '23456789bcdfghjkmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ'
_BASE_LENGTH = len(_ALPHABET)
_SEQ_ID = 0
_RELEASE_ID = int(os.environ.get('HEROKU_RELEASE_VERSION', '0').lstrip('v'))
_OUR_EPOCH = _timestamp()


class ProjectId(SupportsInt):
    def __init__(self, number_value: int, version: int) -> None:
        self._number_value = number_value
        self.is_old = version != 1

    def __hash__(self) -> int:
        return hash(self.__int__())

    def __eq__(self, other: object) -> bool:
        if isinstance(other, ProjectId):
            return self.__int__() == other.__int__()
        else:
            return False

    def __ne__(self, other: object) -> bool:
        return (not self.__eq__(other))

    def __str__(self) -> str:
        return self._to_string_v1(self._number_value)

    def __repr__(self) -> str:
        return '<ProjectId ' + self.__str__() + '>'

    def __int__(self) -> int:
        return self._number_value

    def _to_string_v1(self, number_value: int) -> str:
        tracker = int(number_value)
        output = ''
        while tracker > 0:
            index = tracker % _BASE_LENGTH
            output = _ALPHABET[index] + output
            tracker = tracker // _BASE_LENGTH
        return output + 'a1'

    def _to_string_v0(self, number_value: int) -> str:
        tracker = int(number_value)
        output = ''
        while tracker > 0:
            index = (tracker % _BASE_LENGTH) - 1
            if index >= 0:
                output = _ALPHABET[index] + output
            tracker = tracker // _BASE_LENGTH
        return output

    def to_json(self) -> object:
        return self.__str__()

    @staticmethod
    def generate() -> 'ProjectId':
        global _SEQ_ID
        my_seq_id = (_SEQ_ID + 1) % 1024
        _SEQ_ID += 1
        now_millis = _timestamp()
        result = (now_millis - _OUR_EPOCH) << 23
        result |= _RELEASE_ID << 10
        result |= my_seq_id
        return ProjectId(result, 1)

    @staticmethod
    def _from_string_v0(input: str) -> 'ProjectId':
        tracker = 0
        length = len(input)
        for i in range(length):
            index = _ALPHABET.index(input[i]) + 1
            tracker = tracker * _BASE_LENGTH + index
        return ProjectId(tracker, 0)

    @staticmethod
    def _from_string_v1(input: str) -> 'ProjectId':
        tracker = 0
        without_id = input.replace('a1', '')
        length = len(without_id)
        for i in range(length):
            index = _ALPHABET.index(without_id[i])
            tracker = tracker * _BASE_LENGTH + index
        return ProjectId(tracker, 1)

    @staticmethod
    def _determine_version(input: str) -> int:
        if input.endswith('a1'):
            return 1
        return 0

    @staticmethod
    def from_string(input: str) -> Optional['ProjectId']:
        if input.isdigit():
            return ProjectId(int(input), 1)

        version = ProjectId._determine_version(input)
        if version == 1:
            return ProjectId._from_string_v1(input)
        elif version == 0:
            return ProjectId._from_string_v0(input)
        else:
            return None

    @staticmethod
    def from_json(input: Any) -> Optional['ProjectId']:
        if isinstance(input, str):
            return ProjectId.from_string(input)
        return None
