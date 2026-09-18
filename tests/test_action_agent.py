import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("action_agent", ROOT / "eval" / "action_agent.py")
action_agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(action_agent)


class Tokenizer:
    def encode(self, text): return list(text)


class ActionAgentTests(unittest.TestCase):
    def setUp(self):
        self.lines = [
            {"timestamp": "0", "speaker": "A", "text": "下一步我可以写方案"},
            {"timestamp": "1", "speaker": "B", "text": "产品可以自动提醒用户"},
        ]

    def candidate(self, **changes):
        item = {"task": "写方案", "status": "proposed", "owner": None,
                "source_ids": [1], "quote": "我可以写方案"}
        item.update(changes)
        return item

    def test_accepts_exact_evidence(self):
        raw = json.dumps({"actions": [self.candidate()]}, ensure_ascii=False)
        self.assertEqual(len(action_agent.validate_candidates(raw, {1}, self.lines)), 1)

    def test_drops_paraphrased_or_cross_window_evidence(self):
        raw = json.dumps({"actions": [self.candidate(quote="写一个方案"),
                                      self.candidate(source_ids=[2], quote="产品可以自动提醒用户")]},
                         ensure_ascii=False)
        self.assertEqual(action_agent.validate_candidates(raw, {1}, self.lines), [])

    def test_rejects_malformed_candidate_schema(self):
        raw = json.dumps({"actions": [{"task": "x"}]})
        with self.assertRaises(ValueError):
            action_agent.validate_candidates(raw, {1}, self.lines)

    def test_chunking_preserves_all_ids(self):
        chunks = action_agent.chunk_lines(self.lines, Tokenizer(), budget=80)
        self.assertEqual([identifier for chunk in chunks for identifier, _ in chunk], [1, 2])


if __name__ == "__main__": unittest.main()
