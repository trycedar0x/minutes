"""Dependency-free worker contract tests: load pure functions without ML imports."""
import ast
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

source = ast.parse((Path(__file__).resolve().parents[1] / "transcribe.py").read_text())
names = {"_validate_meeting_notes", "_meeting_chunks", "generate_meeting_notes", "_organize_meeting_notes"}
namespace = {}
exec(compile(ast.Module(body=[node for node in source.body
                             if isinstance(node, ast.FunctionDef) and node.name in names],
                        type_ignores=[]), "transcribe.py", "exec"), namespace)
validate = namespace["_validate_meeting_notes"]
chunks = namespace["_meeting_chunks"]
generate_notes = namespace["generate_meeting_notes"]


class Tokenizer:
    def encode(self, text):
        return list(text)

    def apply_chat_template(self, messages, **kwargs):
        return messages


def payload(ref=1):
    return {"summary": [{"text": "讨论发布", "sources": [ref]}],
            "decisions": [], "actions": [{"text": "测试", "sources": [ref], "owner": None, "due": None}],
            "questions": []}


class MeetingNotesTests(unittest.TestCase):
    def test_valid_json_and_fences(self):
        data = payload()
        self.assertEqual(validate("```json\n" + json.dumps(data) + "\n```", {1}), data)

    def test_reject_invalid_references(self):
        for refs in ([], [0], [-1], [2], [True], ["1"]):
            data = payload()
            data["summary"][0]["sources"] = refs
            with self.assertRaises(ValueError):
                validate(json.dumps(data), {1})

    def test_reject_malformed_sections(self):
        for data in ({}, [], {**payload(), "summary": []}, {**payload(), "questions": "?"}):
            with self.assertRaises(ValueError):
                validate(json.dumps(data), {1})
        data = payload()
        data["actions"][0]["owner"] = 42
        with self.assertRaises(ValueError):
            validate(json.dumps(data), {1})

    def test_all_lines_and_long_turns_covered(self):
        lines = [{"timestamp": "00:01", "speaker": "A", "text": "你好" * 7000},
                 {"timestamp": "01:00", "speaker": "B", "text": "last"}]
        parts = list(chunks(lines, Tokenizer()))
        self.assertGreater(len(parts), 1)
        flattened = [json.loads(text) for part in parts for _, text in part]
        for index, line in enumerate(lines, 1):
            self.assertEqual("".join(p["text"] for p in flattened if p["id"] == index), line["text"])
        self.assertTrue(all(sum(len(text) + 8 for _, text in part) <= 5000 for part in parts))

    def test_generation_covers_every_chunk_with_valid_sources(self):
        lm = types.ModuleType("mlx_lm")
        lm.load = lambda _: (object(), Tokenizer())
        calls = []

        def generate(model, tokenizer, prompt, **kwargs):
            source_text = prompt[1]["content"].split("TRANSCRIPT DATA:\n", 1)[1].split("\nEND TRANSCRIPT.", 1)[0]
            sources = [json.loads(line) for line in source_text.splitlines()]
            calls.append(sources)
            return json.dumps(payload(sources[-1]["id"]))

        lm.generate = generate
        sampling = types.ModuleType("mlx_lm.sample_utils")
        sampling.make_sampler = lambda **kwargs: None
        lines = [{"timestamp": str(i), "speaker": "A", "text": "a" * 1000} for i in range(20)]
        with patch.dict(sys.modules, {"mlx_lm": lm, "mlx_lm.sample_utils": sampling}):
            notes = generate_notes(lines, "local-test-model")
        self.assertEqual({s["id"] for call in calls for s in call}, set(range(1, 21)))
        self.assertEqual(len(notes["summary"]), len(calls))
        validate(json.dumps(notes), set(range(1, 21)))

    def test_organization_preserves_action_evidence(self):
        organize = namespace["_organize_meeting_notes"]
        data = payload()
        result = organize(data, None, Tokenizer(), lambda *a, **kw: json.dumps(data), lambda **kw: None)
        self.assertEqual(result, data)
        missing = {**data, "actions": []}
        with self.assertRaisesRegex(ValueError, "dropped action-item evidence"):
            organize(data, None, Tokenizer(), lambda *a, **kw: json.dumps(missing), lambda **kw: None)

    def test_organization_does_not_invent_reference_ids(self):
        organize = namespace["_organize_meeting_notes"]
        with self.assertRaisesRegex(ValueError, "source IDs"):
            organize(payload(), None, Tokenizer(), lambda *a, **kw: json.dumps(payload(2)), lambda **kw: None)

    def test_organization_fails_explicitly_on_context_overflow(self):
        data = payload()
        data["summary"][0]["text"] = "x" * 12001
        with self.assertRaisesRegex(ValueError, "context budget"):
            namespace["_organize_meeting_notes"](data, None, Tokenizer(), None, None)

    def test_generation_retries_then_fails_without_partial_result(self):
        lm = types.ModuleType("mlx_lm")
        lm.load = lambda _: (object(), Tokenizer())
        calls = []
        lm.generate = lambda *args, **kwargs: calls.append(1) or "not json"
        sampling = types.ModuleType("mlx_lm.sample_utils")
        sampling.make_sampler = lambda **kwargs: None
        with patch.dict(sys.modules, {"mlx_lm": lm, "mlx_lm.sample_utils": sampling}):
            with self.assertRaisesRegex(ValueError, "section 1"):
                generate_notes([{"timestamp": "0", "speaker": "A", "text": "hi"}], "test")
        self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
