from abc import abstractmethod
from typing import Any, Dict, List, NamedTuple, NewType, Optional, Union

from hashids import Hashids

from .. import constants

# CONSTANTS


_hashids = Hashids(constants.COOKIE_SECRET)

_incrementer = 0


# CLASSES


class CookieId(NamedTuple):
    value: str


class UserId(object):
    def __init__(self, id: Union[CookieId]) -> None:
        self.id = id

    def to_json(self) -> Any:
        if isinstance(self.id, CookieId):
            return {'tag': 'Cookie', 'value': self.id.value}
        else:
            return None

    @staticmethod
    def from_json(data: Dict[str, Any]) -> Optional['UserId']:
        if 'tag' not in data:
            return None
        if data['tag'] == 'Cookie':
            if 'value' not in data or not isinstance(data['value'], str):
                return None
            return UserId(CookieId(data['tag']))
        else:
            return None

    @staticmethod
    def generate() -> 'UserId':
        global _incrementer
        _incrementer += 1
        value = _hashids.hashid(constants.RELEASE_ID, _incrementer)
        return UserId(CookieId(value))
