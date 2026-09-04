import unittest

from sync_gym_directory import merge_records


class MergeRecordsTest(unittest.TestCase):
    def test_updates_stable_source_identity_and_preserves_review_fields(self) -> None:
        existing = [{
            "name": "香蕉攀岩 旧名称",
            "city": "成都",
            "address": "旧地址",
            "brandName": "香蕉攀岩",
            "canonicalVenueId": "directory:banana:成都:目标店",
            "source": {"name": "公开源", "external_id": "same-id", "url": "https://old.example"},
        }]
        refreshed = [{
            "name": "香蕉攀岩 新名称",
            "city": "成都",
            "address": "新地址",
            "source": {"name": "公开源", "external_id": "same-id", "url": "https://new.example"},
        }]

        added, updated = merge_records(existing, refreshed)

        self.assertEqual((added, updated, len(existing)), (0, 1, 1))
        self.assertEqual(existing[0]["name"], "香蕉攀岩 新名称")
        self.assertEqual(existing[0]["address"], "新地址")
        self.assertEqual(existing[0]["brandName"], "香蕉攀岩")
        self.assertEqual(existing[0]["canonicalVenueId"], "directory:banana:成都:目标店")

    def test_keeps_distinct_external_ids_when_exact_identity_differs(self) -> None:
        existing = [{
            "name": "A 店",
            "city": "深圳",
            "address": "地址 1",
            "source": {"name": "公开源", "external_id": "one", "url": "https://example.com/one"},
        }]
        incoming = [{
            "name": "B 店",
            "city": "深圳",
            "address": "地址 2",
            "source": {"name": "公开源", "external_id": "two", "url": "https://example.com/two"},
        }]

        added, updated = merge_records(existing, incoming)

        self.assertEqual((added, updated, len(existing)), (1, 0, 2))


if __name__ == "__main__":
    unittest.main()
