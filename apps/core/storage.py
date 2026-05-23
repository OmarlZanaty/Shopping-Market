"""
Presigned S3 upload URL generator. Spec: never proxy images through Node — give
the client a signed URL it can PUT directly to.
"""
import logging
import uuid

from django.conf import settings
from rest_framework import permissions
from rest_framework.views import APIView

from .responses import ok, fail
from .validators import safe_filename, ALLOWED_IMAGE_MIME

logger = logging.getLogger(__name__)


class S3PresignView(APIView):
    """
    POST /api/v1/uploads/presign
    Body: { filename, content_type, folder }
    Returns: { url, fields, key, public_url } (POST policy) — or
             { url, key } for PUT-style presigned URLs.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if not getattr(settings, 'USE_S3', False):
            return fail('S3 is not enabled on this server', status_code=503)

        filename = safe_filename(request.data.get('filename', 'upload.jpg'))
        content_type = request.data.get('content_type', 'image/jpeg')
        folder = (request.data.get('folder') or 'misc').strip('/').replace('..', '')

        if content_type not in ALLOWED_IMAGE_MIME:
            return fail(f'Unsupported content_type. Allowed: {sorted(ALLOWED_IMAGE_MIME)}', status_code=400)

        try:
            import boto3
            from botocore.client import Config
            session = boto3.session.Session()
            client = session.client(
                's3',
                region_name=settings.AWS_S3_REGION_NAME,
                aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
                aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
                config=Config(signature_version='s3v4'),
            )
            key = f'{folder}/{uuid.uuid4().hex}_{filename}'
            url = client.generate_presigned_url(
                ClientMethod='put_object',
                Params={
                    'Bucket': settings.AWS_STORAGE_BUCKET_NAME,
                    'Key': key,
                    'ContentType': content_type,
                    'ACL': 'public-read',
                },
                ExpiresIn=300,
            )
            public_url = f'https://{settings.AWS_S3_CUSTOM_DOMAIN}/{key}'
            return ok({'url': url, 'key': key, 'public_url': public_url, 'expires_in': 300})
        except Exception as e:
            logger.exception('presign error: %s', e)
            return fail('Could not generate presigned URL', status_code=500)
