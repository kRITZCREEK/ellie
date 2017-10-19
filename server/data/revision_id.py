from typing import Any, Optional

from .project_id import ProjectId


class RevisionId(object):
    def __init__(self, project_id: ProjectId, revision_number: int) -> None:
        self.project_id = project_id
        self.revision_number = revision_number

    def to_json(self) -> Any:
        return {
            'projectId': self.project_id.to_json(),
            'revisionNumber': self.revision_number
        }

    @staticmethod
    def from_json(data: Any) -> Optional['RevisionId']:
        project_id = ProjectId.from_json(data['projectId'])
        if project_id is None:
            return None
        return RevisionId(project_id, data['revisionNumber'])
