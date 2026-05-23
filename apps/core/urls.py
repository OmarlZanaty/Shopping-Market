from django.urls import path
from .storage import S3PresignView

urlpatterns = [
    path('uploads/presign/', S3PresignView.as_view(), name='s3-presign'),
]
