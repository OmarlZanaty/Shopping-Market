"""
Standard response envelope per spec:
    { success: bool, data: {}, message: string, errors: [] }
And the list variant:
    { success: bool, data: [...], pagination: {page, limit, total, totalPages}, message: string }
"""
from rest_framework.response import Response
from rest_framework import status as drf_status


def ok(data=None, message='', status_code=drf_status.HTTP_200_OK):
    return Response(
        {'success': True, 'data': data if data is not None else {}, 'message': message, 'errors': []},
        status=status_code,
    )


def created(data=None, message='Created'):
    return ok(data, message=message, status_code=drf_status.HTTP_201_CREATED)


def fail(message='Error', errors=None, data=None, status_code=drf_status.HTTP_400_BAD_REQUEST):
    payload = {'success': False, 'data': data if data is not None else {}, 'message': message, 'errors': errors or []}
    return Response(payload, status=status_code)


def paginated(data_list, page, limit, total, message=''):
    total_pages = max(1, (int(total) + int(limit) - 1) // int(limit))
    return Response({
        'success': True,
        'data': data_list,
        'pagination': {
            'page': int(page),
            'limit': int(limit),
            'total': int(total),
            'totalPages': total_pages,
        },
        'message': message,
        'errors': [],
    })
