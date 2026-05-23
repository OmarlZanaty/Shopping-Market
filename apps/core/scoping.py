"""
Store-scoping mixins for DRF views.

Use case: an Admin endpoint that lists products. A Super Admin should see all
products across all stores. A Store Admin should only see products from their
own store. A Branch Manager should see products from their store AND filter
by branch.

Mix into the view AFTER `permission_classes`:

    class AdminProductListView(ScopedAdminListMixin, generics.ListAPIView):
        scope_field = 'store_id'      # field on the model
        branch_field = 'branch_id'    # optional, for branch-manager scoping
        queryset = Product.objects.all()
"""


class ScopedAdminListMixin:
    """Apply store_id (and optionally branch_id) filter based on request.user."""

    scope_field = 'store_id'
    branch_field = None  # set to e.g. 'branch_id' if the model has it

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        store_id = getattr(user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(**{self.scope_field: store_id})
        if self.branch_field and getattr(user, 'role', None) == 'branch_manager':
            branch_id = getattr(user, 'branch_id', None)
            if branch_id:
                qs = qs.filter(**{self.branch_field: branch_id})
        return qs


def scope_to_user(queryset, user, scope_field='store_id', branch_field=None):
    """Function form for views that override get_queryset themselves."""
    store_id = getattr(user, 'store_id', None)
    if store_id is not None:
        queryset = queryset.filter(**{scope_field: store_id})
    if branch_field and getattr(user, 'role', None) == 'branch_manager':
        branch_id = getattr(user, 'branch_id', None)
        if branch_id:
            queryset = queryset.filter(**{branch_field: branch_id})
    return queryset


def enforce_store_id_on_create(serializer, user):
    """
    Save hook: when a non-super-admin creates an object, force store_id to
    their own. Super Admin must pass store_id explicitly.
    """
    store_id = getattr(user, 'store_id', None)
    if store_id is not None:
        return serializer.save(store_id=store_id)
    return serializer.save()
