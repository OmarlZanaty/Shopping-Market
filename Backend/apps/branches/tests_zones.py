# -*- coding: utf-8 -*-
"""
Delivery-zone coverage tests.

    DJANGO_SETTINGS_MODULE=config.settings_test python manage.py test apps.branches
"""
from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from apps.stores.models import Store

from .coverage import OUT_OF_ZONE_AR, branch_covers, covering_branch, is_covered
from .geo import bbox_of, circle_to_polygon, contains_point, haversine_km, validate_geometry
from .models import Branch, DeliveryZone

# A square over central Cairo: lng 31.20–31.30, lat 30.00–30.10
SQUARE = {
    'type': 'Polygon',
    'coordinates': [[
        [31.20, 30.00], [31.30, 30.00], [31.30, 30.10], [31.20, 30.10], [31.20, 30.00],
    ]],
}

INSIDE = (30.05, 31.25)
OUTSIDE = (30.05, 31.40)


class GeometryTests(TestCase):

    def test_contains_point(self):
        self.assertTrue(contains_point(SQUARE, *INSIDE))
        self.assertFalse(contains_point(SQUARE, *OUTSIDE))

    def test_point_on_the_border_counts_as_inside(self):
        """A customer standing on the boundary should be served, not lost to a
        floating-point tie."""
        self.assertTrue(contains_point(SQUARE, 30.05, 31.20))
        self.assertTrue(contains_point(SQUARE, 30.00, 31.25))

    def test_hole_is_excluded(self):
        donut = {
            'type': 'Polygon',
            'coordinates': [
                SQUARE['coordinates'][0],
                [[31.24, 30.04], [31.26, 30.04], [31.26, 30.06], [31.24, 30.06], [31.24, 30.04]],
            ],
        }
        self.assertFalse(contains_point(donut, 30.05, 31.25))   # in the hole
        self.assertTrue(contains_point(donut, 30.02, 31.22))    # in the ring

    def test_multipolygon(self):
        multi = {
            'type': 'MultiPolygon',
            'coordinates': [
                SQUARE['coordinates'],
                [[[31.50, 30.00], [31.60, 30.00], [31.60, 30.10], [31.50, 30.10], [31.50, 30.00]]],
            ],
        }
        self.assertTrue(contains_point(multi, 30.05, 31.25))
        self.assertTrue(contains_point(multi, 30.05, 31.55))
        self.assertFalse(contains_point(multi, 30.05, 31.40))

    def test_bbox(self):
        self.assertEqual(bbox_of(SQUARE), [31.20, 30.00, 31.30, 30.10])

    def test_circle_to_polygon_has_the_requested_radius(self):
        poly = circle_to_polygon(30.05, 31.25, 5)
        ring = poly['coordinates'][0]
        self.assertEqual(ring[0], ring[-1])            # closed
        for lng, lat in ring:
            km = haversine_km(30.05, 31.25, lat, lng)
            self.assertAlmostEqual(km, 5, delta=0.2)

    def test_validate_geometry_rejects_junk(self):
        for bad in [
            None, 'polygon', {'type': 'Point', 'coordinates': [31.2, 30.0]},
            {'type': 'Polygon', 'coordinates': [[[31.2, 30.0]]]},
            {'type': 'Polygon', 'coordinates': [[[500, 30.0], [31.3, 30.0], [31.3, 30.1]]]},
        ]:
            with self.assertRaises(ValueError):
                validate_geometry(bad)

    def test_validate_geometry_rejects_a_bow_tie(self):
        """Crossed edges make containment nonsense — catch it at save time."""
        bow_tie = {'type': 'Polygon', 'coordinates': [[
            [31.20, 30.00], [31.30, 30.10], [31.30, 30.00], [31.20, 30.05], [31.20, 30.00],
        ]]}
        with self.assertRaises(ValueError):
            validate_geometry(bow_tie)

    def test_validate_geometry_rejects_a_zone_with_no_area(self):
        collinear = {'type': 'Polygon', 'coordinates': [[
            [31.20, 30.00], [31.25, 30.05], [31.30, 30.10], [31.20, 30.00],
        ]]}
        with self.assertRaises(ValueError):
            validate_geometry(collinear)

    def test_validate_geometry_accepts_the_shapes_admins_actually_draw(self):
        self.assertIsNotNone(validate_geometry(SQUARE))
        self.assertIsNotNone(validate_geometry(circle_to_polygon(30.05, 31.25, 5)))


class CoverageTests(TestCase):

    def setUp(self):
        self.store = Store.objects.create(name_ar='متجر', name_en='Store', type='supermarket')
        self.branch = Branch.objects.create(
            store=self.store, name='Main', name_ar='الفرع الرئيسي', name_en='Main',
            address='Cairo', latitude=30.05, longitude=31.25, phone='0100',
            delivery_radius_km=3,
        )

    def test_falls_back_to_radius_when_no_zones_exist(self):
        """Deploying this feature must change nothing until someone draws."""
        self.assertTrue(branch_covers(self.branch, 30.06, 31.25))    # ~1km
        self.assertFalse(branch_covers(self.branch, 30.20, 31.25))   # ~17km

    def test_zone_overrides_the_radius(self):
        DeliveryZone.objects.create(branch=self.branch, name_ar='وسط', geometry=SQUARE)
        self.branch.refresh_from_db()

        # Inside the square but 17km away — the radius would have refused this.
        self.assertTrue(branch_covers(self.branch, 30.09, 31.29))
        # 1km away but outside the square — the radius would have allowed it.
        self.assertFalse(branch_covers(self.branch, 30.05, 31.40))

    def test_inactive_zone_is_ignored_and_radius_returns(self):
        zone = DeliveryZone.objects.create(branch=self.branch, name_ar='وسط', geometry=SQUARE)
        zone.is_active = False
        zone.save()
        self.branch.refresh_from_db()
        self.assertTrue(branch_covers(self.branch, 30.06, 31.25))

    def test_bbox_is_maintained_on_save(self):
        zone = DeliveryZone.objects.create(branch=self.branch, name_ar='وسط', geometry=SQUARE)
        self.assertEqual(zone.bbox, [31.20, 30.00, 31.30, 30.10])

    def test_covering_branch_picks_the_nearest_of_several(self):
        far = Branch.objects.create(
            store=self.store, name='Far', name_ar='بعيد', address='Cairo',
            latitude=30.09, longitude=31.29, phone='0101', delivery_radius_km=50,
        )
        DeliveryZone.objects.create(branch=self.branch, name_ar='وسط', geometry=SQUARE)
        DeliveryZone.objects.create(branch=far, name_ar='وسط٢', geometry=SQUARE)

        self.assertEqual(covering_branch(30.01, 31.21).id, self.branch.id)
        self.assertEqual(covering_branch(30.089, 31.289).id, far.id)

    def test_inactive_branch_never_covers(self):
        DeliveryZone.objects.create(branch=self.branch, name_ar='وسط', geometry=SQUARE)
        self.branch.is_active = False
        self.branch.save()
        self.assertFalse(is_covered(*INSIDE))


class CoverageEndpointTests(TestCase):

    def setUp(self):
        self.store = Store.objects.create(name_ar='متجر', name_en='Store', type='supermarket')
        self.branch = Branch.objects.create(
            store=self.store, name='Main', name_ar='الرئيسي', name_en='Main',
            address='Cairo', latitude=30.05, longitude=31.25, phone='0100',
            delivery_radius_km=3,
        )
        DeliveryZone.objects.create(branch=self.branch, name_ar='وسط البلد', geometry=SQUARE)
        self.client = APIClient()

    def test_covered_address(self):
        r = self.client.get('/api/v1/branches/coverage/', {'lat': INSIDE[0], 'lng': INSIDE[1]})
        self.assertEqual(r.status_code, 200)
        data = r.json()['data']
        self.assertTrue(data['covered'])
        self.assertEqual(data['branch']['name_ar'], 'الرئيسي')

    def test_uncovered_address_gets_the_arabic_message(self):
        r = self.client.get('/api/v1/branches/coverage/', {'lat': OUTSIDE[0], 'lng': OUTSIDE[1]})
        data = r.json()['data']
        self.assertFalse(data['covered'])
        self.assertIsNone(data['branch'])
        self.assertEqual(data['message_ar'], OUT_OF_ZONE_AR)
        self.assertIn('عذراً', data['message_ar'])

    def test_missing_coordinates_is_a_400(self):
        self.assertEqual(self.client.get('/api/v1/branches/coverage/').status_code, 400)


class AdminZoneApiTests(TestCase):

    def setUp(self):
        self.store = Store.objects.create(name_ar='متجر', name_en='Store', type='supermarket')
        self.branch = Branch.objects.create(
            store=self.store, name='Main', name_ar='الرئيسي', name_en='Main',
            address='Cairo', latitude=30.05, longitude=31.25, phone='0100',
            delivery_radius_km=4,
        )
        self.admin = get_user_model().objects.create_user(
            phone='+201000000009', full_name='Admin', role='admin',
            is_staff=True, is_superuser=True, is_active=True,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.admin)

    def test_create_zone(self):
        r = self.client.post('/api/v1/branches/admin/zones/', {
            'branch': self.branch.id, 'name_ar': 'وسط', 'geometry': SQUARE,
        }, format='json')
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(DeliveryZone.objects.count(), 1)
        self.assertEqual(DeliveryZone.objects.first().bbox, [31.20, 30.00, 31.30, 30.10])

    def test_bad_geometry_is_rejected_at_save_not_at_checkout(self):
        r = self.client.post('/api/v1/branches/admin/zones/', {
            'branch': self.branch.id, 'name_ar': 'سيء',
            'geometry': {'type': 'Point', 'coordinates': [31.2, 30.0]},
        }, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertEqual(DeliveryZone.objects.count(), 0)

    def test_checkout_rejects_an_out_of_zone_address_in_arabic(self):
        """The gate that did not exist before: the server, not just the app."""
        from apps.orders.services import OrderError, create_customer_order
        from apps.products.models import Product
        from apps.users.models import Address

        DeliveryZone.objects.create(branch=self.branch, name_ar='وسط', geometry=SQUARE)
        product = Product.objects.create(
            store=self.store, barcode='7001', name_ar='منتج', name_en='Item',
            original_price=10, quantity_in_stock=50, is_available=True,
        )
        customer = get_user_model().objects.create_user(
            phone='+201000000010', full_name='Customer', is_active=True,
        )
        payload_items = [{'product_id': str(product.id), 'qty': 1}]

        far = Address.objects.create(
            user=customer, full_address='بعيد', building_number='1', floor_number='1',
            apartment_number='1', latitude=OUTSIDE[0], longitude=OUTSIDE[1],
        )
        with self.assertRaises(OrderError) as ctx:
            create_customer_order(customer, {'address_id': far.id, 'items': payload_items})
        self.assertEqual(str(ctx.exception), OUT_OF_ZONE_AR)

        near = Address.objects.create(
            user=customer, full_address='قريب', building_number='1', floor_number='1',
            apartment_number='1', latitude=INSIDE[0], longitude=INSIDE[1],
        )
        order = create_customer_order(customer, {'address_id': near.id, 'items': payload_items})
        self.assertIsNotNone(order.pk)

    def test_inline_order_without_coordinates_still_goes_through(self):
        """Older app builds send no lat/lng. Blocking them would reject real
        customers over a missing field, not a real out-of-area address."""
        from apps.orders.services import create_customer_order
        from apps.products.models import Product

        DeliveryZone.objects.create(branch=self.branch, name_ar='وسط', geometry=SQUARE)
        product = Product.objects.create(
            store=self.store, barcode='7002', name_ar='منتج', name_en='Item',
            original_price=10, quantity_in_stock=50, is_available=True,
        )
        customer = get_user_model().objects.create_user(
            phone='+201000000011', full_name='Customer2', is_active=True,
        )
        order = create_customer_order(customer, {
            'delivery_address': 'عنوان بدون إحداثيات',
            'items': [{'product_id': str(product.id), 'qty': 1}],
        })
        self.assertIsNotNone(order.pk)

    def test_zone_from_radius_reproduces_the_current_area(self):
        r = self.client.post(f'/api/v1/branches/admin/{self.branch.id}/zone-from-radius/',
                             {}, format='json')
        self.assertEqual(r.status_code, 200, r.content)
        zone = DeliveryZone.objects.get()
        self.assertEqual(zone.source, DeliveryZone.Source.CIRCLE)
        # Same area the branch already served: 3km in is covered, 5km out is not.
        self.assertTrue(zone.contains(30.05 + 0.018, 31.25))
        self.assertFalse(zone.contains(30.05 + 0.060, 31.25))

    def test_zone_from_radius_twice_refreshes_instead_of_duplicating(self):
        url = f'/api/v1/branches/admin/{self.branch.id}/zone-from-radius/'
        self.assertEqual(self.client.post(url, {}, format='json').status_code, 200)
        r = self.client.post(url, {'radius_km': 8}, format='json')
        self.assertEqual(r.status_code, 200, r.content)

        zone = DeliveryZone.objects.get(source=DeliveryZone.Source.CIRCLE)
        self.assertEqual(DeliveryZone.objects.count(), 1)
        self.assertTrue(zone.contains(30.05 + 0.060, 31.25))   # now the 8km area

    def test_zone_from_radius_leaves_drawn_zones_alone(self):
        drawn = DeliveryZone.objects.create(branch=self.branch, name_ar='مرسومة', geometry=SQUARE)
        self.client.post(f'/api/v1/branches/admin/{self.branch.id}/zone-from-radius/',
                         {}, format='json')
        drawn.refresh_from_db()
        self.assertEqual(drawn.geometry, SQUARE)
        self.assertEqual(DeliveryZone.objects.count(), 2)
