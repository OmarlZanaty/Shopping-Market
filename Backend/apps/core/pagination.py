"""
DRF pagination class that emits the spec envelope:
    { success, data: [...], pagination: {page, limit, total, totalPages}, message, errors }

For backward compatibility with the existing Flutter client (which reads
res.data['results']) we ALSO emit `results`, `count`, `next`, `previous` —
the legacy DRF keys. New clients ignore them; old clients see only what they
expect.
"""
from collections import OrderedDict
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response


class StandardPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = 'limit'
    max_page_size = 100

    def get_paginated_response(self, data):
        total = self.page.paginator.count
        limit = self.get_page_size(self.request) or self.page_size
        page = self.page.number
        total_pages = self.page.paginator.num_pages
        next_link = self.get_next_link()
        prev_link = self.get_previous_link()
        return Response(OrderedDict([
            # New envelope
            ('success', True),
            ('data', data),
            ('pagination', OrderedDict([
                ('page', page),
                ('limit', limit),
                ('total', total),
                ('totalPages', total_pages),
            ])),
            ('message', ''),
            ('errors', []),
            # Legacy DRF keys (back-compat with older Flutter parsers)
            ('results', data),
            ('count', total),
            ('next', next_link),
            ('previous', prev_link),
        ]))
