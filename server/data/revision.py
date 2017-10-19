from typing import Any, Iterator, List, NamedTuple, Optional, TypeVar

from .package import Package
from .revision_id import RevisionId
from .version import Version

T = TypeVar('T')


def _cat_optionals(data: Iterator[Optional[T]]) -> List[T]:
    out = []
    for x in data:
        if x is not None:
            out.append(x)
    return out


class _RevisionBase(NamedTuple):
    title: str
    description: str
    elm_code: str
    html_code: str
    packages: List[Package]
    id: Optional[RevisionId]
    owned: bool
    snapshot: Any
    elm_version: Version
    accepted_terms: Optional[int]


class Revision(_RevisionBase):
    def to_json(self) -> Any:
        return {
            'title': self.title,
            'description': self.description,
            'elmCode': self.elm_code,
            'htmlCode': self.html_code,
            'packages': [p.to_json() for p in self.packages],
            'id': self.id.to_json() if self.id is not None else None,
            'owned': self.owned,
            'snapshot': self.snapshot,
            'elmVersion': self.elm_version.to_json(),
            'acceptedTerms': self.accepted_terms
        }

    @staticmethod
    def from_json(data: Any) -> Optional['Revision']:
        elm_version = Version(0, 18, 0)
        if 'elmVersion' in data:
            parsed = Version.from_json(data['elmVersion'])
            if parsed is not None:
                elm_version = parsed

        return Revision(
            title=data['title'],
            description=data['description'],
            elm_code=data['elmCode'],
            html_code=data['htmlCode'],
            packages=_cat_optionals(
                Package.from_json(x) for x in data['packages']),
            id=RevisionId.from_json(data['id']),
            owned=data['owned'] if 'owned' in data else False,
            snapshot=data['snapshot'],
            elm_version=elm_version,
            accepted_terms=data.get('acceptedTerms'))
