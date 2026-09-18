import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import transcribe


class _Turn:
    def __init__(self, start, end):
        self.start = start
        self.end = end


class _Annotation:
    def __init__(self, turns):
        self._turns = turns

    def itertracks(self, yield_label=False):
        for start, end, speaker in self._turns:
            yield _Turn(start, end), None, speaker


class _Diarization:
    def __init__(self, turns):
        self.speaker_diarization = _Annotation(turns)


class QwenAlignedMergeTests(unittest.TestCase):
    def test_preserves_real_speaker_boundary(self):
        result = {"text": "你好。yes please!", "segments": [
            {"text": "你", "start": 0.80, "end": 0.92},
            {"text": "好", "start": 0.92, "end": 1.00},
            {"text": "yes", "start": 1.00, "end": 1.18},
            {"text": "please", "start": 1.18, "end": 1.50},
        ]}
        diarization = _Diarization([(0.0, 1.0, "SPEAKER_00"), (1.0, 2.0, "SPEAKER_01")])

        lines = transcribe.merge_aligned_transcript_and_diarization(result, diarization)

        self.assertEqual([line["speaker"] for line in lines], ["SPEAKER_00", "SPEAKER_01"])
        self.assertEqual([line["text"] for line in lines], ["你好。", "yes please!"])
        self.assertEqual(lines[0]["end"], 1.0)
        self.assertEqual(lines[1]["start"], 1.0)

    def test_smooths_only_isolated_tiny_flip(self):
        units = [
            {"text": "a", "start": 0.0, "end": 0.2, "speaker": "A", "speaker_confidence": 1.0},
            {"text": "b", "start": 0.2, "end": 0.28, "speaker": "B", "speaker_confidence": 1.0},
            {"text": "c", "start": 0.28, "end": 0.5, "speaker": "A", "speaker_confidence": 1.0},
        ]
        smoothed = transcribe._smooth_aligned_speakers(units)
        self.assertEqual([unit["speaker"] for unit in smoothed], ["A", "A", "A"])
        self.assertEqual([unit["text"] for unit in smoothed], ["a", "b", "c"])

    def test_keeps_sustained_middle_turn(self):
        units = [
            {"text": "a", "start": 0.0, "end": 0.2, "speaker": "A", "speaker_confidence": 1.0},
            {"text": "b", "start": 0.2, "end": 0.4, "speaker": "B", "speaker_confidence": 1.0},
            {"text": "c", "start": 0.4, "end": 0.6, "speaker": "B", "speaker_confidence": 1.0},
            {"text": "d", "start": 0.6, "end": 0.8, "speaker": "A", "speaker_confidence": 1.0},
        ]
        smoothed = transcribe._smooth_aligned_speakers(units)
        self.assertEqual([unit["speaker"] for unit in smoothed], ["A", "B", "B", "A"])

    def test_zero_duration_unit_uses_local_speaker_evidence(self):
        result = {"segments": [
            {"text": "前", "start": 0.8, "end": 0.9},
            {"text": "界", "start": 1.1, "end": 1.1},
            {"text": "后", "start": 1.1, "end": 1.2},
        ]}
        diarization = _Diarization([(0.0, 1.0, "A"), (1.0, 2.0, "B")])
        lines = transcribe.merge_aligned_transcript_and_diarization(result, diarization)
        self.assertEqual([(line["speaker"], line["text"]) for line in lines], [("A", "前"), ("B", "界后")])

    def test_rejects_non_monotonic_alignment(self):
        result = {"segments": [
            {"text": "a", "start": 1.0, "end": 1.1},
            {"text": "b", "start": 0.9, "end": 1.2},
        ]}
        with self.assertRaisesRegex(ValueError, "not monotonic"):
            transcribe.merge_aligned_transcript_and_diarization(result, _Diarization([]))

    def test_rejects_decreasing_end_timestamps(self):
        result = {"text": "ab", "segments": [
            {"text": "a", "start": 0.0, "end": 0.8},
            {"text": "b", "start": 0.5, "end": 0.7},
        ]}
        with self.assertRaisesRegex(ValueError, "not monotonic"):
            transcribe.merge_aligned_transcript_and_diarization(result, _Diarization([]))

    def test_preserves_exact_multilingual_raw_text_across_boundaries(self):
        raw_text = "你好，  hello hello!\nनमस्ते？ repeated repeated\t끝."
        tokens = ["你", "好", "hello", "hello", "नमस्ते", "repeated", "repeated", "끝"]
        segments = [
            {"text": token, "start": index * 0.5, "end": index * 0.5 + 0.4}
            for index, token in enumerate(tokens)
        ]
        result = {"text": raw_text, "segments": segments}
        diarization = _Diarization([
            (0.0, 1.0, "A"), (1.0, 2.0, "B"),
            (2.0, 3.0, "A"), (3.0, 4.5, "B"),
        ])

        restored = transcribe._validated_qwen_units(result)
        lines = transcribe.merge_aligned_transcript_and_diarization(result, diarization)

        self.assertEqual("".join(unit["text"] for unit in restored), raw_text)
        self.assertEqual("".join(line["text"] for line in lines), raw_text)
        self.assertGreater(len(lines), 1)

    def test_rejects_leading_interstitial_and_trailing_lexical_gaps(self):
        cases = [
            ("omitted kept", ["kept"]),
            ("kept 漏掉 next", ["kept", "next"]),
            ("kept omitted", ["kept"]),
        ]
        for raw_text, tokens in cases:
            with self.subTest(raw_text=raw_text):
                result = {
                    "text": raw_text,
                    "segments": [
                        {"text": token, "start": index * 0.5, "end": index * 0.5 + 0.4}
                        for index, token in enumerate(tokens)
                    ],
                }
                with self.assertRaisesRegex(ValueError, "omitted lexical"):
                    transcribe._validated_qwen_units(result)

    def test_language_is_part_of_qwen_cache_identity(self):
        base = dict(model="whisper", qwen_asr_model="asr", qwen_aligner_model="aligner")
        audio = Path("meeting.m4a")
        _, auto = transcribe._transcription_cache_paths(audio, SimpleNamespace(**base, language=""))
        _, zh = transcribe._transcription_cache_paths(audio, SimpleNamespace(**base, language="zh"))
        _, chinese = transcribe._transcription_cache_paths(audio, SimpleNamespace(**base, language="Chinese"))
        self.assertNotEqual(auto, zh)
        self.assertEqual(zh, chinese)
        self.assertIn(".auto.qwen3-asr.json", auto.name)
        self.assertIn(".chinese.qwen3-asr.json", zh.name)

    def test_qwen_commit_keeps_matching_transcript_and_exact_evidence(self):
        metadata = transcribe._qwen_cache_metadata("asr", "aligner", "zh")
        result = {
            "backend": "qwen3-asr", "cache_metadata": metadata,
            "language": "Chinese", "text": "你 好！\nagain again",
            "segments": [
                {"text": "你", "start": 0.0, "end": 0.2},
                {"text": "好", "start": 0.2, "end": 0.4},
                {"text": "again", "start": 0.4, "end": 0.8},
                {"text": "again", "start": 0.8, "end": 1.2},
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "out.txt"
            evidence_path = transcribe._commit_transcript_output("rendered qwen transcript", str(output), result)
            evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
            self.assertEqual(output.read_text(encoding="utf-8"), "rendered qwen transcript\n")
            self.assertEqual(evidence["raw_text"], result["text"])
            self.assertEqual(evidence["aligned_units"], result["segments"])


class QwenFallbackTests(unittest.TestCase):
    @staticmethod
    def _whisper_result():
        return {"language": "en", "segments": [{"words": [
            {"word": "fallback", "start": 0.0, "end": 0.5},
        ]}]}

    def test_malformed_qwen_cache_falls_back_to_whisper(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "meeting.wav"
            output = Path(directory) / "out.txt"
            audio.write_bytes(b"audio")
            argv = ["transcribe.py", str(audio), "--hf-token", "token", "--backend", "qwen3-asr", "--output", str(output)]
            with patch.object(sys, "argv", argv):
                args = transcribe.parse_args()
            _, qwen_cache = transcribe._transcription_cache_paths(audio.resolve(), args)
            qwen_cache.write_text("{broken", encoding="utf-8")

            with patch.object(sys, "argv", argv), \
                    patch.object(transcribe, "transcribe_with_qwen") as qwen, \
                    patch.object(transcribe, "transcribe_with_mlx", return_value=self._whisper_result()) as whisper, \
                    patch.object(transcribe, "diarize", return_value=_Diarization([(0.0, 1.0, "A")])):
                transcribe.main()

            qwen.assert_not_called()
            whisper.assert_called_once()
            self.assertIn("fallback", output.read_text(encoding="utf-8"))
            self.assertFalse(qwen_cache.exists())

    def test_stale_qwen_cache_metadata_falls_back_to_whisper(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "meeting.wav"
            output = Path(directory) / "out.txt"
            audio.write_bytes(b"audio")
            argv = ["transcribe.py", str(audio), "--hf-token", "token", "--backend", "qwen3-asr", "--output", str(output)]
            with patch.object(sys, "argv", argv):
                args = transcribe.parse_args()
            _, qwen_cache = transcribe._transcription_cache_paths(audio.resolve(), args)
            stale = {
                "backend": "qwen3-asr",
                "cache_metadata": transcribe._qwen_cache_metadata(
                    args.qwen_asr_model, args.qwen_aligner_model, "zh"
                ),
                "language": "Chinese", "text": "stale",
                "segments": [{"text": "stale", "start": 0.0, "end": 0.5}],
            }
            qwen_cache.write_text(json.dumps(stale), encoding="utf-8")

            with patch.object(sys, "argv", argv), \
                    patch.object(transcribe, "transcribe_with_qwen") as qwen, \
                    patch.object(transcribe, "transcribe_with_mlx", return_value=self._whisper_result()) as whisper, \
                    patch.object(transcribe, "diarize", return_value=_Diarization([(0.0, 1.0, "A")])):
                transcribe.main()

            qwen.assert_not_called()
            whisper.assert_called_once()
            self.assertIn("fallback", output.read_text(encoding="utf-8"))
            self.assertFalse(qwen_cache.exists())

    def test_omitted_qwen_word_triggers_whisper_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "meeting.wav"
            output = Path(directory) / "out.txt"
            audio.write_bytes(b"audio")
            argv = ["transcribe.py", str(audio), "--hf-token", "token", "--backend", "qwen3-asr", "--output", str(output)]
            metadata = transcribe._qwen_cache_metadata(
                "Qwen/Qwen3-ASR-1.7B", "Qwen/Qwen3-ForcedAligner-0.6B", None
            )
            qwen_result = {
                "backend": "qwen3-asr", "cache_metadata": metadata,
                "language": "English", "text": "kept omitted next",
                "segments": [
                    {"text": "kept", "start": 0.0, "end": 0.4},
                    {"text": "next", "start": 0.5, "end": 0.9},
                ],
            }
            with patch.object(sys, "argv", argv), \
                    patch.object(transcribe, "transcribe_with_qwen", return_value=qwen_result), \
                    patch.object(transcribe, "transcribe_with_mlx", return_value=self._whisper_result()) as whisper, \
                    patch.object(transcribe, "diarize", return_value=_Diarization([(0.0, 1.0, "A")])):
                transcribe.main()

            whisper.assert_called_once()
            self.assertIn("fallback", output.read_text(encoding="utf-8"))
            self.assertFalse(transcribe._qwen_evidence_path(str(output)).exists())

    def test_qwen_aggregation_failure_falls_back_to_whisper(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "meeting.wav"
            output = Path(directory) / "out.txt"
            audio.write_bytes(b"audio")
            argv = ["transcribe.py", str(audio), "--hf-token", "token", "--backend", "qwen3-asr", "--output", str(output)]
            metadata = transcribe._qwen_cache_metadata(
                "Qwen/Qwen3-ASR-1.7B", "Qwen/Qwen3-ForcedAligner-0.6B", None
            )
            qwen_result = {
                "backend": "qwen3-asr", "cache_metadata": metadata,
                "language": "English", "text": "qwen",
                "segments": [{"text": "qwen", "start": 0.0, "end": 0.5}],
            }
            with patch.object(sys, "argv", argv), \
                    patch.object(transcribe, "transcribe_with_qwen", return_value=qwen_result), \
                    patch.object(transcribe, "transcribe_with_mlx", return_value=self._whisper_result()) as whisper, \
                    patch.object(transcribe, "merge_aligned_transcript_and_diarization", side_effect=ValueError("bad boundary")), \
                    patch.object(transcribe, "diarize", return_value=_Diarization([(0.0, 1.0, "A")])):
                transcribe.main()

            whisper.assert_called_once()
            self.assertIn("fallback", output.read_text(encoding="utf-8"))
            self.assertFalse(transcribe._qwen_evidence_path(str(output)).exists())

    def test_pre_output_failure_preserves_old_transcript_and_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "meeting.wav"
            output = Path(directory) / "out.txt"
            evidence_path = transcribe._qwen_evidence_path(str(output))
            audio.write_bytes(b"audio")
            output.write_text("old transcript\n", encoding="utf-8")
            evidence_path.write_text('{"raw_text":"old evidence"}', encoding="utf-8")
            argv = [
                "transcribe.py", str(audio), "--hf-token", "token", "--backend", "qwen3-asr",
                "--polish", "--output", str(output),
            ]
            metadata = transcribe._qwen_cache_metadata(
                "Qwen/Qwen3-ASR-1.7B", "Qwen/Qwen3-ForcedAligner-0.6B", None
            )
            qwen_result = {
                "backend": "qwen3-asr", "cache_metadata": metadata,
                "language": "English", "text": "new qwen",
                "segments": [
                    {"text": "new", "start": 0.0, "end": 0.2},
                    {"text": "qwen", "start": 0.2, "end": 0.5},
                ],
            }
            with patch.object(sys, "argv", argv), \
                    patch.object(transcribe, "transcribe_with_qwen", return_value=qwen_result), \
                    patch.object(transcribe, "polish_transcript", side_effect=RuntimeError("polish failed")), \
                    patch.object(transcribe, "diarize", return_value=_Diarization([(0.0, 1.0, "A")])):
                with self.assertRaisesRegex(RuntimeError, "polish failed"):
                    transcribe.main()

            self.assertEqual(output.read_text(encoding="utf-8"), "old transcript\n")
            self.assertEqual(evidence_path.read_text(encoding="utf-8"), '{"raw_text":"old evidence"}')

    def test_qwen_success_then_fallback_removes_stale_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "meeting.wav"
            output = Path(directory) / "out.txt"
            audio.write_bytes(b"audio")
            base_argv = ["transcribe.py", str(audio), "--hf-token", "token", "--backend", "qwen3-asr", "--output", str(output)]
            metadata = transcribe._qwen_cache_metadata(
                "Qwen/Qwen3-ASR-1.7B", "Qwen/Qwen3-ForcedAligner-0.6B", None
            )
            qwen_result = {
                "backend": "qwen3-asr", "cache_metadata": metadata,
                "language": "English", "text": "qwen",
                "segments": [{"text": "qwen", "start": 0.0, "end": 0.5}],
            }
            diarization = _Diarization([(0.0, 1.0, "A")])

            with patch.object(sys, "argv", base_argv), \
                    patch.object(transcribe, "transcribe_with_qwen", return_value=qwen_result), \
                    patch.object(transcribe, "diarize", return_value=diarization):
                transcribe.main()
            evidence_path = transcribe._qwen_evidence_path(str(output))
            self.assertTrue(evidence_path.exists())
            self.assertIn("qwen", output.read_text(encoding="utf-8"))
            self.assertEqual(json.loads(evidence_path.read_text(encoding="utf-8"))["raw_text"], "qwen")

            with patch.object(sys, "argv", base_argv + ["--force"]), \
                    patch.object(transcribe, "transcribe_with_qwen", return_value=qwen_result), \
                    patch.object(transcribe, "transcribe_with_mlx", return_value=self._whisper_result()), \
                    patch.object(transcribe, "merge_aligned_transcript_and_diarization", side_effect=ValueError("bad boundary")), \
                    patch.object(transcribe, "diarize", return_value=diarization):
                transcribe.main()

            self.assertIn("fallback", output.read_text(encoding="utf-8"))
            self.assertFalse(evidence_path.exists())


if __name__ == "__main__":
    unittest.main()
