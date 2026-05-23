"""
Centralized exception handler that converts every DRF + Django error into the
spec envelope: { success: false, data: {}, message, errors: [] }.

Wire via REST_FRAMEWORK['EXCEPTION_HANDLER'] = 'apps.core.exceptions.exception_handler'
"""
import logging

from rest_framework.views import exception_handler as drf_default_handler
from rest_framework.response import Response
from rest_framework import status as drf_status
from django.core.exceptions import PermissionDenied, ObjectDoesNotExist
from django.http import Http404

logger = logging.getLogger('apps')


def exception_handler(exc, context):
    response = drf_default_handler(exc, context)

    if response is not None:
        data = response.data
        # DRF default: dict of {field: [msg, ...]} or {'detail': msg}
        message = ''
        errors = []
        if isinstance(data, dict):
            message = str(data.get('detail') or data.get('message') or 'Request error')
            for field, msgs in data.items():
                if field in ('detail', 'message'):
                    continue
                if isinstance(msgs, list):
                    errors.extend([{'field': field, 'message': str(m)} for m in msgs])
                else:
                    errors.append({'field': field, 'message': str(msgs)})
        elif isinstance(data, list):
            message = 'Request error'
            errors = [{'field': '_', 'message': str(m)} for m in data]
        return Response(
            {'success': False, 'data': {}, 'message': message, 'errors': errors},
            status=response.status_code,
        )

    # Non-DRF exceptions not handled by drf_default_handler
    if isinstance(exc, Http404) or isinstance(exc, ObjectDoesNotExist):
        return Response(
            {'success': False, 'data': {}, 'message': 'Not found', 'errors': []},
            status=drf_status.HTTP_404_NOT_FOUND,
        )
    if isinstance(exc, PermissionDenied):
        return Response(
            {'success': False, 'data': {}, 'message': 'Permission denied', 'errors': []},
            status=drf_status.HTTP_403_FORBIDDEN,
        )

    # Fall through to a generic 500
    logger.exception('Unhandled exception', extra={'context': context})
    return Response(
        {'success': False, 'data': {}, 'message': 'Internal server error', 'errors': []},
        status=drf_status.HTTP_500_INTERNAL_SERVER_ERROR,
    )
