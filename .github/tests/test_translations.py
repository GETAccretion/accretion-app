"""Accretion.xcstrings: every translation takes the same arguments as its English string.

The app formats these strings with String(format:), so a translation with a missing, extra or
different format specifier shows wrong text or crashes. Line breaks and link addresses must match too.
"""

import json
import re
import unittest
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[2] / "Feather/Resources/Accretion.xcstrings"
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+0 #]*\d*(?:\.\d+)?((?:ll|l|h|z|q)?[@dDuUxXoOfFeEgGcCsSpaA])|%%")
LINK = re.compile(r"\]\((https?://[^)\s]+)\)")


def arguments(text):
    """The type of each argument by position, or None when two specifiers disagree on one."""
    types, next_index = {}, 0
    for match in SPECIFIER.finditer(text):
        if match.group(0) == "%%":
            continue
        if match.group(1):
            index = int(match.group(1))
        else:
            next_index += 1
            index = next_index
        if types.setdefault(index, match.group(2)) != match.group(2):
            return None
    return types


def problem(english, translation):
    if not translation.strip():
        return "empty"
    if SPECIFIER.sub("", translation).count("%") != SPECIFIER.sub("", english).count("%"):
        return "a percent sign that is not a format specifier"
    if arguments(translation) != arguments(english):
        return "format specifiers differ"
    if translation.count("\n") != english.count("\n"):
        return "line breaks differ"
    if sorted(LINK.findall(translation)) != sorted(LINK.findall(english)):
        return "link addresses differ"
    return None


class Arguments(unittest.TestCase):
    def test_reads_plain_and_positional_specifiers(self):
        self.assertEqual(arguments("%@ of %lld (100%%)"), {1: "@", 2: "lld"})
        self.assertEqual(arguments("%2$lld from %1$@"), {1: "@", 2: "lld"})
        self.assertIsNone(arguments("%1$@ and %1$lld"))

    def test_finds_each_kind_of_problem(self):
        self.assertIsNone(problem("%@ apps", "%@ aplicaciones"))
        self.assertIsNone(problem("%@ of %lld", "%2$lld de %1$@"))
        self.assertEqual(problem("%@ apps", "aplicaciones"), "format specifiers differ")
        self.assertEqual(problem("%@ of %lld", "%lld de %@"), "format specifiers differ")
        self.assertEqual(problem("Now at 100%.", "Ahora al 100."), "a percent sign that is not a format specifier")
        self.assertEqual(problem("One\nTwo", "Uno Dos"), "line breaks differ")
        self.assertEqual(problem("[Open](https://a.example/x)", "[Abrir](https://b.example/x)"), "link addresses differ")
        self.assertEqual(problem("Done", " "), "empty")


class Catalog(unittest.TestCase):
    def test_every_translation_matches_its_english_string(self):
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        self.assertEqual(catalog["sourceLanguage"], "en")
        found = []
        for english, entry in catalog["strings"].items():
            for language, localization in entry.get("localizations", {}).items():
                why = problem(english, localization["stringUnit"]["value"])
                if why:
                    found.append(f"{language}: {english!r}: {why}")
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
