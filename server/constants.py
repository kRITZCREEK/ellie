import os

ENV: str = os.environ.get('ENV', 'development')

LATEST_TERMS_VERSION: int = 1

PRODUCTION: bool = ENV == 'production'

COOKIE_SECRET: bytes = os.environ.get(
    'COOKIE_SECRET', 'secret1234').encode('utf-8')

SESSION_LIFETIME: int = 60 * 60 * 24 * 365 * 20

S3_BUCKET: str = os.environ['AWS_S3_BUCKET']

RELEASE_ID: int = int(os.environ.get(
    'HEROKU_RELEASE_VERSION', '0').lstrip('v'))
